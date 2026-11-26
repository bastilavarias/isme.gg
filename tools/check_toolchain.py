"""Validate the shared Android toolchain and detect tracked checkout mutations."""
import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]


def read_toolchain(root=ROOT):
    pins = json.loads((root / "toolchain.json").read_text(encoding="utf-8"))
    for field in ("flutter", "dart", "gradle", "androidGradlePlugin", "kotlin", "androidBuildTools"):
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
    properties = (root / "android/gradle.properties").read_text(encoding="utf-8")
    expected = [
        (wrapper, r"^distributionUrl=.*?/gradle-" + re.escape(pins["gradle"]) + r"-(?:bin|all)\.zip\s*$", "Gradle"),
        (settings, r'id\s+"com\.android\.application"\s+version\s+"' + re.escape(pins["androidGradlePlugin"]) + r'"', "AGP"),
        (settings, r'id\s+"org\.jetbrains\.kotlin\.android"\s+version\s+"' + re.escape(pins["kotlin"]) + r'"', "Kotlin"),
        (app, r"^\s*compileSdk\s+" + str(pins["androidSdk"]) + r"\s*$", "Android compile SDK"),
        (app, r'^\s*buildToolsVersion\s+"' + re.escape(pins["androidBuildTools"]) + r'"\s*$', "Android Build Tools"),
    ]
    for source, pattern, label in expected:
        if not re.search(pattern, source, re.M):
            raise ValueError(f"{label} differs from toolchain.json")
    for flag in ("android.newDsl", "android.builtInKotlin"):
        definitions = re.findall(r"^[ \t]*" + re.escape(flag) + r"(?=[ \t=:]).*", properties, re.M)
        if [line.strip() for line in definitions] != [f"{flag}=false"]:
            raise ValueError(f"android/gradle.properties must set {flag}=false once before Flutter runs")
    return pins


def check_flutter(pins):
    flutter = shutil.which("flutter")
    if not flutter:
        raise ValueError("Flutter SDK not found on PATH")
    output = subprocess.check_output([flutter, "--version", "--machine"], cwd=ROOT, text=True)
    info = json.loads(output)
    for pin, field, label in (("flutter", "frameworkVersion", "Flutter"), ("dart", "dartSdkVersion", "Dart")):
        if info.get(field) != pins[pin]:
            raise ValueError(f"{label} {pins[pin]} required; found {info.get(field, 'unknown')}")


def check_clean(root=ROOT):
    status = subprocess.check_output(
        ["git", "status", "--porcelain=v1", "--untracked-files=no"], cwd=root, text=True
    )
    if status.strip():
        # Print only file names/status, never the contents of build files.
        raise ValueError("Build changed tracked files; changes preserved:\n" + status.strip())


def check_debug_apk(path):
    required = {
        f"lib/{abi}/{library}"
        for abi in ("armeabi-v7a", "arm64-v8a", "x86_64")
        for library in ("libflutter.so", "libtorrent4j.so")
    }
    with ZipFile(path) as apk:
        missing = required.difference(apk.namelist())
    if missing:
        raise ValueError("Debug APK is missing native libraries:\n" + "\n".join(sorted(missing)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--check-flutter", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--debug-apk", type=Path)
    args = parser.parse_args()
    pins = check_gradle()
    if args.check_flutter:
        check_flutter(pins)
    if args.clean:
        check_clean()
    if args.debug_apk:
        check_debug_apk(args.debug_apk)
    if args.github_output:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            for field, value in pins.items():
                stream.write(f"{field}={value}\n")
    print("Shared Android toolchain checks passed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
