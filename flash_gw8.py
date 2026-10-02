import io, os, sys, subprocess
import sync_gwweb

env = os.environ.copy()
sync_gwweb.sync()
run = lambda args: subprocess.run(
    [sys.executable, '-m', 'platformio', 'run', '-e', 'gateway'] + args,
    cwd=r'D:\esp32\firmware', env=env, capture_output=True, text=True)

# Flash the firmware, then the LittleFS image (dashboard assets) so the
# embedded rescue web UI is present on first power-up.
results = []
results.append(('upload', run(['-t', 'upload', '--upload-port', 'COM8'])))
results.append(('uploadfs', run(['-t', 'uploadfs', '--upload-port', 'COM8'])))

log = ''
for name, p in results:
    log += '\n===== %s rc=%d =====\n' % (name, p.returncode)
    log += (p.stdout or '') + '\n' + (p.stderr or '')
io.open(r'D:\esp32\firmware\.pio_com8_gw2.log', 'w', encoding='utf-8',
        errors='replace').write(log)

code = max((p.returncode for _, p in results), default=0)
print('flash_gw8 rc=%d' % code)
print((results[-1][1].stdout or '')[-1400:])
sys.exit(code)