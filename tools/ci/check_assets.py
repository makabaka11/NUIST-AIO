"""Fail publishing unless all four exact package files exist and are nonempty."""
from pathlib import Path
import sys


def expected_assets(tag):
    return [f'nuistaio-{tag}-{suffix}' for suffix in (
        'android-universal.apk', 'ios-unsigned.ipa',
        'macos-universal.zip', 'windows-x64.zip')]


def check(directory, tag):
    for name in expected_assets(tag):
        path = Path(directory) / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f'Missing or empty release package: {name}')


if __name__ == '__main__':
    check(*sys.argv[1:])
