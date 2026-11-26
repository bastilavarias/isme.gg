"""Generate a small public Pages release feed from published GitHub releases."""
import argparse
import json
import re
import subprocess
from pathlib import Path

REPO = "bastilavarias/isme.gg"
BASE = "https://github.com/" + REPO
STABLE = re.compile(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True, timeout=60).stdout


def stable(release):
    return not release.get("draft") and not release.get("prerelease") and bool(STABLE.fullmatch(release.get("tag_name", "")))


def assets(release):
    tag = release["tag_name"]
    result = {}
    for asset in release.get("assets", []):
        name = asset.get("name")
        if name in ("isme.apk", "update.json", "SHA256SUMS.txt") and asset.get("state") == "uploaded":
            expected = f"{BASE}/releases/download/{tag}/{name}"
            if asset.get("browser_download_url") == expected:
                result[name] = asset
    return result


def entry(release):
    tag = release["tag_name"]
    return dict(version=tag[1:], tag=tag, publishedAt=release.get("published_at"),
                notes=(release.get("body") or "")[:20000], releaseUrl=f"{BASE}/releases/tag/{tag}")


def build_feed(releases, latest=None, manifest=None):
    public = [r for r in releases if stable(r) and len(assets(r)) == 3]
    if latest is None:
        return {"schema": 1, "latest": None, "history": []}
    if not stable(latest) or len(assets(latest)) != 3:
        raise ValueError("Latest stable release does not have the three required published assets")
    files = assets(latest)
    tag = latest["tag_name"]
    if (not isinstance(manifest, dict)
            or manifest.get("version") != tag[1:]
            or type(manifest.get("versionCode")) is not int
            or not 0 < manifest["versionCode"] <= 2100000000
            or manifest.get("packageId") != "gg.isme.tv.flutter"
            or manifest.get("asset") != "isme.apk"
            or manifest.get("minimumAndroidSdk") != 28
            or sorted(manifest.get("abis", [])) != ["arm64-v8a", "armeabi-v7a"]
            or type(manifest.get("bytes")) is not int
            or not 0 < manifest["bytes"] <= 200 * 1024 * 1024
            or manifest["bytes"] != files["isme.apk"].get("size")
            or not re.fullmatch(r"[0-9a-f]{64}", manifest.get("sha256", ""))):
        raise ValueError("Published update metadata does not match the APK")
    digest = files["isme.apk"].get("digest")
    if digest and digest != "sha256:" + manifest["sha256"]:
        raise ValueError("GitHub APK digest does not match update metadata")
    current = entry(latest)
    current.update(versionCode=manifest["versionCode"], bytes=manifest["bytes"],
                   sha256=manifest["sha256"], minimumAndroidSdk=28, abis=manifest["abis"],
                   downloadUrl=files["isme.apk"]["browser_download_url"])
    history = [entry(r) for r in public if r["tag_name"] != tag][:20]
    return {"schema": 1, "latest": current, "history": history}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    releases = json.loads(gh("api", f"repos/{REPO}/releases?per_page=100"))
    if any(stable(r) for r in releases):
        latest = json.loads(gh("api", f"repos/{REPO}/releases/latest"))
        if not stable(latest) or len(assets(latest)) != 3:
            raise ValueError("Invalid stable release; refusing to publish misleading download links")
        if not 0 < assets(latest)["update.json"].get("size", 0) <= 65536:
            raise ValueError("Invalid manifest size")
        manifest = json.loads(gh("release", "download", latest["tag_name"], "-R", REPO,
                                 "--pattern", "update.json", "--output", "-"))
        feed = build_feed(releases, latest, manifest)
    else:
        feed = build_feed(releases)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Website release:", feed["latest"]["version"] if feed["latest"] else "No public release yet")


if __name__ == "__main__":
    main()
