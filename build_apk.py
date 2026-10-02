import io,os,subprocess,sys,time,shutil

base=r'D:\esp32\mobile'
logf=r'D:\esp32\apk_build.log'
LOGS=open(logf,'w',encoding='utf-8')

def run(args,cwd=base,timeout=1500):
    en=os.environ.copy()
    en['ANDROID_HOME']=r'C:\Users\ADMIN\AppData\Local\Android\Sdk'
    en['ANDROID_SDK_ROOT']=en['ANDROID_HOME']
    en['JAVA_HOME']=r'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot'
    en['PATH']=r'C:\src\flutter\bin;'+r'C:\src\flutter\bin\cache\dart-sdk\bin;'+r'C:\Users\ADMIN\AppData\Local\Android\Sdk\platform-tools;'+en.get('PATH','')
    try:
        p=subprocess.run(args,cwd=cwd,env=en,capture_output=True,text=True,timeout=timeout)
    except subprocess.TimeoutExpired as e:
        print('TIMEOUT after %ss'%timeout); flush()
        out=getattr(e,'stdout',None) or ''; err=getattr(e,'stderr',None) or ''
        LOGS.write(out+'\n---STDERR---\n'+err+'\n'); LOGS.flush()
        return None
    LOGS.write('=== %r rc=%d ===\n'%(args,p.returncode))
    if p.stdout: LOGS.write(p.stdout+'\n')
    if p.stderr: LOGS.write(p.stderr+'\n')
    LOGS.flush()
    return p

def flush(): pass

# 1) backup manifest so perms can be re-applied
mfest=os.path.join(base,'android','app','src','main','AndroidManifest.xml')
orig=io.open(mfest,encoding='utf-8-sig',errors='replace').read()
shutil.copy2(mfest, mfest+'.precreate.bak')
print('manifest backed up (%d bytes)'%len(orig))

# 2) regenerate android scaffold (keeps lib/ + pubspec.yaml + manifest)
p=run([r'C:\src\flutter\bin\flutter.bat','create','--project-name','safetrails','--org','com.safetrails','--platforms','android','.'])
if p is None or p.returncode!=0:
    print('flutter create FAILED rc=%s'%(p.returncode if p else 'timeout')); sys.exit(1)

# 3) re-apply critical perms if create overwrote manifest
s=io.open(mfest,encoding='utf-8-sig',errors='replace').read()
needed=['BLUETOOTH_SCAN','BLUETOOTH_CONNECT','ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','BLUETOOTH']
missing=[n for n in needed if 'android.permission.'+n not in s]
if missing:
    ins='\n'.join('    <uses-permission android:name="android.permission.%s"/>'%n for n in missing)
    if '</manifest>' in s: s=s.replace('</manifest>',ins+'\n</manifest>')
    io.open(mfest,'w',encoding='utf-8',newline='').write(s)
    print('re-applied permissions: %s'%missing)
else:
    print('manifest perms already intact')

# ensure INTERNET (harmless)
if 'android.permission.INTERNET' not in s:
    io.open(mfest,'w',encoding='utf-8',newline='').write(s.replace('</manifest>','    <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>'))

# 4) ensure minSdk high enough for geolocator (21) + flutter_blue_plus (21)
ap=os.path.join(base,'android','app','build.gradle.kts')
if os.path.exists(ap):
    s=io.open(ap,encoding='utf-8-sig',errors='replace').read()
    s=s.replace('minSdk = flutter.minSdkVersion','minSdk = 23')
    io.open(ap,'w',encoding='utf-8',newline='').write(s)
    print('minSdk -> 23 in build.gradle.kts')

# 5) pub get + build release apk
run([r'C:\src\flutter\bin\flutter.bat','pub','get'])
run([r'C:\src\flutter\bin\flutter.bat','build','apk','--release'],timeout=2400)

# 6) locate artifact
import glob
arts=glob.glob(r'D:\esp32\mobile\build\app\outputs\flutter-apk\*.apk')
print('ARTIFACTS:',arts)
LOG=io.open(logf,encoding='utf-8',errors='replace').read()
print('log tail:')
print(LOG[-1200:])