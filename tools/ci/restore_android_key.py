"""Restore CI secrets only. Never generate or replace the release key."""
import base64
import os
from pathlib import Path


def properties_escape(value):
    # Java Properties uses ISO-8859-1 and backslash escapes.
    result = []
    for c in value:
        if c in '\\:=#! ':
            result.append('\\' + c)
        elif c in '\n\r\t':
            result.append({'\n': '\\n', '\r': '\\r', '\t': '\\t'}[c])
        elif ord(c) > 127:
            result.extend('\\u' + f'{int.from_bytes(part, "big"):04x}' for part in
                          [c.encode('utf-16-be')[i:i+2] for i in range(0, len(c.encode('utf-16-be')), 2)])
        else:
            result.append(c)
    return ''.join(result)


def restore():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Signing restoration is restricted to GitHub Actions')
    names = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_STORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']
    if any(not os.environ.get(name) for name in names):
        raise SystemExit('Configure all four Android release signing secrets using the existing key')
    key = Path('android/keystore/nuistaio-release.jks')
    properties = Path('android/key.properties')
    if key.exists() or properties.exists():
        raise SystemExit('Refusing to overwrite existing release signing files')
    try:
        data = base64.b64decode(''.join(os.environ[names[0]].split()), validate=True)
        if not data:
            raise ValueError()
    except ValueError:
        raise SystemExit('Invalid ANDROID_KEYSTORE_BASE64') from None
    key.parent.mkdir(parents=True, exist_ok=True)
    key.write_bytes(data)
    key.chmod(0o600)
    values = {'storeFile': '../keystore/nuistaio-release.jks',
              'storePassword': os.environ[names[1]], 'keyAlias': os.environ[names[2]],
              'keyPassword': os.environ[names[3]]}
    properties.write_text(''.join(f'{k}={properties_escape(v)}\n' for k, v in values.items()), encoding='ascii')
    properties.chmod(0o600)


if __name__ == '__main__':
    restore()
