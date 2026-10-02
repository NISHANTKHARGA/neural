import io, os, re, sys

# Safe subprocess build wrapper: no shell, no quoting, byte-exact capture.
# Syncs the latest dashboard assets into the gateway LittleFS image first.
import subprocess
import sync_gwweb

env = os.environ.copy()
sync_gwweb.sync()
cmd = [sys.executable, '-m', 'platformio', 'run', '-e', 'gateway']
print('cwd=%s' % os.getcwd())
p = subprocess.run(cmd, cwd=r'D:\esp32\firmware', env=env,
                   capture_output=True, text=True)
out = p.stdout or ''
err = p.stderr or ''
log = out + '\n' + err
io.open(r'D:\esp32\firmware\.pio_gw_err2.log', 'w', encoding='utf-8', errors='replace').write(log)
print('rc=%d' % p.returncode)
print('stderr tail:')
print(err[-3000:])