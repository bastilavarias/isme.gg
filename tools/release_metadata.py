"""Validate a signed adaptive APK and generate its GitHub release metadata."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path
from zipfile import ZipFile

PACKAGE = "gg.isme.tv.flutter"
MAX_BYTES = 200 * 1024 * 1024


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def validate_badging(badging, version, code):
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != (PACKAGE, str(code), version):
        raise ValueError("APK package or version differs from release metadata")
    minimum = re.search(r"^(?:minSdkVersion|sdkVersion):'(\d+)'", badging, re.M)
    if not minimum or int(minimum[1]) != 28:
        raise ValueError("Unexpected minimum Android SDK")
    if "android.intent.category.LEANBACK_LAUNCHER" not in badging and "leanback-launchable-activity:" not in badging:
        raise ValueError("Android TV launcher entry missing")
    return int(minimum[1])


def generate(apk, output, version, code, aapt2, apksigner, expected_signer):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not 0 < code <= 2100000000:
        raise ValueError("Use a stable X.Y.Z version and positive Android versionCode")
    size = apk.stat().st_size
    if not 0 < size <= MAX_BYTES:
        raise ValueError("APK size is outside updater limits")
    minimum = validate_badging(run(aapt2, "dump", "badging", str(apk)), version, code)
    signing = run(apksigner, "verify", "--print-certs", str(apk))
    fingerprints = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)", signing)
    expected_signer = expected_signer.replace(":", "").strip().lower()
    if not re.fullmatch(r"[a-f0-9]{64}", expected_signer) or [x.lower() for x in fingerprints] != [expected_signer]:
        raise ValueError("APK is not signed by the expected permanent release certificate")
    abis = ("arm64-v8a", "armeabi-v7a")
    with ZipFile(apk) as archive:
        names = set(archive.namelist())
        native_abis = {name.split("/")[1] for name in names if name.startswith("lib/") and name.endswith(".so")}
        if native_abis != set(abis):
            raise ValueError("APK native libraries must target ARM64 and ARMv7 only")
        for abi in abis:
            if f"lib/{abi}/libflutter.so" not in names:
                raise ValueError(f"Flutter native library missing for {abi}")
            if not any(n.startswith(f"lib/{abi}/") and "torrent" in n.lower() and n.endswith(".so") for n in names):
                raise ValueError(f"Native playback library missing for {abi}")
    with apk.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    metadata = dict(version=version, versionCode=code, minimumAndroidSdk=minimum,
                    packageId=PACKAGE, asset="isme.apk", bytes=size, sha256=checksum,
                    abis=list(abis))
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(apk, output / "isme.apk")
    (output / "update.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  isme.apk\n", encoding="utf-8")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--code", type=int, required=True)
    parser.add_argument("--aapt2", required=True)
    parser.add_argument("--apksigner", required=True)
    parser.add_argument("--signer", required=True, help="Expected public signing certificate SHA-256 fingerprint")
    args = parser.parse_args()
    generate(args.apk, args.output, args.version, args.code, args.aapt2, args.apksigner, args.signer)
