import io,os,glob,sys,subprocess,time

def run(cmd,cwd=None,timeout=1400,env=None):
    en=os.environ.copy()
    if env: en.update(env)
    for k in ('ANDROID_HOME','ANDROID_SDK_ROOT'):
        if k not in en: en[k]=r'C:\Users\ADMIN\AppData\Local\Android\Sdk'
    en['JAVA_HOME']=r'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot'
    en['PATH']=r'C:\src\flutter\bin;'+r'C:\src\flutter\bin\cache\dart-sdk\bin;'+r'C:\Users\ADMIN\AppData\Local\Android\Sdk\platform-tools;'+en.get('PATH','')
    p=subprocess.run(cmd,cwd=cwd,env=en,capture_output=True,text=True,timeout=timeout)
    return p

base=r'D:\esp32\mobile'
print('=== flutter --version ===')
p=run([r'C:\src\flutter\bin\flutter.bat','--version'],cwd=base)
print('rc=%d'%p.returncode); print((p.stdout or '')[-400:]); print((p.stderr or '')[-300:])

print('=== android scaffold presence ===')
for rel in ['android/build.gradle','android/build.gradle.kts','android/settings.gradle','android/settings.gradle.kts',
            'android/settings.gradle.kts','android/gradle/wrapper/gradle-wrapper.properties',
            'android/gradle.properties','android/app/build.gradle.kts','android/app/src/main/AndroidManifest.xml',
            'android/app/src/main/res/values/styles.xml','android/app/src/main/kotlin/',
            'android/local.properties','android/gradlew.bat',
            'ios/Podfile','ios/Runner/Info.plist',
            'lib/main.dart','pubspec.yaml','test/widget_test.dart','web/index.html','windows/','linux/','macos/','web/']:
    print('  %-58s %s'%(rel,'YES' if os.path.exists(os.path.join(base,rel)) else ''))

print('=== dart shared pkg referenced ===')
pub=io.open(os.path.join(base,'pubspec.yaml'),encoding='utf-8-sig',errors='replace').read()
for l in pub.splitlines():
    if 'path:' in l.import(l if False else ''): pass
for l in pub.splitlines():
    if 'safetrails_protocol' in l or 'shared' in l:
        print('  ',l.strip())
