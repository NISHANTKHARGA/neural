import io,re,os

# 1) REAL full error list from gateway build log
log=r'D:\esp32\firmware\.pio_gw_err.log'
seen=set()
print('=== distinct (file:line) ERRORS in gateway log ===')
for x in io.open(log,encoding='utf-8',errors='replace'):
    if 'error:' not in x: continue
    m=re.search(r'([\\/](?:src|libdeps)[^:\s]*\.(?:cpp|h)):(\d+):(\d+): error:',x)
    if not m: continue
    k=(m.group(1),m.group(2))
    if k in seen: continue
    seen.add(k)
    # next non-empty continuation lines for the primary message
    print('  %s:%s:%s'%(m.group(1),m.group(2),m.group(3)))
print('\n(totals: groupbysrc)'%'')

# 2) read the failing line exactly
p=r'D:\esp32\firmware\src\app\relay_engine.cpp'
L=io.open(p,encoding='utf-8-sig',errors='replace').read().splitlines()
print('\n=== relay_engine.cpp:70-85 ===')
for i in range(69,min(85,len(L))): print('%5d: %s'%(i+1,L[i]))
