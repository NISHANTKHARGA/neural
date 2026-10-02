import io,os,re

log=r'D:\esp32\firmware\.pio_gw_err.log'

print('=== distinct errors remaining in gateway build log (file:line => msg) ===')
errs={}
for x in io.open(log,encoding='utf-8',errors='replace').read().splitlines():
    if 'error:' not in x: continue
    m=re.search(r'([^\\/:*?"<>|\r\n]+?\.(?:cpp|h)):(\d+):(\d+): error:(.*)',x)
    if not m: continue
    f=m.group(1); ln=m.group(2)
    msg=m.group(4).strip()
    # Normalize: strip trailing "In file included from..." context lines handled separately.
    key=(f,ln)
    if key not in errs: errs[key]=msg[:150]
print(' TOTAL distinct: %d'%len(errs))
for k in sorted(errs): print('  %s:%s : %s'%(k[0],k[1],errs[k]))

print('\n=== relay_engine Inbound struct (source of push_back failure) ===')
p=r'D:\esp32\firmware\src\app\relay_engine.h'
L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
for i,x in enumerate(L):
    if re.search(r'Inbound|inboundBuf_|struct\b',x):
        print('  %4d: %s'%(i+1,x.strip()))

print('\n=== exact relay_engine.cpp:78 context ===')
p2=r'D:\esp32\firmware\src\app\relay_engine.cpp'
L2=io.open(p2,encoding='utf-8',errors='replace').read().splitlines()
for i in range(70,84):
    if i<len(L2): print('  %4d: %s'%(i+1,L2[i]))
