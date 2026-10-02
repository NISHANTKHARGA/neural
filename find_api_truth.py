import os,io,re,glob
home=os.path.expanduser('~')

def find(name,roots):
    out=[]
    for r in roots:
        for g in glob.glob(os.path.join(r,'**',name),recursive=True):
            out.append(g)
    return out

hdr_found={}
def first(name):
    for cand in [os.path.join(home,'.platformio'), os.path.join(home,'.platformio','libdeps'),
                 r'D:\esp32', r'D:\esp32\firmware', r'D:\esp32\.pio', r'C:\',
                 os.path.join(home,'Documents')]:
        if os.path.isdir(cand):
            g=find(name,[cand])
            if g: return g
    return None

# These four decide every one of my 7 edits. Print REAL signature lines.
checks=[
 ('NimBLEAddress.h',  r'NimBLEAddress\s*\('),
 ('NimBLEScan.h',     r'NimBLEScanResults\s+(start|getResults|clearResults)\s*\(|start\s*\('),
 ('SX1278.h',         r'setPacketMode|setDio0Action|setDioAction|setDio1Action|setDioAsRssi|setCRC|begin\s*\('),
]

for hname,pat in checks:
    g=first(hname)
    print('=== %s ==='%hname)
    if not g:
        print('   NOT FOUND in any probed root; telling you so is better than editing blind')
        continue
    p=g[0]; print('   at: %s'%p)
    try:
        L=io.open(p,'r',encoding='utf-8',errors='replace').read().splitlines()
    except: 
        print('   (cannot read)'); continue
    for i,x in enumerate(L):
        if re.search(pat,x):
            print('%6d: %s'%(i+1,x.strip()))
    print('')

# the radio lib that the code actually instantiates
print('=== RadioLib SX1278 methods (verbatim, so lora_link.cpp:24/28 gets real names) ===')
for r_ in [r'D:\esp32\firmware\.pio\libdeps', r'D:\esp32\.pio\libdeps', os.path.join(home,'.platformio')]:
    for g in glob.glob(os.path.join(r_,'**','SX1278.h'),recursive=True):
        L=io.open(g,'r',encoding='utf-8',errors='replace').read().splitlines()
        print('   at: %s'%g)
        for i,x in enumerate(L):
            if re.search(r'setPacketMode|setDio0Action|setDioAction|setDio1Action|setCRC|int16_t\s+begin|void\s+reset',x):
                print('%6d: %s'%(i+1,x.strip()))
        break
    else:
        continue
    break
