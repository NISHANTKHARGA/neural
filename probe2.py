import os,glob,io,re
root=r'D:\esp32\firmware'; src=os.path.join(root,'src')
def read(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f: return f.read().splitlines()
    except Exception as e: return ['!! %s: %s'%(p,e)]
home=os.path.expanduser('~')

def find_rel_header(rel):
    for env in ('relay','gateway'):
        p=os.path.join(home,'.platformio','libdeps',env,*rel.split('/'))
        if os.path.isfile(p): return p
    for g in [os.path.join(home,'.platformio','libdeps','*',*rel.split('/'))]:
        for f in glob.glob(g):
            if os.path.isfile(f): return f
    return None

print('=== [1] NimBLEAddress real ctors (2.2.0) - decides :35 in *.h and :61 in *.cpp ===')
h=find_rel_header('NimBLE-Arduino/src/NimBLEAddress.h')
print('header: %s'%h)
if h:
    L=read(h)
    for i in range(len(L)):
        if re.search(r'NimBLEAddress\s*\(|NimBLEAddress\(\)',L[i]): print('%4d: %s'%(i+1,L[i].strip()))

print('\n=== [2] NimBLEScan::start + getResults (2.2.0) - decides the :34 results line ===')
h=find_rel_header('NimBLE-Arduino/src/NimBLEScan.h')
print('header: %s'%h)
if h:
    L=read(h)
    for i in range(len(L)):
        if re.search(r'NimBLEScanResults|start\s*\(|getResults\s*\(|NimBLEScanResults getResults',L[i]): print('%4d: %s'%(i+1,L[i].strip()))

print('\n=== [3] ST_SVC_UUID real definition (the :37 not-declared + ble_server.cpp:39 createService) - is it ST_SVC_UUID or ST_SOS_SVC_UUID? ===')
cfg=read(os.path.join(src,'config.h'))
for i in range(len(cfg)):
    if re.search(r'ST_SVC|ST_SOS_SVC|#define\s+ST_SVC',cfg[i]): print('%4d: %s'%(i+1,cfg[i].strip()))
# also find where ST_SVC_UUID is USED vs DEFINED
def usage(pat):
    for p in glob.glob(os.path.join(src,'**','*.cpp'),recursive=True)+glob.glob(os.path.join(src,'**','*.h'),recursive=True):
        L=read(p)
        for i in range(len(L)):
            if re.search(pat,L[i]): print('   %s:%d: %s'%(os.path.relpath(p,src),i+1,L[i].strip()))
print('   -- usages of ST_SVC_UUID / ST_SOS_SVC_UUID:')
usage(r'\bST_SVC_UUID\b|\bST_SOS_SVC_UUID\b')

print('\n=== [4] RadioLib v7 SX1278 real methods (setPacketMode? setDio0Action? the compiler suggested setDio0Action) ===')
h=find_rel_header('RadioLib/src/SX1278.h') or find_rel_header('RadioLib/src/modules/SX127x/SX1278.h')
print('header: %s'%h)
if h:
    L=read(h)
    for i in range(len(L)):
        if re.search(r'setPacketMode|setDio0Action|setDioAction|setPacketMode',L[i]): print('%4d: %s'%(i+1,L[i].strip()))

print('\n=== [5] the lora_link.cpp lines calling them + ble_server setMaxLen/setScanResponse real 2.2.0 replacements ===')
for f in ['link/lora_link.cpp','ble/ble_server.cpp']:
    L=read(os.path.join(src,f))
    print('-- %s --'%f)
    for i in range(len(L)):
        if re.search(r'setPacketMode|setDioAction|setMaxLen|setScanResponse|setScanResponseData|setAdvertisementData',L[i]): print('%4d: %s'%(i+1,L[i].strip()))

print('\n=== [6] relay_engine.cpp:78 (the 6th error) ===')
L=read(os.path.join(src,'app','relay_engine.cpp'))
for i in range(74,82):
    if i<len(L): print('%4d: %s'%(i+1,L[i]))
