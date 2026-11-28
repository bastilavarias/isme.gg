#!/usr/bin/env bash
# Development only. No signing, publishing or system package installation.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in
    Linux) platform=linux ;;
    Darwin) platform=macos ;;
    *) echo "Use setupdesktop.ps1 on Windows." >&2; exit 2 ;;
esac
mode="${1:-run}"
case "$mode" in run|test|build) ;; *) echo "Usage: bash desktop/setup-unix.sh [run|test|build]" >&2; exit 2;; esac
if [[ -n "${ISME_FLUTTER_DIR:-}" && -x "$ISME_FLUTTER_DIR/bin/flutter" ]]; then
    flutter="$ISME_FLUTTER_DIR/bin/flutter"
    dart="$ISME_FLUTTER_DIR/bin/dart"
else
    flutter="$(command -v flutter)"
    dart="$(command -v dart)"
fi
cd "$root"
"$flutter" --version --machine | python3 -c 'import json,sys; p=json.load(open("toolchain.json")); f=json.load(sys.stdin); assert f["frameworkVersion"]==p["flutter"] and f["dartSdkVersion"]==p["dart"], "Flutter/Dart pin mismatch"'
"$dart" tools/prepare_fonts.dart
cd "$root/desktop"
if [[ ! -d "$platform" ]]; then
    "$flutter" create --platforms="$platform" --project-name ismegg_desktop --org gg.isme --no-pub --empty .
fi
# macOS sandbox/entitlements and native architecture still need device validation.
if [[ "$platform" == macos ]]; then
    for entitlements in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
        /usr/libexec/PlistBuddy -c 'Add :com.apple.security.network.client bool true' "$entitlements" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :com.apple.security.network.client true' "$entitlements"
        /usr/libexec/PlistBuddy -c 'Add :com.apple.security.network.server bool true' "$entitlements" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :com.apple.security.network.server true' "$entitlements"
    done
fi
mvn -B -f native-engine/pom.xml clean package
export ISME_DESKTOP_ENGINE="$root/desktop/native-engine/target"
"$flutter" pub get
if [[ "$mode" != run ]]; then
    "$flutter" analyze --no-pub --no-fatal-infos
    "$flutter" test --no-pub
fi
if [[ "$mode" == run ]]; then
    "$flutter" run -d "$platform" --no-pub
elif [[ "$mode" == build ]]; then
    "$flutter" build "$platform" --release --no-pub
    if [[ "$platform" == linux ]]; then
        bundle="$root/desktop/build/linux/x64/release/bundle"
        [[ -d "$bundle" ]] || { echo "Expected x64 Linux bundle missing"; exit 1; }
        engine="$bundle/engine"
    else
        apps=("$root"/desktop/build/macos/Build/Products/Release/*.app)
        [[ ${#apps[@]} -eq 1 && -d "${apps[0]}" ]] || { echo "Expected a single macOS app"; exit 1; }
        engine="${apps[0]}/Contents/MacOS/engine"
    fi
    mkdir -p "$engine"
    cp -R native-engine/target/classes native-engine/target/dependency "$engine/"
    if [[ ! -x "$engine/runtime/bin/java" ]]; then
        jlink --add-modules java.se,jdk.httpserver,jdk.unsupported,jdk.crypto.ec,jdk.zipfs --output "$engine/runtime" --strip-debug --no-header-files --no-man-pages
    fi
    echo "Experimental bundle generated. Review dependencies, licensing and platform signing before distribution."
fi
