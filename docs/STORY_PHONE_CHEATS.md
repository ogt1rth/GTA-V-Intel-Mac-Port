# Story phone Cheats

The custom phone overlay is in the player's existing
`x64/levels/gta5/script/script_wasm.rpf`: `cellphone_flashhand.ysc` and
`appcheats.ysc`. Its `WasmSandbox` command-line query used to return false in
Story mode.

`Scripts/prepare_story_phone_cheats.py` patches the already translated
`GET_COMMANDLINE_PARAM_EXISTS` handler. Only those two scripts receive true for
`WasmSandbox`. All other queries and scripts retain the original handler, so
Story mode, mission startup and save locations are unchanged. The patch is
idempotent and runs in normal preparation for future builds. It does not run
WASM translation.

On Mac the pause overlay also exposes Mod menu directly; Settings > Mod menu
opens the existing native cheats in both modes. Script-mod keys remain a
separate Mods button.

The launcher app icon is an AppIcon.appiconset, padded to square from the user's
Downloads/gta-v.png; HomeIcon uses the original artwork with aspect-fit sizing.

Validation: incremental Intel Catalyst build succeeded; only game_31.c was
recompiled among the translated engine files. Installed to
/Applications/GTA-V.app after retaining the previous app in
Build/AppBackups. The installed AppIcon.icns matches the build by SHA-256.
Rendered home artwork was checked and Story mode reached WORLD_READY with
Michael's saved game visible. Phone Cheats navigation remains unverified:
the computer-use tool repeatedly reported concurrent user changes, so automated
input was stopped. No cheat was activated during validation.
