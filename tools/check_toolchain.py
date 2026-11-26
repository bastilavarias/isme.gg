"""Validate the shared Android toolchain and detect tracked checkout mutations."""
import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_toolchain(root=ROOT):
    pins = json.loads((root / "toolchain.json").read_text(encoding="utf-8"))
    for field in ("flutter", "gradle", "androidGradlePlugin", "kotlin", "androidBuildTools"):
        if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", pins[field]):
            raise ValueError(f"Invalid version: {field}")
    if not re.fullmatch(r"\d+", pins["java"]) or type(pins["androidSdk"]) is not int:
        raise ValueError("Invalid Java or Android SDK version")
    return pins


def check_gradle(root=ROOT):
    pins = read_toolchain(root)
    wrapper = (root / "android/gradle/wrapper/gradle-wrapper.properties").read_text(encoding="utf-8")
    settings = (root / "android/settings.gradle").read_text(encoding="utf-8")
    app = (root / "android/app/build.gradle").read_text(encoding="utf-8")
    expected = [
        (wrapper, r"^distributionUrl=.*?/gradle-" + re.escape(pins["gradle"]) + r"-(?:bin|all)\.zip\s*$", "Gradle"),
        (settings, r'id\s+"com\.android\.application"\s+version\s+"' + re.escape(pins["androidGradlePlugin"]) + r'"', "AGP"),
        (settings, r'id\s+"org\.jetbrains\.kotlin\.android"\s+version\s+"' + re.escape(pins["kotlin"]) + r'"', "Kotlin"),
        (app, r"^\s*compileSdk\s+" + str(pins["androidSdk"]) + r"\s*$", "Android compile SDK"),
    ]
    for source, pattern, label in expected:
        if not re.search(pattern, source, re.M):
            raise ValueError(f"{label} differs from toolchain.json")
    return pins


def check_flutter(pins):
    flutter = shutil.which("flutter")
    if not flutter:
        raise ValueError("Flutter SDK not found on PATH")
    output = subprocess.check_output([flutter, "--version", "--machine"], cwd=ROOT, text=True)
    info = json.loads(output)
    if info["frameworkVersion"] != pins["flutter"]:
        raise ValueError(f"Flutter {pins['flutter']} required; found {info['frameworkVersion']}")


def check_clean(root=ROOT):
    status = subprocess.check_output(
        ["git", "status", "--porcelain=v1", "--untracked-files=no"], cwd=root, text=True
    )
    if status.strip():
        # Print only file names/status, never the contents of build files.
        raise ValueError("Build changed tracked files; changes preserved:\n" + status.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--check-flutter", action="store_true")
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()
    pins = check_gradle()
    if args.check_flutter:
        check_flutter(pins)
    if args.clean:
        check_clean()
    if args.github_output:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            for field, value in pins.items():
                stream.write(f"{field}={value}\n")
    print("Shared Android toolchain checks passed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
