"""Expose the existing phone Cheats app in Story without changing the game's start mode.
Only the phone UI and appcheats may see WasmSandbox as present. Other scripts retain
its real value, including main's Story mission startup. Reuses generated C.
"""
from pathlib import Path
from engine_names import fn
root = Path(__file__).resolve().parents[1]
number = fn('debug_commands::SetupScriptCommands()::scrWrapped_GET_COMMANDLINE_PARAM_EXISTS::Call(rage::scrThread::Info&)')
active = fn('rage::scrThread::GetActiveThread()')
head = f'void w2c_game_f{number}(w2c_game* instance, u64 var_p0) {{'
path = next(p for p in (root / 'Generated').glob('game_*.c') if head in p.read_text())
s = path.read_text()
start = s.index(head); end = s.index('\n}\n', start)
body = s[start:end]
marker = '/* Story phone Cheats: scoped WasmSandbox query. */'
if marker not in body:
    needle = '  if (var_i0) {goto var_B1;}\n'
    if body.count(needle) != 2:
        raise RuntimeError('Command-line handler changed; refusing an unverified patch')
    patch = f'''  {marker}
  if (!strcmp((const char *)wasm_rt_local_memory_base + var_l1, "WasmSandbox")) {{
    u64 phoneThread = w2c_game_f{active}(instance);
    const char *phoneScript = phoneThread ? (const char *)wasm_rt_local_memory_base + phoneThread + 428 : "";
    if (!strcmp(phoneScript, "cellphone_flashhand") || !strcmp(phoneScript, "appcheats")) {{
      var_i0 = 1u;
      goto var_B0;
    }}
  }}
'''
    body = body.replace(needle, needle + patch, 1)
    s = s[:start] + body + s[end:]
    path.write_text(s)
    print(f'Story phone Cheats: patched f{number} in {path.name}')
else:
    print('Story phone Cheats: already patched')
