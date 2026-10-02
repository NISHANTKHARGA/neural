import io,os,re

# Read the FULL saved gateway log and list every distinct (file,line) error,
# plus print context for each, so I can fix ALL of them in one pass.
log=r'D:\esp32\firmware\.pio_gw_err.log'
base=r'D:\esp32\firmware\src'
errs={}  # (file,line) -> list of first message fragments
order=[]
for x in io.open(log,encoding='utf-8',errors='replace').read().splitlines():
    if 'error:' not in x: continue
    m=re.search(r'(?:\\|/)([\w]+\.(?:cpp|h)):(\d+):\d+:\s*error:\s*(.*)',x)
    if not m: continue
    f=m.group(1); ln=int(m.group(2)); msg=m.group(3).strip()
    key=(f,ln)
    if key not in errs:
        errs[key]=[msg]; order.append(key)
    else:
        if len(errs[key])<4: errs[key].append(msg)

print('=== distinct (file:line) ERRORS in full gateway log: %d ==='%len(order))
for f,ln in order:
    print('\n--- %s:%d ---'%(f,ln))
    for msg in errs[(f,ln)]:
        print('    %s'%msg[:160])
    # print the source line that owns this error
    for root in [base, r'D:\esp32\firmware\src']:
        p=os.path.join(root,'ble' if f.startswith('ble') else 'link','')+'' if False else None
    # find the file under src
    import glob
    hits=[]
    for pat in [os.path.join(base,'**',f), os.path.join(base,f)]:
        hits+=glob.glob(pat,recursive=True)
    if hits:
        p=hits[0]
        L=io.open(p,encoding='utf-8',errors='replace').read().splitlines()
        for i in range(max(1,ln-2),min(len(L),ln+1)+1 if ln+1>=1 else 1):
            pass
        lo=max(1,ln-3); hi=min(len(L),ln+3)
        for i in range(lo,hi+1):
            mark='>>' if i==ln else '  '
            print('   %s%5d: %s'%(mark,i,L[i-1]))
