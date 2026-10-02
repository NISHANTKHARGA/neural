import io,os,re

base=r'D:\esp32\firmware\src'

def rd(p): return io.open(p,encoding='utf-8-sig',errors='replace').read()
def wr(p,s): io.open(p,'w',encoding='utf-8',newline='').write(s)

def rep(p,old,new,why):
    s=rd(p); n=s.count(old)
    if n==0: print('  !! %s NOT FOUND: <%s> [%s]'%(p,old[:60],why)); return
    wr(p,s.replace(old,new)); print('  ok %s : %s -> %s (%d) [%s]'%(p,old.strip()[:40],new.strip()[:40],n,why))

print('=== struct Inbound (exact) ===')
for p in [base+r'\app\relay_engine.h', base+r'\app\relay_engine.cpp']:
    L=rd(p).splitlines()
    for i,x in enumerate(L):
        if 'struct Inbound' in x or 'inboundBuf_.push_back' in x:
            for j in range(i,max(0,i-4)):
                pass
            print('  %s:%d'%(p,i+1))
            for k in range(i,min(i+8,len(L))): print('     %5d: %s'%(k+1,L[k]))

# ── fix ble_mesh.cpp: getDevice() returns const NimBLEAdvertisedDevice* in NimBLE 2.x ──
rep(base+r'\ble\ble_mesh.cpp',
    'NimBLEAdvertisedDevice d = results.getDevice(i);',
    'const NimBLEAdvertisedDevice* d = results.getDevice(i);',
    '2.x: getDevice returns const NimBLEAdvertisedDevice*')
rep(base+r'\ble\ble_mesh.cpp',
    '    std::string name = d.getName();',
    '    std::string name = (d ? d->getName() : "");',
    'deref')
rep(base+r'\ble\ble_mesh.cpp',
    '    bool isRelay = d.isAdvertisingService(svc);',
    '    bool isRelay = (d && d->isAdvertisingService(svc));',
    'deref')
rep(base+r'\ble\ble_mesh.cpp',
    '  p.addr = d.getAddress();',
    '  p.addr = (d ? d->getAddress() : NimBLEAddress());',
    'deref')
rep(base+r'\ble\ble_mesh.cpp',
    '  p.rssi = d.getRSSI();',
    '  p.rssi = (d ? (int8_t)d->getRSSI() : -127);',
    'deref')

# ── fix relay_engine.cpp:78 inboundBuf_.push_back({json,handle}) ──
rep(base+r'\app\relay_engine.cpp',
    '  inboundBuf_.push_back({json, handle});',
    '  Inbound in{json, handle};\n  inboundBuf_.push_back(in);',
    'explicit Inbound construction')
