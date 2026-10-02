import io,os,re,sys

base=r'D:\esp32\firmware\src'
log=r'D:\esp32\firmware\.pio_gw_err.log'

def rd(p): return io.open(p,encoding='utf-8-sig',errors='replace').read()
def wr(p,s): io.open(p,'w',encoding='utf-8',newline='').write(s)

print('=== ALL distinct (file:line) errors in gateway log ===')
errs={}
for x in rd(log).splitlines():
    if 'error:' not in x: continue
    m=re.search(r'([\w]+\.(?:cpp|h)):(\d+):\d+:\s*error:\s*(.*)',x)
    if not m: continue
    f=m.group(1); ln=int(m.group(2))
    if (f,ln) not in errs: errs[(f,ln)]=m.group(3).strip()[:150]
for (f,ln),msg in sorted(errs.items()):
    print('  %-24s %5d  %s'%(f,ln,msg))

print('\n=== relay_engine.h: struct Inbound ===')
L=rd(base+r'\app\relay_engine.h').splitlines()
for i,x in enumerate(L):
    if 'Inbound' in x:
        for j in range(max(0,i-2),min(len(L),i+6)):
            print('    %5d: %s'%(j+1,L[j]))
        print('    ----')

print('\n=== current exact lines that must change ===')
for p,lo,hi in [(base+r'\ble\ble_mesh.cpp',33,45),(base+r'\app\relay_engine.cpp',74,82)]:
    L=rd(p).splitlines()
    print('  --- %s ---'%p)
    for i in range(lo-1,min(hi,len(L))):
        print('    %5d: %s'%(i+1,L[i]))
