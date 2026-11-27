"""Require the installed version/build to have its own What's New builder."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(version, registry):
    if not re.fullmatch(r"\d+\.\d+\.\d+\+[1-9]\d*", version):
        raise ValueError("Expected stable version+versionCode")
    entries = re.findall(r"^\s*'([^']+)'\s*:\s*([A-Za-z_]\w*)\s*,\s*$",
                         registry, re.MULTILINE)
    matches = [builder for key, builder in entries if key == version]
    if len(matches) != 1 or sum(builder == matches[0] for _, builder in entries) != 1:
        raise ValueError(f"Register a unique owner-approved What's New builder for {version}")


def main():
    version = re.search(r"^version:\s*(\S+)\s*$",
                        (ROOT / "pubspec.yaml").read_text(), re.MULTILINE)
    if version is None:
        raise ValueError("Missing pubspec version")
    validate(version.group(1), (ROOT / "lib/whats_new/whats_new_registry.dart").read_text())
    print(f"What's New registration valid for {version.group(1)}")


if __name__ == "__main__":
    main()
