import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile
import release_metadata as release

BADGING = ("package: name='gg.isme.tv.flutter' versionCode='5' versionName='0.5.0'\n"
           "sdkVersion:'28'\nleanback-launchable-activity: name='gg.isme.tv.MainActivity'\n")
SIGNER = "a" * 64


class ReleaseMetadataTest(unittest.TestCase):
    def test_correct_badging(self):
        self.assertEqual(release.validate_badging(BADGING, "0.5.0", 5), 28)

    def test_reject_mismatched_version_package_sdk_and_tv_launcher(self):
        for invalid in (BADGING.replace("versionCode='5'", "versionCode='4'"),
                        BADGING.replace("gg.isme.tv.flutter", "gg.isme.tv.flutter.debug"),
                        BADGING.replace("sdkVersion:'28'", "sdkVersion:'29'"),
                        BADGING.split("leanback-launchable-activity")[0]):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                release.validate_badging(invalid, "0.5.0", 5)

    def test_generate_and_reject_wrong_signer(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / "test.apk"
            out = Path(tmp) / "release"
            with ZipFile(apk, "w") as z:
                for abi in ("arm64-v8a", "armeabi-v7a"):
                    z.writestr(f"lib/{abi}/libflutter.so", b"test")
                    z.writestr(f"lib/{abi}/libtorrent4j.so", b"test")
            with patch.object(release, "run", side_effect=[BADGING, f"Signer #1 certificate SHA-256 digest: {SIGNER}"]):
                release.generate(apk, out, "0.5.0", 5, "aapt2", "apksigner", SIGNER)
            metadata = json.loads((out / "update.json").read_text())
            self.assertEqual(metadata["sha256"], hashlib.sha256(apk.read_bytes()).hexdigest())
            self.assertEqual(metadata["bytes"], apk.stat().st_size)
            self.assertEqual(metadata["abis"], ["arm64-v8a", "armeabi-v7a"])
            self.assertEqual((out / "isme.apk").read_bytes(), apk.read_bytes())
            with patch.object(release, "run", side_effect=[BADGING, "Signer #1 certificate SHA-256 digest: " + "b"*64]), self.assertRaises(ValueError):
                release.generate(apk, out, "0.5.0", 5, "aapt2", "apksigner", SIGNER)

    def test_missing_abi(self):
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / "test.apk"
            with ZipFile(apk, "w") as z:
                z.writestr("lib/arm64-v8a/libflutter.so", b"test")
                z.writestr("lib/arm64-v8a/libtorrent4j.so", b"test")
            with patch.object(release, "run", side_effect=[BADGING, f"Signer #1 certificate SHA-256 digest: {SIGNER}"]), self.assertRaises(ValueError):
                release.generate(apk, Path(tmp) / "release", "0.5.0", 5, "aapt2", "apksigner", SIGNER)


if __name__ == "__main__":
    unittest.main()
