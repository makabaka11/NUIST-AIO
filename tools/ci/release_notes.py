"""Compose the shared GitHub/Gitee release body with fixed platform notes."""
from pathlib import Path
import re
import sys


PLATFORM_NOTES = """## 平台说明

- iOS IPA 为未签名版本，需自行签名后安装。
- 安卓端首选arm64-v8a，如不可用可以尝试`armeabi-v7a` 版"""


def compose(notes):
    lines = []
    replacing = False
    fence = None
    for line in notes.replace('\r\n', '\n').splitlines(keepends=True):
        marker = re.match(r'^ {0,3}(`{3,}|~{3,})', line)
        if marker:
            value = marker[1]
            if fence is None:
                fence = value
            elif value[0] == fence[0] and len(value) >= len(fence) and not line[marker.end():].strip():
                fence = None
        elif fence is None:
            heading = re.match(r'^ {0,3}(#{1,2})[ \t]+(.+?)\s*$', line)
            if heading:
                title = re.sub(r'[ \t]+#+$', '', heading[2]).strip()
                replacing = heading[1] == '##' and title == '平台说明'
        if not replacing:
            lines.append(line)
    return ''.join(lines).rstrip() + '\n\n' + PLATFORM_NOTES + '\n'


if __name__ == '__main__':
    source, destination = map(Path, sys.argv[1:])
    destination.write_text(compose(source.read_text(encoding='utf-8')), encoding='utf-8')
