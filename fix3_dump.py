import io,os,re

base=r'D:\esp32\firmware\src'
log=r'D:\esp32\firmware\.pio_gw_err.log'

def rd(p): return io.open(p,encoding='utf-8-sig',errors='replace').read()
def wr(p,s): io.open(p,'w',encoding='utf-8',newline='').write(s)
def rep(p,old,new,why):
    s=rd(p); n=s.count(old)
    if n==0:
        print('  !! %s: NOT FOUND: <%s> [%s]'%(p,old[:60],why)); return
    wr(p,s.replace(old,new)); print('  ok  %s: %s -> %s (%d) [%s]'%(p,old.strip()[:44],new.strip()[:44],n,why))

# ── 0) dump ALL distinct errors currently in the log ──
print('=== distinct (file:line) errors in %s ==='%log)
errs={}
for x in rd(log).splitlines():
    if 'error:' not in x: continue
    m=re.search(r'([\\/]([\w]+\.(?:cpp|h))):(\d+):\d+:\s*error:\s*(.*)',x)
    if not m: continue
    f=m.group(2); ln=int(m.group(3))
    key=(f,ln)
    if key not in errs: errs[key]=m.group(4).strip()[:150]
for k in sorted(errs): print('  %s:%d  %s'%(k[0],k[1],errs[k]))

# ── 1) struct Inbound in relay_engine.h ──
print('\n=== struct Inbound (relay_engine.h) ===')
p=base+r'\app\relay_engine.h'
L=rd(p).splitlines()
start=None
for i,x in enumerate(L):
    if 'struct Inbound' in x and start is None: start=i
if start is not None:
    depth=0
    for i in range(start,len(L)):
        d=L[i].count('{')-L[i].count('}')
        print('  %5d: %s'%(i+1,L[i]))
        depth+=d
        if depth<=0 and i>start: break
else:
    print('  (struct Inbound not found in relay_engine.h)')
    # search whole tree
    import glob
    for g in glob.glob(base+r'\**\relay_engine.h',recursive=True):
        print('  in %s'%g)
