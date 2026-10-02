import io,os,re,glob
core=r'D:\esp32\firmware\.pio\libdeps\gateway'

def show(rel,pats,label):
    p=os.path.join(core,rel)
    print('\n=== %s (%s) ==='%(label,p))
    if not os.path.isfile(p): print('  MISSING'); return
    L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if any(re.search(pp,x) for pp in pats):
            print('  %5d: %s'%(i+1,x.strip()))

# a) NimBLEAddress::isNull still exists? (ble_mesh.cpp:84 calls target.isNull())
show(r'NimBLE-Arduino\src\NimBLEAddress.h',[r'isNull\s*\(','isEmpty'],'NimBLEAddress isNull')
# b) RadioLib SX127x dio edge constant + setPacketMode full signatures
show(r'RadioLib\src\modules\SX127x\SX127x.h',[r'setDio0Action\s*\(',r'setDio1Action\s*\(',r'setPacketMode\s*\('],'SX127x setDio*/setPacketMode (args!)')
# c) the RISING/edge macro RadioLib wants for the `dir` arg
show(r'RadioLib\src\RadioLib.h',[r'#define\s+(RISING|FALLING|RADIOLIB_DIO0|RADIOLIB_LOW|LOW|HIGH)'],'RadioLib edge macros')
# d) does config.h also define ST_BLE_CHAR_MAX (ble_server.cpp:44 setMaxLen arg) + does NimBLECharacteristic still have setMaxLen anywhere in 2.2? 
show(r'NimBLE-Arduino\src\NimBLECharacteristic.h',[r'setMaxLen'],'NimBLECharacteristic.setMaxLen in 2.2 (expected: none)')
p=os.path.join(core,r'..\gateway',r'NimBLE-Arduino\src\NimBLECharacteristic.h')
