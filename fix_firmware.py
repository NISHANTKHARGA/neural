import io,time
base=r'D:\esp32\firmware\src'

def rd(p):
    return io.open(p,encoding='utf-8-sig',errors='replace').read()

def wr(p,s):
    io.open(p,'w',encoding='utf-8',newline='').write(s)
    print('  wrote %s'%p)

def rep(p,old,new,why):
    s=rd(p)
    n=s.count(old)
    if n==0:
        print('  !! %s: %s NOT FOUND (skip, %s)'%(p,'<%s>'%old[:60],why)); return
    s=s.replace(old,new)
    wr(p,s)
    print('  ok  %s: %s -> %s (%d hit)'%(p,old.strip()[:50],new.strip()[:50],n))

# ── 1) NimBLE 2.2.0: NimBLEAddress has no const char* ctor —— use default ("none" sentinel) ──
rep(base+r'\ble\ble_mesh.h',
    'NimBLEAddress addr = NimBLEAddress("00:00:00:00:00:00");',
    'NimBLEAddress addr;',
    '2.x removed const char* ctor; default ctor = all-zero = "isNull"')
rep(base+r'\ble\ble_mesh.cpp',
    'NimBLEAddress best = NimBLEAddress("00:00:00:00:00:00");',
    'NimBLEAddress best;',
    'same 2.x ctor')
rep(base+r'\app\relay_engine.cpp',
    'NimBLEAddress("00:00:00:00:00:00")',
    'NimBLEAddress()',
    'same 2.x ctor')

# ── 2) NimBLE 2.2.0: NimBLEScan::start() returns bool; results via getResults() ──
rep(base+r'\ble\ble_mesh.cpp',
    'NimBLEScanResults results = NimBLEDevice::getScan()->start(3000, false);',
    'NimBLEDevice::getScan()->start(3000, false);\n  NimBLEScanResults results = NimBLEDevice::getScan()->getResults();',
    'start() returns bool in 2.x')

# ── 3) ST_SVC_UUID / ST_SOS_TX live in ble_server.h (ble_mesh.cpp only included config.h) ──
rep(base+r'\ble\ble_mesh.cpp',
    '#include "ble_mesh.h"\n\n#include "../core/packet.h"',
    '#include "ble_mesh.h"\n\n#include "../core/packet.h"\n#include "ble_server.h"',
    'ST_SVC_UUID & ST_SOS_TX are defined in ble_server.h:13-14')

# ── 4) NimBLE 2.2.0: setMaxLen removed (default max length is used) ──
rep(base+r'\ble\ble_server.cpp',
    '    if (c) c->setMaxLen(ST_BLE_CHAR_MAX);\n',
    '',
    '2.x removed NimBLECharacteristic::setMaxLen')

# ── 5) NimBLE 2.2.0: setScanResponse(bool) removed (default = no scan response) ──
rep(base+r'\ble\ble_server.cpp',
    '  adv->setScanResponse(false);\n',
    '',
    '2.x removed setScanResponse(bool)')

# ── 6) RadioLib 7.x: SX1278 has no 0-arg setPacketMode; packet mode is default after begin() ──
rep(base+r'\link\lora_link.cpp',
    '  radio_.setPacketMode();\n',
    '',
    'RadioLib 7 requires args; default is already packet mode')

# ── 7) RadioLib 7.x: setDioAction → setDio0Action(func, RISING) ──
rep(base+r'\link\lora_link.cpp',
    '  radio_.setDioAction(onLoraIrq);',
    '  radio_.setDio0Action(onLoraIrq, RISING);',
    'RadioLib 7 renamed to setDio0Action(dir)')

print('\nDONE — all substitutions applied (log above).')
