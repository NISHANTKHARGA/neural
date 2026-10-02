import re, io, os, glob
root=r'D:\esp32\firmware'
src=os.path.join(root,'src')

def read(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f:
            return f.read().splitlines()
    except Exception as e:
        return ['!! cannot read %s: %s' % (p,e)]

print('=== [1] NimBLE-Arduino pinned version ===')
ini=''
try:
    with io.open(os.path.join(root,'platformio.ini'),'r') as f: ini=f.read()
except Exception as e: ini='ERR %s'%e
for m in re.finditer(r'^.*NimBLE[^\r\n]*$', ini, re.M): print('  '+m.group(0).strip())
for m in re.finditer(r'^.*lib_deps[^\r\n]*$', ini, re.M): print('  '+m.group(0).strip())

print('\n=== [2] the 5 failing source areas (read verbatim, numbered) ===')

# A) ble_mesh.h + ble_mesh.cpp NimBLEAddress(const char[18])
h=os.path.join(src,'ble','ble_mesh.h')
L=read(h)
print('\n--- %s line 30-40 (struct Peer NimBLEAddress ctor) ---' % os.path.basename(h))
for i in range(29,41):
    if i < len(L): print('%3d: %s' % (i+1, L[i]))

c=os.path.join(src,'ble','ble_mesh.cpp')
L=read(c)
print('\n--- %s line 30-64 (scan callback, NimBLEAddress, ST_* constants, NimBLEScanResults) ---' % os.path.basename(c))
for i in range(29,64):
    if i < len(L): print('%3d: %s' % (i+1, L[i]))

s=os.path.join(src,'ble','ble_server.cpp')
L=read(s)
print('\n--- %s lines 30-95 (setMaxLen, setScanResponse, ST_* constants) ---' % os.path.basename(s))
for i in range(29,95):
    if i < len(L) and re.search(r'setMaxLen|setScanResponse|ST_|createService|createCharacteristic|setMaxIn|max_len|maxLen', L[i]): print('%3d: %s' % (i+1, L[i]))

l=os.path.join(src,'link','lora_link.cpp')
L=read(l)
print('\n--- %s lines 15-35 (setPacketMode, setDioAction vs SX1278 lib API) ---' % os.path.basename(l))
for i in range(14,35):
    if i < len(L): print('%3d: %s' % (i+1, L[i]))

print('\n=== [3] which ST_SOS_* / ST_SVC / RESCUE constants ACTUALLY exist vs what code uses ===')
names=[]
for p in glob.glob(os.path.join(src,'**','*.h'),recursive=True):
    for L in read(p):
        m=re.match(r'\s*#define\s+(ST_[A-Z0-9_]+)', L)
        if m: names.append(m.group(1))
names=sorted(set(names))
for n in names:
    if re.search(r'SOS|SVC|RESC|RES|ACK|ALARM|TX|RX', n): print('   #define %s' % n)

used=[]
for p in glob.glob(os.path.join(src,'**','*.cpp'),recursive=True):
    for i,L in enumerate(read(p)):
        for m in re.finditer(r'\b(ST_SOS_[A-Z0-9_]+|ST_SVC_[A-Z0-9_]*|ST_RESCUE\w*)\b', L):
            used.append((os.path.relpath(p,src),i+1,m.group(1)))
print('\n--- usages that MUST resolve (dedup) ---')
for u in sorted(set(used)): print('   %s:%d  %s' % u)

print('\n=== [4] LoRa lib actually installed (name+version decides setPacketMode/setDioAction reality) ===')
for pat in [os.path.join(root,'lib','*'), os.path.join(root,'.pio','libdeps','relay','*'), os.path.join(root,'.pio','libdeps','gateway','*')]:
    for d in sorted(glob.glob(pat)):
        base=os.path.basename(d)
        if re.match(r'(LoRa|RadioLib|SX12|MCCI|arduino-lorawan|heltec|Lora)', base, re.I):
            print('   %s' % base)
