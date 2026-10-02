import io,os,re,glob

core=r'D:\esp32\firmware\.pio\libdeps\gateway'

def show(rel, pats, label):
    p=os.path.join(core,rel)
    print('\n=== %s (%s) ==='%(label,p))
    if not os.path.isfile(p):
        print('  MISSING'); return
    L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
    for i,x in enumerate(L):
        if any(re.search(pp,x) for pp in pats):
            print('  %5d: %s'%(i+1,x.strip()))

show(r'NimBLE-Arduino\src\NimBLEScan.h', [r'NimBLEScan\s*\(', r'\bstart\s*\(', r'getResults\s*\(', r'clearResults\s*\(', r'erase\s*\('], 'NimBLEScan (start returns ?)')
show(r'NimBLE-Arduino\src\NimBLEScanResults.h', [r'getDevice\s*\(', r'getCount\s*\(', r'begin\s*\(', r'end\s*\('], 'NimBLEScanResults (getDevice ret type)')
show(r'NimBLE-Arduino\src\NimBLEAddress.h', [r'NimBLEAddress\s*\('], 'NimBLEAddress ctors')
show(r'NimBLE-Arduino\src\NimBLEUUID.h', [r'NimBLEUUID\s*\('], 'NimBLEUUID ctors')
show(r'NimBLE-Arduino\src\NimBLECharacteristic.h', [r'setMaxLen\s*\(', r'createCharacteristic\s*\(', r'setValue\s*\(', r'getValue\s*\('], 'NimBLECharacteristic (setMaxLen gone?) + NimBLEService createCharacteristic')
show(r'NimBLE-Arduino\src\NimBLEAdvertising.h', [r'setScanResponseData\s*\(', r'setScanResponse\s*\(', r'setAdvertisementData\s*\(', r'setName\s*\('], 'NimBLEAdvertising 2.x (scan response renamed)')
show(r'RadioLib\src\modules\SX127x\SX1278.h', [r'setPacketMode\s*\(', r'setDio[0-9]?Action\s*\(', r'setDio0Action\s*\(', r'setDio0Mode\s*\('], 'SX1278 (RadioLib 7.x packet/dio names)')
show(r'RadioLib\src\modules\SX127x\SX127x.h', [r'setPacketMode\s*\(', r'setDio[0-9]?Action\s*\(', r'setDioAction\s*\('], 'SX127x base (dies/packet)')
