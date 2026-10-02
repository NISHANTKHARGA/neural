import io,os,glob,subprocess,sys

base=r'D:\esp32\mobile'
print('=== pubspec.yaml (full android-relevant) ===')
s=io.open(os.path.join(base,'pubspec.yaml'),encoding='utf-8-sig',errors='replace').read()
for l in s.splitlines():
    if any(k in l.lower() for k in ('safetrails','path:','protocol','flutter_ble','geolocator','permission','version:','environment','sdk','nimble','lora')):
        print('   ',l)

print('\n=== android scaffold present? ===')
for rel in ['android/build.gradle','android/build.gradle.kts',
            'android/settings.gradle','android/settings.gradle.kts',
            'android/gradle/wrapper/gradle-wrapper.properties',
            'android/app/build.gradle','android/app/build.gradle.kts',
            'android/app/src/main/AndroidManifest.xml',
            'android/gradle.properties','android/local.properties',
            'android/gradlew','android/gradlew.bat',
            'android/app/src/main/kotlin','android/app/src/main/java',
            'ios/Podfile','linux/','windows/','web/','lib/main.dart','pubspec.yaml','analysis_options.yaml']:
    print('   %-52s %s'%(rel,'YES' if os.path.exists(os.path.join(base,rel)) else '--'))

print('\n=== shared dart pkg ===')
for r in sorted(glob.glob(r'D:\esp32\shared\protocol\dart\**',recursive=True))[:25]:
    print('   ',os.path.relpath(r,r'D:\esp32'))

print('\n=== tooling ===')
for cand in [r'C:\src\flutter\bin\flutter.bat',
             r'C:\Users\ADMIN\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat',
             r'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot\bin\java.exe',
             r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe']:
    print('   %-58s %s'%(cand,os.path.exists(cand)))
import subprocess
print('\n=== java -version ===')
for cand in [r'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot\bin\java.exe']:
    p=subprocess.run([cand,'-version'],capture_output=True,text=True)
    print('   ', (p.stderr or p.stdout).strip().splitlines()[0] if (p.stderr or p.stdout) else '?')
