import os,io,re,glob
home=os.path.expanduser('~')

# PlatformIO Core dir is NOT ~/.platformio on this box. Find it for real (the .pio/.platformio may be elsewhere).
cands=[]
for r in [r'D:\esp32\firmware\.pio', r'D:\esp32\.pio', os.path.join(home,'.platformio'),
          os.path.join(home,'.platformio','libdeps'), r'D:\esp32\firmware\.pio\libdeps']:
    if os.path.isdir(r): cands.append(r)
print('probe roots: %s'%cands)

def find_h(name,roots=None):
    rs=roots or cands
    for r in rs:
        for m in glob.glob(os.path.join(r,'**',name),recursive=True):
            if os.path.isfile(m): return m
    return None

h=find_h('NimBLEAddress.h')
print('\n=== NimBLEAddress.h: %s ==='%h)
if h:
    L=io.open(h,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'NimBLEAddress\s*\((\s|\()',x) or 'NimBLEAddress(' in x:
            print('  %5d: %s'%(i+1,x.strip()))

s=find_h('NimBLEScan.h')
print('\n=== NimBLEScan.h: %s ==='%s)
if s:
    L=io.open(s,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'NimBLEScanResults\s+(start|getResults|clearResults|start)\s*\(|getResults\s*\(',x) or 'start(' in x and 'NimBLEScan' in x:
            print('  %5d: %s'%(i+1,x.strip()))

sx=find_h('SX1278.h')
print('\n=== SX1278.h (RadioLib): %s ==='%sx)
if sx:
    L=io.open(sx,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'setPacketMode|setDioAction|setDio0Action|setDio1Action|packetMode|startReceive|setDirectSyncWord',x):
            print('  %5d: %s'%(i+1,x.strip()))

# config.h: ST_SVC_UUID? and ble_server.h: the UUID+characteristic constants
cc=os.path.join(r'D:\esp32\firmware\src','config.h')
print('\n=== config.h: does ST_SVC_UUID/ST_SOS_GATEWAY-ID live here (compiler says "not declared")? ===')
if os.path.isfile(cc):
    L=io.open(cc,encoding='utf-8-sig',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'ST_SVC_UUID|ST_SOS_TX|ST_SOS_RX|ST_SOS_BODY|ST_TOURIST|ST_ROLE_',x):
            print('  %5d: %s'%(i+1,x.strip()))
bsh=os.path.join(r'D:\esp32\firmware\src\ble','ble_server.h')
print('\n=== ble_server.h (the real home of ST_SVC_UUID + the SOS char constants) ===')
if os.path.isfile(bsh):
    L=io.open(bsh,encoding='utf-8-sig',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'#define\s+ST_',x):
            print('  %5d: %s'%(i+1,x.strip()))
