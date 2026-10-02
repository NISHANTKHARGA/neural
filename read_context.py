import os,io,re,glob
root=r'D:\esp32\firmware'
src=os.path.join(root,'src')
def read(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f: return f.read().splitlines()
    except Exception as e: return ['!! %s: %s'%(p,e)]

print('=== [A] config.h ST_* constants block verbatim — I need the REAL name that replaces ST_SOS_TX (compiler says only ST_SOS_BODY exists) ===')
c=read(os.path.join(src,'config.h'))
for i in range(len(c)):
    if re.search(r'#define\s+ST_(SOS|SVC|RESCUE|ALARM|BUZZ|LED|TOURIST|TOUR|ID|BODY|TX|RX|STATUS|HEART|SIGNAL|ADV|DATA)',c[i]):
        print('%3d: %s'%(i+1,c[i]))

print('\n=== [B] ble_mesh.cpp:28-64 FULL — the scan callback chain (34=scan results, 37=ST_SVC_UUID, 40=result->getAddress vs NimBLEAddress ctor, 47/49/61=peer addr) ===')
m=read(os.path.join(src,'ble','ble_mesh.cpp'))
for i in range(27,64):
    print('%3d: %s'%(i+1,m[i]))

print('\n=== [C] NimBLEScanResults: does NimBLEScan::start return results in 2.2.0, or bool + separate getResults()? (drives fix at :34) ===')
for cand in glob.glob(os.path.join(os.path.expanduser('~'),'.platformio','libdeps','relay','NimBLE-Arduino','src','NimBLEScan.h'),recursive=True)+glob.glob(os.path.join(os.path.expanduser('~'),'.platformio','packages','*','libraries','NimBLE*','src','NimBLEScan.h'),recursive=True):
    if os.path.isfile(cand):
        print('at: '+cand)
        L=read(cand)
        for i in range(len(L)):
            if re.search(r'start|getResults|NimBLEScanResults|class NimBLEScan',L[i]): print('   %3d: %s'%(i+1,L[i].strip()))
        break
