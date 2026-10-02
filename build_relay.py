import io,os,sys,subprocess

env=os.environ.copy()
cmd=[sys.executable,'-m','platformio','run','-e','relay']
p=subprocess.run(cmd,cwd=r'D:\esp32\firmware',env=env,capture_output=True,text=True)
out=p.stdout or ''
err=p.stderr or ''
log=out+'\n'+err
io.open(r'D:\esp32\firmware\.pio_relay_build.log','w',encoding='utf-8',errors='replace').write(log)
print('rc=%d'%p.returncode)
# distinct file:line errors
import re
seen={}
for x in log.splitlines():
    if 'error:' not in x: continue
    m=re.search(r'([\w]+\.(?:cpp|h)):(\d+):\d+:\s*error:\s*(.*)',x)
    if not m: continue
    k=(m.group(1),int(m.group(2)))
    if k not in seen: seen[k]=m.group(3).strip()[:140]
print('distinct errors: %d'%len(seen))
for k,v in sorted(seen.items()):
    print('  %s:%d  %s'%(k[0],k[1],v))
tail=log[-2500:]
print('--- log tail ---')
print(tail)
