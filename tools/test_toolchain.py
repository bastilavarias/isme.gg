import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from check_toolchain import ROOT, check_clean, check_gradle


class ToolchainTests(unittest.TestCase):
    def test_shared_pins_match_gradle(self):
        self.assertTrue(check_gradle()["flutter"])

    def test_gradle_drift_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for file in ("toolchain.json", "android/settings.gradle",
                         "android/gradle/wrapper/gradle-wrapper.properties", "android/app/build.gradle"):
                target = root / file
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / file, target)
            settings = root / "android/settings.gradle"
            settings.write_text(settings.read_text().replace(
                'id "com.android.application" version "8.13.1"',
                'id "com.android.application" version "99.0.0"'), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "AGP differs"):
                check_gradle(root)

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
