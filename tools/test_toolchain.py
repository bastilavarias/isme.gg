import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from check_toolchain import ROOT, check_clean, check_flutter, check_gradle


class ToolchainTests(unittest.TestCase):
    def test_shared_pins_match_gradle(self):
        self.assertTrue(check_gradle()["flutter"])

    def test_gradle_drift_detected(self):
        pins = check_gradle()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for file in ("toolchain.json", "android/settings.gradle",
                         "android/gradle/wrapper/gradle-wrapper.properties", "android/app/build.gradle",
                         "android/gradle.properties"):
                target = root / file
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / file, target)
            mutations = [
                ("android/settings.gradle",
                 f'id "com.android.application" version "{pins["androidGradlePlugin"]}"',
                 'id "com.android.application" version "99.0.0"', "AGP differs"),
                ("android/app/build.gradle", f'buildToolsVersion "{pins["androidBuildTools"]}"',
                 'buildToolsVersion "99.0.0"', "Android Build Tools differs"),
                ("android/gradle.properties", "android.newDsl=false", "", r"android\.newDsl"),
                ("android/gradle.properties", "android.builtInKotlin=false",
                 "android.builtInKotlin=false\nandroid.builtInKotlin=true", r"android\.builtInKotlin"),
            ]
            for file, original, replacement, error in mutations:
                with self.subTest(error=error):
                    target = root / file
                    content = target.read_text(encoding="utf-8")
                    self.assertIn(original, content)
                    target.write_text(content.replace(original, replacement), encoding="utf-8")
                    try:
                        with self.assertRaisesRegex(ValueError, error):
                            check_gradle(root)
                    finally:
                        target.write_text(content, encoding="utf-8")

    @patch("check_toolchain.shutil.which", return_value="flutter")
    @patch("check_toolchain.subprocess.check_output")
    def test_flutter_and_bundled_dart_must_match(self, version_output, _flutter):
        pins = check_gradle()
        versions = {"frameworkVersion": pins["flutter"], "dartSdkVersion": pins["dart"]}
        version_output.return_value = json.dumps(versions)
        check_flutter(pins)

        for field, label in (("frameworkVersion", "Flutter"), ("dartSdkVersion", "Dart")):
            with self.subTest(label=label):
                version_output.return_value = json.dumps({**versions, field: "0.0.0"})
                with self.assertRaisesRegex(ValueError, rf"{label} .* required; found 0\.0\.0"):
                    check_flutter(pins)

    def test_dirty_checkout_detected_and_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args):
                subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            git("init", "-q")
            git("config", "user.email", "test@example.invalid")
            git("config", "user.name", "Toolchain test")
            source = root / "settings.gradle"
            source.write_text("original", encoding="utf-8")
            git("add", "settings.gradle")
            git("commit", "-qm", "initial")
            (root / "metadata.properties").write_text("dummy local config", encoding="utf-8")
            check_clean(root)
            source.write_text("local change", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "tracked files"):
                check_clean(root)
            self.assertEqual(source.read_text(), "local change")
            git("add", "settings.gradle")
            with self.assertRaises(ValueError):
                check_clean(root)


if __name__ == "__main__":
    unittest.main()
