"""Fail publishing unless all architecture-specific package files exist and are nonempty."""
from pathlib import Path
import sys


def expected_assets(tag):
    return [f'nuistaio-{tag}-{suffix}' for suffix in (
        'android-armeabi-v7a.apk', 'android-arm64-v8a.apk', 'ios-unsigned.ipa',
        'macos-arm64.zip', 'macos-x86_64.zip', 'windows-x64.zip')]


def check(directory, tag):
    for name in expected_assets(tag):
        path = Path(directory) / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f'Missing or empty release package: {name}')


if __name__ == '__main__':
    check(*sys.argv[1:])
