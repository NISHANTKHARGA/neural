import io,os,re,sys
p=r'D:\esp32\mobile\pubspec.yaml'
s=io.open(p,encoding='utf-8-sig',errors='replace').read()
print('bytes=%d'%len(s))
# required: android applicationId + minSdk (flutter_blue_plus needs 19+; geolocator 21+)
a=io.open(r'D:\esp32\mobile\android\app\build.gradle',encoding='utf-8-sig',errors='replace').read() if os.path.exists(r'D:\esp32\mobile\android\app\build.gradle') else ''
b=io.open(r'D:\esp32\mobile\android\app\build.gradle.kts',encoding='utf-8-sig',errors='replace').read() if os.path.exists(r'D:\esp32\mobile\android\app\build.gradle.kts') else ''
print('gradle file:', 'kts' if b else 'groovy' if a else 'MISSING')
g=(a or b)
import re
print('applicationId:', re.findall(r'applicationId\s*[= ]+\s*"(.*?)"',g))
print('minSdk:', re.findall(r'minSdk\s*[= ]+\s*(\d+)',g))
print('targetSdk:', re.findall(r'targetSdk\s*[= ]+\s*(\d+)',g))
print('cp numberFormat:', re.findall(r'numberFormat\s*[= ]+\s*(\d+)',g))
# check shared protocol dart pkg exists
print('shared dart pkg:', os.path.isdir(r'D:\esp32\shared\protocol\dart'))
print('--- pubspec deps ---')
for l in s.splitlines():
    if l.strip().startswith(('flutter_','geolocator','provider','permission_','shared_pref','safetrails','  sdk','environment','web_socket','http')):
        print('   ',l)
