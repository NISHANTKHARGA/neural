import io,os,sys,subprocess
env=os.environ.copy()
cmd=[sys.executable,'-m','platformio','run','-e','relay','-t','upload','--upload-port','COM8']
p=subprocess.run(cmd,cwd=r'D:\esp32\firmware',env=env,capture_output=True,text=True)
io.open(r'D:\esp32\firmware\.pio_com8_flash.log','w',encoding='utf-8',errors='replace').write((p.stdout or '')+'\n'+(p.stderr or ''))
print('rc=%d'%p.returncode)
t=(p.stdout or '')[-1500:]
print(t)
