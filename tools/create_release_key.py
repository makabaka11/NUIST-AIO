"""Create this project's local release key once; never replace existing keys."""
from pathlib import Path
import os
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
keystore = root / 'android/keystore/nuistaio-release.jks'
properties = root / 'android/key.properties'
if keystore.exists() or properties.exists():
    if keystore.is_file() and properties.is_file():
        print('Existing release signing files preserved.')
        raise SystemExit(0)
    raise SystemExit('Incomplete signing files exist; inspect them before continuing. No files were replaced.')
keytool = '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool'
if not Path(keytool).is_file():
    keytool = shutil.which('keytool')
if not keytool:
    raise SystemExit('A JDK with keytool is required.')
os.umask(0o077)
keystore.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(keystore.parent, 0o700)
store_password = secrets.token_hex(32)
key_password = secrets.token_hex(32)
environment = os.environ.copy()
environment['NUISTAIO_STORE_PASSWORD'] = store_password
environment['NUISTAIO_KEY_PASSWORD'] = key_password
subprocess.run([
    keytool, '-genkeypair', '-noprompt', '-storetype', 'JKS',
    '-keystore', str(keystore), '-alias', 'nuistaio-release',
    '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA',
    '-validity', '10000', '-dname', 'CN=NUIST AIO, OU=Mobile Apps, O=Retrsoft, C=CN',
    '-storepass:env', 'NUISTAIO_STORE_PASSWORD',
    '-keypass:env', 'NUISTAIO_KEY_PASSWORD',
], env=environment, check=True, stdout=subprocess.DEVNULL)
properties.write_text(
    'storeFile=../keystore/nuistaio-release.jks\n'
    'keyAlias=nuistaio-release\n'
    f'storePassword={store_password}\n'
    f'keyPassword={key_password}\n', encoding='utf-8')
os.chmod(keystore, 0o600)
os.chmod(properties, 0o600)
print('Created release keystore and local properties (mode 600); passwords were not printed.')
