# Building on Intel macOS

Run these commands from the root of this fork, `GTA-V-Intel-Mac-Port`. This guide builds an x86_64 Mac Catalyst application; it does not provide game files.

## Prerequisites

- An Intel Mac running macOS 13 or later, with enough free space for your game files, generated C, shaders and Xcode build products. 16 GB RAM is recommended; compilation is memory intensive.
- Full Xcode with Mac Catalyst and the Metal compiler installed. Command Line Tools alone are insufficient. Launch Xcode once to finish its setup and accept its license.
- Git, Python 3, CMake and XcodeGen. Homebrew users can install the latter tools with `brew install python cmake ninja xcodegen`.
- Your own supported game folder containing `data/` and `b/8b0b5899ed/`. Other engine versions are rejected by preparation.
- An Intel-native `pgmsl` shader translator compatible with `app/ShaderTool/pgmsl.cc`.

Check the selected toolchain:

```sh
xcode-select -p
xcodebuild -version
xcrun --find metal
command -v python3 cmake xcodegen
```

If the selected developer directory is only CommandLineTools, select your installed Xcode in Xcode Settings › Locations before building.

## Required Intel shader translator

The upstream downloadable `pgmsl` is ARM-only. On Intel, supply a trusted x86_64 build through `PGMSL`:

```sh
export PGMSL="/absolute/path/to/pgmsl"
file "$PGMSL"
test -x "$PGMSL"
```

The output of `file` must include x86_64. The translator must implement this repository's shader reflection and binding conventions; a generic Tint executable is not a substitute.

To build the translator yourself, use `app/ShaderTool/build_pgmsl.sh` with a compatible Dawn/Tint source checkout at `app/Tools/dawn` and its host CMake build. Build Tint's `tint_cmd_tint_cmd` target first, then run:

```sh
cd app
mkdir -p Build
MAC_ARCH=x86_64 TINT_BUILD="/absolute/path/to/tint-host-build" \
  OUT="$PWD/Build/pgmsl" bash ShaderTool/build_pgmsl.sh
cd ..
export PGMSL="$PWD/app/Build/pgmsl"
```

**The matching Dawn revision and its dependency setup are not currently pinned or automated by this fork.** Supplying a compatible native translator remains a fresh-build prerequisite; these instructions do not claim that an arbitrary latest Dawn checkout will compile. Keep its applicable license notices with any redistributed tool.

## Build and package

```sh
export MAC_ARCH=x86_64
export PYTHON="$(command -v python3)"
export PGMSL="/absolute/path/to/x86_64/pgmsl"
JOBS=3 ./build_mac_app.sh --mirror "/absolute/path/to/your/game-folder"
```

Preparation builds checksum-verified WABT 1.0.42 from source on Intel, translates the supplied engine to C, applies the native-host patches and prepares shaders. The Mac build compiles native dependencies, generates the Xcode project, and builds a Release x86_64 Catalyst app with local ad-hoc signing. The first complete engine build can take a long time; do not use an ARM executable as an Intel workaround.

If the compiler is killed or memory pressure is excessive, retry with `JOBS=1`. Subsequent builds can reuse unchanged compiler outputs. Do not delete `app/Build` unless you intend to rebuild those outputs.

Outputs:

```text
app/Build/Mac/Build/Products/Release-maccatalyst/GTA-V.app
app/Build/xcodebuild-mac.log
GTA-V-Intel-Mac-Port.zip
```

Launch and verify the packaged architecture:

```sh
file "app/Build/Mac/Build/Products/Release-maccatalyst/GTA-V.app/Contents/MacOS/GTA-V"
codesign --verify --deep --strict "app/Build/Mac/Build/Products/Release-maccatalyst/GTA-V.app"
open "app/Build/Mac/Build/Products/Release-maccatalyst/GTA-V.app"
```

The app is locally signed, not notarized. Verify the origin of downloaded software; use macOS's normal Privacy & Security controls for software you trust.

## Troubleshooting

- **Intel requires a native shader translator:** set `PGMSL` to the compatible executable described above.
- **Bad CPU type in executable:** inspect the failing tool with `file`; replace it with an x86_64 build.
- **Metal compiler missing:** install the Metal toolchain/components offered by your Xcode version.
- **Unsupported engine or missing files:** use the supported layout from your own files; do not bypass the version checks.
- **Build succeeded but FPS drops later:** compilation does not validate sustained gameplay. Check the local runtime log and macOS power/thermal limits; performance is hardware dependent.

Generated game-engine C, shader outputs and app bundles are for local use and remain ignored. Do not attach them to GitHub issues or publish them as source releases.
