import io,os

base=r'D:\esp32\firmware\src'

def rd(p): return io.open(p,encoding='utf-8-sig',errors='replace').read()
def wr(p,s): io.open(p,'w',encoding='utf-8',newline='').write(s)
def rep(p,old,new,why):
    s=rd(p); n=s.count(old)
    if n==0: print('  !! %s: NOT FOUND: <%s> [%s]'%(p,old[:60],why)); return
    wr(p,s.replace(old,new)); print('  ok %s: [%s]'%(p,why))

# ── 1) NimBLE 2.2: getDevice(i) returns const NimBLEAdvertisedDevice* ──
rep(base+r'\ble\ble_mesh.cpp',
    'for (int i = 0; i < results.getCount() && i < 12; i++) {\n    NimBLEAdvertisedDevice d = results.getDevice(i);\n    std::string name = d.getName();\n    bool isRelay = d.isAdvertisingService(svc);',
    'for (int i = 0; i < results.getCount() && i < 12; i++) {\n    const NimBLEAdvertisedDevice* d = results.getDevice(i);\n    if (!d) continue;\n    std::string name = d->getName();\n    bool isRelay = d->isAdvertisingService(svc);',
    'getDevice -> const ptr')

# ── 2) struct Inbound: add 2-arg ctor so push_back({json,handle}) works ──
rep(base+r'\app\relay_engine.h',
    'struct Inbound {\n    std::string json;\n    uint16_t handle = 0;\n  };',
    'struct Inbound {\n    Inbound() = default;\n    Inbound(const std::string& j, uint16_t h) : json(j), handle(h) {}\n    std::string json;\n    uint16_t handle = 0;\n  };',
    'Inbound needs ctors (non-aggregate due to DMI)')

# ── 3) make sure ble_mesh.cpp sees the UUID+char defines (ble_server.h) ──
rep(base+r'\ble\ble_mesh.cpp',
    '#include "ble_mesh.h"',
    '#include "ble_mesh.h"\n#include "ble_server.h"',
    'ST_SVC_UUID/ST_SOS_TX live in ble_server.h')
