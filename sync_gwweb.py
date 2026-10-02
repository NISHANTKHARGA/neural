import os, shutil, sys

# Bundles the shared dashboard frontend into the gateway's LittleFS image
# (firmware/data/www/). Called before every gateway build so the embedded web
# UI always matches the latest dashboard/ + shared/protocol/ sources.

ROOT = r'D:\esp32'
DASH = os.path.join(ROOT, 'dashboard')
SHARED = os.path.join(ROOT, 'shared', 'protocol')
DEST = os.path.join(ROOT, 'firmware', 'data', 'www')


def sync():
    shared_dest = os.path.join(DEST, 'shared')
    os.makedirs(shared_dest, exist_ok=True)
    pairs = [
        (os.path.join(DASH, 'index.html'), os.path.join(DEST, 'index.html')),
        (os.path.join(DASH, 'style.css'), os.path.join(DEST, 'style.css')),
        (os.path.join(DASH, 'app.js'), os.path.join(DEST, 'app.js')),
        (os.path.join(SHARED, 'packet.js'), os.path.join(shared_dest, 'packet.js')),
    ]
    for src, dst in pairs:
        shutil.copyfile(src, dst)
        print('sync_gwweb: %s -> %s' % (src, dst))
    return True


if __name__ == '__main__':
    sys.exit(0 if sync() else 1)