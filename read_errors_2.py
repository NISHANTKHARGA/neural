import os,re,glob,io
root=r'D:\esp32\firmware'
src=os.path.join(root,'src')

def read(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f: return f.read().splitlines()
    except Exception as e: return ['!! %s: %s' % (p,e)]

print('=== [A] the constants that ACTUALLY exist in the tree (the errors want ST_SVC_UUID/ST_SOS_TX — I need the real names, only one of them was suggested: ST_SOS_BODY) ===')
allc=set()
for p in glob.glob(os.path.join(src,'**','*.h'),recursive=True):
    for L in read(p):
        m=re.match(r'\s*#define\s+(ST_[A-Z0-9_]+)',L)
        if m: allc.add(m.group(1))
for c in sorted(allc):
    if re.search(r'SOS|SVC|RESCUE|RESC|ACK|ALARM|BUZZ|LED|BUTTON|TOURIST|BRDC|BODY|TX|RX|MESH|PWR',c): print('   '+c)

print('\n=== [B] NimBLEAddress header REAL ctor list (this is what decides the fix at ble_mesh.h:35 and ble_mesh.cpp:61) ===')
hdr=None
for cand in [os.path.join(os.path.expanduser('~'),'.platformio','libdeps','relay','NimBLE-Arduino','src','NimBLEAddress.h'),
             os.path.join(os.path.expanduser('~'),'.platformio','packages','framework-arduinoespressif32','libraries','NimBLE-Arduino','src','NimBLEAddress.h')]:
    if os.path.isfile(cand): hdr=cand; break
if hdr:
    print('at: '+hdr)
    for L in read(hdr):
        if re.search(r'NimBLEAddress\s*\(',L): print('   '+L.strip())
else:
    print('NOT under libdeps/relay or packages — searching the whole pio tree...')
    for g in glob.glob(os.path.join(os.path.expanduser('~'),'.platformio','**','NimBLEAddress.h'),recursive=True):
        print('candidate: '+g)
        for L in read(g):
            if re.search(r'NimBLEAddress\s*\(',L): print('   '+L.strip())
        break

print('\n=== [C] the LoRa lib actually pinned — what class is lora_link.cpp:24/28 calling into, and the REAL method names \n    (setPacketMode + setDioAction were rejected; NimBLE is ble, so this is the LORA_LINK wrapper or the SX1278 lib) ===')
lp=os.path.join(src,'link','lora_link.cpp')
for i,L in enumerate(read(lp),1):
    if re.search(r'\.(setPacketMode|setDioAction|setDio0Action|begin|reset|setPins|setSpreading|setCoding|setBandwidth|setFrequency|startReceive|listen)',L):
        print('lora_link.cpp:%3d: %s' % (i,L.strip()))

print('\n--- the SX1278 header that defines those methods (find the lib) ---')
hits=[]
for p in glob.glob(os.path.join(os.path.expanduser('~'),'.platformio','libdeps','relay','*','*'),recursive=False):
    pass
# search pinning hint instead
ini=open(os.path.join(root,'platformio.ini')).read()
for m in re.finditer(r'^.*(lora|LoRa|sx127|RadioLib|MCCI).*$',ini,re.M):
    print('   ini: '+m.group(0).strip())
