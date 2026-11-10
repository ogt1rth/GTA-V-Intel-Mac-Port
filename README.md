# GTA-V-Intel-Mac-Port

A Mac Catalyst build toolchain and native runtime focused on Intel Macs. The app is named **GTA-V** and uses Metal graphics, keyboard and mouse input, and controllers.

Derived from and forked from [kevinerikjs/gta5-macos-port](https://github.com/kevinerikjs/gta5-macos-port). Credit belongs to the upstream authors and contributors; their license and copyright notices are retained.

## Game files and rights

**No proprietary game archives, game WebAssembly binary, generated game-engine C, game shaders, or soundtrack are distributed in this repository.** Supply your own lawfully obtained, compatible game files locally. Do not upload them in commits, issues, pull requests, or releases.

The build translates your supplied WebAssembly engine into C using a patched WABT `wasm2c`, then compiles that C and this project's native host into a Mac application. It also translates supplied shaders for Metal. This repository is a toolchain and runtime, not a copy of the game or an official Rockstar product.

This does **not** mean the repository is free of copyright: its open-source code and bundled third-party components have their own copyrights and licenses. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The project is not affiliated with or endorsed by Rockstar Games or Take-Two Interactive. Game names and trademarks belong to their respective owners.

## Build on an Intel Mac

See [the Intel build guide](docs/BUILD_INTEL.md) for prerequisites, the required native shader translator, troubleshooting, and output paths.

With full Xcode, CMake, XcodeGen, Python 3, a compatible **x86_64** `pgmsl` shader translator, and your own compatible game folder:

```sh
export MAC_ARCH=x86_64
export PYTHON="$(command -v python3)"
export PGMSL="/absolute/path/to/x86_64/pgmsl"
JOBS=3 ./build_mac_app.sh --mirror "/absolute/path/to/your/game-folder"
```

The native Intel shader translator is a required external build prerequisite; it is not included, and the upstream ARM-only prebuilt cannot run on Intel. A fresh clone is not a one-command build until this prerequisite is supplied.

Outputs:

- App: `app/Build/Mac/Build/Products/Release-maccatalyst/GTA-V.app`
- Local package: `GTA-V-Intel-Mac-Port.zip`
- Build log: `app/Build/xcodebuild-mac.log`

Build outputs may contain material generated from your supplied game files. They are ignored by Git and must be reviewed separately before any distribution. A successful build does not establish redistribution rights or guarantee a sustained frame rate.

## Use

Open the built app, select your local game folder, and choose Story mode or Sandbox. The supported web-build layout contains `data/` and `b/8b0b5899ed/`; preparation checks the engine version before translating it. No game download is supplied here.

Settings and the in-game mod menu use a fullscreen menu, readable rows, a fixed top position and a panel that fits its contents. The mod menu groups Vehicles, Player, World and Story cheats. Escape closes the menu; arrow keys and Enter navigate. Vehicle selection and deeper settings use the shared settings presentation.

Settings › Mods manages installed mods; see [docs/MODS.md](docs/MODS.md). Script mods use keyboard input. Graphics and audio quality remain configurable by the player.

Saves, installed mods, preferences and the local `native-port.log` live under:

```text
~/Library/Containers/io.github.playgta5ios.app/Data/Documents
```

The retained bundle identifier preserves existing local data. Local diagnostics are not uploaded automatically. The original loading/settings backgrounds and GTA logo assets are included for the interface. These images remain copyrighted artwork belonging to their respective rights holders; they are not covered by the project's MIT license.

## Publishing this source

See [the publication checklist](docs/PUBLISHING.md). Generated engine sources, game data, logs, private credentials, app bundles and packages must remain excluded. The upstream MIT notice and third-party license notices must remain in the repository.
