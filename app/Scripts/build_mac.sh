#!/bin/sh
# The Mac app (GTA-9): the iPhone app built for Intel and Apple Silicon Macs through Mac Catalyst.
# Writes Build/Mac/Build/Products/Release-maccatalyst/GTA-V.app (signed to run on this Mac).
set -eu
MAC_ARCH="${MAC_ARCH:-$(uname -m)}"
case "$MAC_ARCH" in arm64|x86_64) ;; *) echo "Unsupported Mac architecture: $MAC_ARCH" >&2; exit 1 ;; esac
export MAC_ARCH
PY="${PYTHON:-/usr/bin/python3}"
cd "$(dirname "$0")/.."
# The packaging entry point has just completed prepare.py's identical patch sequence.
# Standalone builds still refresh all patches, as before.
case "${1:-}" in ""|--prepared) ;; *) echo "Usage: $0 [--prepared]" >&2; exit 1 ;; esac
if [ "${1:-}" != --prepared ]; then
# The same engine patches as the iPhone build, read from build_native.sh so the two lists can't drift.
grep -E '^python3 Scripts/(generate_imports|prepare_)' Scripts/build_native.sh | while IFS= read -r command; do
  command="${command%%#*}"
  "$PY" ${command#python3 }
done
fi
"$PY" Scripts/build_opus.py --sdk maccatalyst
"$PY" Scripts/build_blink.py --sdk maccatalyst
"$PY" Scripts/build_metal_shaders.py "${PG_SHADER_DIR:-Build/Inputs/shaders}" --sdk maccatalyst
xcodegen generate --spec project.yml
# The bundled libarchive is iPhone-only; the Mac links macOS's own (project.yml, -larchive).
python3 - <<'PYFILTER'
from pathlib import Path
project = Path('GTA-V-Intel-Mac-Port.xcodeproj/project.pbxproj')
text = project.read_text()
needle = '/* libarchive.xcframework in Frameworks */ = {isa = PBXBuildFile; '
if needle not in text:
    raise SystemExit('Could not find the libarchive build-file entry to restrict it to iOS.')
text = text.replace(needle, needle + 'platformFilter = ios; ', 1)
project.write_text(text)
PYFILTER
# PG_NO_STATS=1: the developer's own test builds send no play stats (App/Analytics.swift).
set --
if [ -n "${PG_NO_STATS:-}" ]; then set -- "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) PG_NO_STATS"; fi
# Profile-guided optimization (GTA-172/216), as build_ipa.sh: PG_PGO_PROFILE (.profdata) and PG_ORDER_FILE (hot functions).
if [ -n "${PG_PGO_PROFILE:-}" ]; then set -- "$@" "OTHER_CFLAGS=\$(inherited) -fprofile-instr-use=$PG_PGO_PROFILE -Wno-profile-instr-unprofiled"; fi
if [ -n "${PG_ORDER_FILE:-}" ]; then set -- "$@" "OTHER_LDFLAGS=\$(inherited) -Wl,-order_file,$PG_ORDER_FILE"; fi
xcodebuild -project GTA-V-Intel-Mac-Port.xcodeproj -scheme GTA-V-Intel-Mac-Port \
  -configuration Release -destination "platform=macOS,variant=Mac Catalyst,arch=${MAC_ARCH}" \
  -derivedDataPath Build/Mac -jobs "${MAC_JOBS:-3}" ARCHS="$MAC_ARCH" ONLY_ACTIVE_ARCH=YES \
  GCC_OPTIMIZATION_LEVEL=2 SWIFT_OPTIMIZATION_LEVEL=-O DEBUG_INFORMATION_FORMAT=dwarf \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=App/Mac.entitlements \
  "$@" build
