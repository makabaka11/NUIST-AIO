"""Update only the landing page's embedded downloads from published release assets."""
import argparse
import base64
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import quote


MARKER = re.compile(r'(<script type="application/json" id="release-downloads">\n)(.*?)(\n</script>)', re.S)
PROXY = 'https://gh-proxy.org/'
PACKAGES = {
    'Android': [('android-arm64-v8a.apk', '64 位 ARM · 推荐'), ('android-armeabi-v7a.apk', '32 位 ARM')],
    'iOS': [('ios-unsigned.ipa', '未签名 IPA')],
    'macOS': [('macos-arm64.zip', 'Apple 芯片'), ('macos-x86_64.zip', 'Intel 芯片')],
    'Windows': [('windows-x64.zip', '64 位便携版')],
}
UNIVERSAL = {'Android': ('android-universal.apk', 'ARM 通用版'),
             'macOS': ('macos-universal.zip', 'Apple / Intel 通用版')}


def version(tag):
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Website downloads require a stable version tag')
    return tuple(map(int, tag[1:].split('.')))


def manifest(release, repository):
    tag = release['tag_name']
    version(tag)
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Website downloads require a published stable release')
    assets = {a['name']: a for a in release['assets']}
    platforms = {}
    for platform, packages in PACKAGES.items():
        if not all(f'nuistaio-{tag}-{suffix}' in assets for suffix, _ in packages):
            if platform not in UNIVERSAL:
                raise ValueError(f'Missing website downloads for {platform}')
            packages = [UNIVERSAL[platform]]
        downloads = []
        for suffix, label in packages:
            name = f'nuistaio-{tag}-{suffix}'
            asset = assets.get(name)
            url = f'https://github.com/{repository}/releases/download/{quote(tag, safe="")}/{quote(name, safe="")}'
            if not asset or asset.get('size', 0) <= 0 or asset.get('browser_download_url') != url:
                raise ValueError(f'Missing or invalid published asset: {name}')
            downloads.append({'label': label, 'url': PROXY + url, 'size': asset['size']})
        platforms[platform] = downloads
    return {'version': tag, 'platforms': platforms}


def update(html, data):
    match = MARKER.search(html)
    if match is None or len(MARKER.findall(html)) != 1:
        raise ValueError('Expected one landing page download manifest')
    current = json.loads(match[2])
    if current.get('version') and version(current['version']) > version(data['version']):
        return html  # An older release finishing late must not roll back the site.
    payload = json.dumps(data, ensure_ascii=False, indent=2).replace('<', '\\u003c')
    return html[:match.start(2)] + payload + html[match.end(2):]


def github(path, payload=None):
    command = ['gh', 'api', path]
    if payload is not None:
        command += ['--method', 'PUT', '--input', '-']
    result = subprocess.run(command, input=None if payload is None else json.dumps(payload),
                            text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('GitHub website metadata update failed')
    return json.loads(result.stdout)


def publish(repository, branch, tag):
    release = github(f'repos/{repository}/releases/tags/{quote(tag, safe="")}')
    data = manifest(release, repository)
    for attempt in range(3):
        path = f'repos/{repository}/contents/index.html'
        source = github(path + '?ref=' + quote(branch, safe=''))
        html = base64.b64decode(source['content']).decode('utf-8')
        updated = update(html, data)
        if updated == html:
            print('Website downloads are already current')
            return
        try:
            github(path, {'message': f'ci: update website downloads for {tag}', 'branch': branch,
                          'sha': source['sha'], 'content': base64.b64encode(updated.encode()).decode()})
            print(f'Updated website downloads for {tag}')
            return
        except RuntimeError:
            if attempt == 2:
                raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--repository', required=True)
    parser.add_argument('--release-json', type=Path)
    parser.add_argument('--html', type=Path, default=Path('index.html'))
    parser.add_argument('--branch')
    parser.add_argument('--tag')
    args = parser.parse_args()
    if args.release_json:
        data = manifest(json.loads(args.release_json.read_text()), args.repository)
        args.html.write_text(update(args.html.read_text(), data))
    elif args.branch and args.tag:
        publish(args.repository, args.branch, args.tag)
    else:
        parser.error('Provide --release-json or both --branch and --tag')
