import os,io,re,glob

ROOT=r'D:\esp32\firmware'
SRC=os.path.join(ROOT,'src')

def read(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f: return f.read().splitlines()
    except Exception as e: return ['!! %s: %s'%(p,e)]

def find_header(relname, envs=('relay','gateway')):
    for env in envs:
        d=os.path.join(os.path.expanduser('~'),'.platformio','libdeps',env,relname)
        if os.path.isfile(d): return d
    for g in glob.glob(os.path.join(os.path.expanduser('~'),'.platformio','libdeps','*',relname)) + \
              glob.glob(os.path.join(os.path.expanduser('~'),'.platformio','packages','**',relname),recursive=True):
        return g
    return None

print('=== [A] config.h: EVERY ST_#define + the two ST_ understood from the SOS section (this decides the real names at the 37/109/111 sites) ===')
cfg=read(os.path.join(SRC,'config.h'))
for i in range(len(cfg)):
    m=re.match(r'\s*#define\s+(ST_[A-Z0-9_]+)\s*\(?\"?([^\"\s)]*)',cfg[i])
    if m: print('%4d: #define %-24s = %s'%(i+1,m.group(1),m.group(2)))

print('\n=== [B] ble_mesh.h + ble_mesh.cpp: the exact API-drift lines (35, 34, 37, 40, 61, 109, 111) with enough room to see the WHOLE call ===')
hm=read(os.path.join(SRC,'ble','ble_mesh.h'))
print('-- ble_mesh.h:33-38 (NimBLEAddress member '':35'') --')
for i in range(32,38):
    if i<len(hm): print('%4d: %s'%(i+1,hm[i]))
hc=read(os.path.join(SRC,'ble','ble_mesh.cpp'))
for start,end,tag in ((32,42,'ble_mesh.cpp:33-41 (NimBLEScan start=true + NimBLEScanResults + NimBLEUUID svc + NimBLEAdvertisedDevice)'),
                      (58,64,'ble_mesh.cpp:59-63 (pickPeer NimBLEAddress best)'),
                      (106,112,'ble_mesh.cpp:107-111 (ST_SVC_UUID + ST_SOS_TX usage)'),):
    print('-- %s --'%tag)
    for i in range(start,end):
        if i<len(hc): print('%4d: %s'%(i+1,hc[i]))

print('\n=== [C] NimBLEAddress REAL ctors (heads off the "const char[18]" fix at :35/:61 AND the "getScan()->start returns bool" at :34) ===')
na=find_header('NimBLE-Arduino','src/NimBLEAddress.h')
na=find_header('NimBLE-Arduino/src/NimBLEAddress.h') or find_header('NimBLEAddress.h')
print('header: %s'%na)
if na:
    H=read(na)
    for i in range(len(H)):
        if re.search(r'NimBLEAddress\s*\(',H[i]) or re.search(r'explicit NimBLEAddress',H[i]):
            print('%5d: %s'%(i+1,H[i].strip()))

print('\n=== [D] NimBLEScan: does start() return NimBLEScanResults in 2.2.0 (decides the :34 fix shape) ===')
ns=find_header('NimBLEScan.h')
print('header: %s'%ns)
if ns:
    H=read(ns)
    for i in range(len(H)):
        if re.search(r'NimBLEScanResults|start\(|getResults|void start|results',H[i]):
            print('%5d: %s'%(i+1,H[i].strip()))

print('\n=== [E] RadioLib SX1278: real method list setPacketMode/setDio0Action + the LoRa wrapper class the link wraps ===')
sx=find_header('RadioLib/src/SX1278.h') or find_header('SX1278.h')
print('header: %s'%sx)
if sx:
    H=read(sx)
    for i in range(len(H)):
        if re.search(r'setPacket|setDio0Action|setDioAction|setCurrentLimit|setDioAsRssi|packetMode|begin\(|reset\(',H[i]):
            print('%5d: %s'%(i+1,H[i].strip()))

print('\n=== [F] the lora_link.cpp actual lines (24 + 28) so the fix matches the wrapper type ===')
ll=read(os.path.join(SRC,'link','lora_link.cpp'))
for i in range(20,31):
    if i<len(ll): print('%4d: %s'%(i+1,ll[i]))

print('\n=== [G] ble_server.cpp: the setMaxLen (:44) + setScanResponse (:82) real context ===')
bs=read(os.path.join(SRC,'ble','ble_server.cpp'))
for i in range(41,47):
    if i<len(bs): print('%4d: %s'%(i+1,bs[i]))
print('...')
for i in range(79,85):
    if i<len(bs): print('%4d: %s'%(i+1,bs[i]))

print('\n=== [H] relay_engine.cpp:78 (the other NimBLEAddress no-matching-ctor) ===')
re_=read(os.path.join(SRC,'app','relay_engine.cpp'))
for i in range(75,81):
    if i<len(re_): print('%4d: %s'%(i+1,re_[i]))
