import os,io,re,glob

root=r'D:\esp32\firmware'; src=os.path.join(root,'src')
def read(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f: return f.read().splitlines()
    except Exception as e: return ['!! %s: %s'%(p,e)]

print('=== [X] NimBLEAddress real ctors in the PINNED 2.2.0 (libdeps/relay takes priority; decides ble_mesh.h:35 + ble_mesh.cpp:61) ===')
for ownerbase in ['relay','gateway']:
    a=os.path.join(os.path.expanduser('~'),'.platformio','libdeps',ownerbase,'NimBLE-Arduino','src','NimBLEAddress.h')
    if os.path.isfile(a):
        print('using libdeps/%s: %s'%(ownerbase,a))
        L=read(a)
        ctx=0
        for i in range(len(L)):
            if re.search(r'NimBLEAddress\s*\(',L[i]) or re.search(r'operator const|fromString|static NimBLEAddress|char\s*\*',L[i]):
                ctx=6
            if ctx>0:
                print('%4d: %s'%(i+1,L[i])); ctx-=1
        break
    else:
        print('(no libdeps/%s copy yet)'%ownerbase)

print('\n=== [Y] the config.h ST_ constant names (errors demand ST_SVC_UUID / ST_SOS_TX but config actually declares ST_SOS_BODY — read the REAL block 118-152) ===')
c=read(os.path.join(src,'config.h'))
for i in range(117,152):
    if i<len(c) and (re.search(r'#define\s+ST_',c[i]) or c[i].strip()==''):
        print('%4d: %s'%(i+1,c[i]))

print('\n=== [Z] ble_mesh.cpp scan block 30-64 verbatim (fixes :34 getResults-only, :37 ST_SVC_UUID, :61 NimBLEAddress) ===')
m=read(os.path.join(src,'ble','ble_mesh.cpp'))
for i in range(29,65):
    if i<len(m): print('%4d: %s'%(i+1,m[i]))

print('\n=== [W] ble_server.cpp characteristic+advert blocks (44 setMaxLen, 82 setScanResponse) ===')
s=read(os.path.join(src,'ble','ble_server.cpp'))
for i in range(38,90):
    if i<len(s) and re.search(r'setMaxLen|setScanResponse|createCharacteristic|createService|NimBLEAdvertisementData|setAdvertisementData|setScanResponseData|setCompleteServices|setName',s[i]):
        print('%4d: %s'%(i+1,s[i]))

print('\n=== [V] lora_link.cpp 20-32 (setPacketMode :24, setDioAction :28) + the RadioLib env pin ===')
l=read(os.path.join(src,'link','lora_link.cpp'))
for i in range(19,33):
    if i<len(l): print('%4d: %s'%(i+1,l[i]))
ini=read(os.path.join(root,'platformio.ini'))
for ln in ini:
    if re.search(r'RadioLib|SX127|SX1278|NimBLE',ln): print('ini: %s'%ln.strip())
