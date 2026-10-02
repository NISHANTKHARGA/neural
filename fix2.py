import io,os,re,glob,sys

base=r'D:\esp32\firmware\src'
errlog=r'D:\esp32\firmware\.pio_gw_err.log'

def rd(p): return io.open(p,encoding='utf-8-sig',errors='replace').read()
def wr(p,s): io.open(p,'w',encoding='utf-8',newline='').write(s)
def rep(p,old,new,why):
    s=rd(p); n=s.count(old)
    if n==0: print('  !! %s: NOT FOUND: %s (skip: %s)'%(p,old[:70],why)); return
    wr(p,s.replace(old,new)); print('  ok  %s: %s -> %s (%d)   [%s]'%(p,old.strip()[:40],new.strip()[:40],n,why))

# ── 1) NimBLE 2.x: getDevice(i) returns a POINTER -> deref ──
rep(base+r'\ble\ble_mesh.cpp',
    'NimBLEAdvertisedDevice d = results.getDevice(i);',
    'const NimBLEAdvertisedDevice* d = results.getDevice(i);',
    '2.x NimBLEScanResults::getDevice returns const NimBLEAdvertisedDevice*')
rep(base+r'\ble\ble_mesh.cpp',
    '    std::string name = d.getName();',
    '    std::string name = (d ? d->getName() : "");',
    'pointer deref')
rep(base+r'\ble\ble_mesh.cpp',
    '    bool isRelay = d.isAdvertisingService(svc);',
    '    bool isRelay = (d && d->isAdvertisingService(svc));',
    'pointer deref')
rep(base+r'\ble\ble_mesh.cpp',
    '      p.addr = d.getAddress();',
    '      p.addr = (d ? d->getAddress() : NimBLEAddress());',
    'pointer deref')
rep(base+r'\ble\ble_mesh.cpp',
    '      p.rssi = d.getRSSI();',
    '      p.rssi = (d ? (int8_t)d->getRSSI() : -127);',
    'pointer deref')

# ── 2) relay_engine.cpp:78 — Inbound has a ctor; use explicit value ──
print('\n=== relay_engine.h struct Inbound ===')
p=base+r'\app\relay_engine.h'
L=rd(p).splitlines()
for i,x in enumerate(L):
    if 'Inbound' in x:
        for j in range(i,max(0,i-3)):
            if j+1<=len(L): pass
        print('  %5d: %s'%(i+1,x.strip()))
