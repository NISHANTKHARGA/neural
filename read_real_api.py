import os,io,re,glob

root=r'D:\esp32\firmware'
src=os.path.join(root,'src')
home=os.path.expanduser('~')

def readp(p):
    try:
        with io.open(p,'r',encoding='utf-8-sig',errors='replace') as f: return f.read().splitlines()
    except Exception: return []

def find_h(name):
    c=list(glob.glob(os.path.join(home,'.platformio','libdeps',name,'NimBLE-Arduino','src',os.path.basename(name).replace('','')),recursive=False))
    g=list(glob.glob(os.path.join(home,'.platformio','libdeps','*','NimBLE-Arduino','src','NimBLEScan.h')))
    if g: return g[0]
    return None

# signature of the 2.2.0 scan+address that the code must match
scan=find_h('NimBLEScan.h')
print('NimBLEScan.h at: %s'%scan)
if scan:
    L=readp(scan)
    for i,x in enumerate(L):
        if re.search(r'NimBLEScanResults\s+(start|getResults|clearResults|getResults)\s*\(',x):
            print('  %4d: %s'%(i+1,x.strip()))

addr=None
for g in glob.glob(os.path.join(home,'.platformio','libdeps','*','NimBLE-Arduino','src','NimBLEAddress.h')):
    addr=g; break
print('\nNimBLEAddress.h at: %s'%addr)
if addr:
    L=readp(addr)
    for i,x in enumerate(L):
        if re.search(r'NimBLEAddress\s*\(',x):
            print('  %4d: %s'%(i+1,x.strip()))

# the LoRa lib
lor=None
for g in glob.glob(os.path.join(home,'.platformio','libdeps','*','RadioLib','src','modules','SX127x','SX1278.h')):
    lor=g; break
print('\nSX1278.h at: %s'%lor)
if lor:
    L=readp(lor)
    for i,x in enumerate(L):
        if re.search(r'setPacketMode|setDio0Action|setDioAction|setPacketMode|packetMode|setCRC|setDio',x):
            print('  %4d: %s'%(i+1,x.strip()))
