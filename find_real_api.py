import os,io,re,glob

home=os.path.expanduser('~')

def find_first(fname, roots):
    for r in roots:
        g=glob.glob(os.path.join(r,'**',fname),recursive=True)
        if g: return g[0]
    return None

roots=[
    r'D:\esp32\firmware\.pio',
    r'D:\esp32\firmware',
    os.path.join(home,'.platformio'),
    os.path.join(home,'Documents'),
    r'C:\Users\ADMIN',
]

# 1) NimBLEAddress real ctors (2.2.0)
p=find_first('NimBLEAddress.h',roots)
print('=== [1] NimBLEAddress.h (%s) — real ctors (fix target :35 in ble_mesh.h, :61 in ble_mesh.cpp, relay_engine.cpp:78) ==='%p)
if p:
    L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if 'NimBLEAddress' in x and ('(' in x):
            print('  %5d: %s'%(i+1,x.strip()))

# 2) NimBLEScan start + getResults (the ble_mesh.cpp:34 conversion-from-bool error)
p=find_first('NimBLEScan.h',roots)
print('\n=== [2] NimBLEScan.h (%s) — start() returns bool(?) + getResults() (fix target ble_mesh.cpp:34) ==='%p)
if p:
    L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'start\(|getResults\(|NimBLEScanResults',x):
            print('  %5d: %s'%(i+1,x.strip()))

# 3) SX1278 (RadioLib) setPacketMode vs what lora_link.cpp:24 calls
p=find_first('SX1278.h',roots)
print('\n=== [3] SX1278.h (%s) — setPacketMode/setDioAction real names (fix target lora_link.cpp:24,28) ==='%p)
if p:
    L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if re.search(r'setPacketMode|setDioAction|setDio0Action|setDio1Action|setPacketMode|networkMode|setNetworkMode',x):
            print('  %5d: %s'%(i+1,x.strip()))

# 4) the constants files
for fname in ['ble_server.h','ble_mesh.h','config.h']:
    p=find_first(fname,roots)
    print('\n=== [4] %s (%s) ==='%(fname,p))
    if p:
        L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
        for i,x in enumerate(L):
            if ST_ in x or 'ST_SVC' in x or 'ST_SOS' in x:
                print('  %5d: %s'%(i+1,x.strip()))

# 5) the actual source lines that are wrong
src=os.path.join(r'D:\esp32\firmware\src')
for f,lo,hi in [('ble/ble_mesh.h',32,38),('ble/ble_mesh.cpp',32,42),('ble/ble_mesh.cpp',106,114),
                ('ble/ble_server.cpp',40,48),('ble/ble_server.cpp',78,86),
                ('link/lora_link.cpp',20,30),('app/relay_engine.cpp',74,82)]:
    pp=os.path.join(src,f)
    L=io.open(pp,encoding='utf-8',errors='replace').read().splitlines()
    print('\n=== [5] %s:%d-%d ==='%(f,lo,hi))
    for i in range(lo-1,min(hi,len(L))):
        print('  %5d: %s'%(i+1,L[i]))
