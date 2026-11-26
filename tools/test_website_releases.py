import unittest
from website_releases import BASE, build_feed


def release(tag="v0.0.0", draft=False, prerelease=False):
    return dict(tag_name=tag, draft=draft, prerelease=prerelease,
                published_at="2026-11-26T00:00:00Z", body="<script>untrusted notes</script>",
                assets=[dict(name=n, state="uploaded", size=s,
                             browser_download_url=f"{BASE}/releases/download/{tag}/{n}")
                        for n, s in (("isme.apk", 1000), ("update.json", 250), ("SHA256SUMS.txt", 75))])


def metadata():
    return dict(version="0.0.0", versionCode=4, minimumAndroidSdk=28,
                packageId="gg.isme.tv.flutter", asset="isme.apk", bytes=1000,
                sha256="a"*64, abis=["arm64-v8a", "armeabi-v7a"])


class ReleaseFeedTest(unittest.TestCase):
    def test_no_public_release(self):
        self.assertIsNone(build_feed([release(draft=True), release(prerelease=True)])["latest"])

    def test_stable_assets(self):
        current = release()
        feed = build_feed([current, release("v0.0.1", prerelease=True)], current, metadata())
        self.assertEqual(feed["latest"]["downloadUrl"], BASE + "/releases/download/v0.0.0/isme.apk")
        self.assertEqual(feed["latest"]["versionCode"], 4)
        self.assertEqual(feed["history"], [])

    def test_bad_manifest_or_url(self):
        current = release()
        with self.assertRaises(ValueError):
            build_feed([current], current, dict(metadata(), bytes=2000))
        current["assets"][0]["browser_download_url"] = "https://example.com/unsafe.apk"
        with self.assertRaises(ValueError):
            build_feed([current], current, metadata())

    def test_history_excludes_drafts_and_prereleases(self):
        current = release()
        previous = release("v0.0.1")
        feed = build_feed([current, previous, release("v0.0.2", draft=True)], current, metadata())
        self.assertEqual([r["tag"] for r in feed["history"]], ["v0.0.1"])


if __name__ == "__main__":
    unittest.main()
