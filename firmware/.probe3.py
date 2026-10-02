import io,os

# 1) real compile errors, unique, from the LAST full build log
log=r'D:\esp32\firmware\.pio_err.log'
print('=== unique (file:line) error rows in %s ==='%log)
seen=set()
L=io.open(log,encoding='utf-8',errors='replace').read().splitlines()
for x in L:
    if 'error:' not in x: continue
    # extract any  path:line:col
    import re
    m=re.search(r'([\w\\/]+\.(cpp|h)):(\d+):(\d+):',x)
    if m:
        k=(os.path.basename(m.group(1))+'%s'%m.group(2))
        p='%s:%s'%((m.group(1).split('\\')[-1]),m.group(2))
        key=(p,x[:120])
        if key[1] in seen: continue
        seen.add(key[1])
        print('  %-30s %s'%(p, m.group(4).rjust(3))+' : '+x.split('error:')[-1].strip()[:110])

print('\n=== [ble] really-open NimBLE 2.2.0 header constants we must match ===')
hdr=r'D:\esp32\firmware\.pio\libdeps\gateway\NimBLE-Arduino\src'
for h in ['NimBLEScan.h','NimBLEScanResults.h']:
    p=os.path.join(hdr,h)
    if not os.path.isfile(p): print('  MISS %s'%p); continue
    print('  --- %s ---'%h)
    for i,x in enumerate(io.open(p,encoding='utf-8',errors='replace').read().splitlines()):
        if x.strip().startswith('NimBLEScan') or re.search(r'(start|getResults|getDevice|getCount)\s*\(',x):
            print('   %5d: %s'%(i+1,x.strip()))
