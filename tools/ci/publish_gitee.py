"""Optional Gitee mirror using its documented public API; never log credentials.

The matching source commit must already have been mirrored to Gitee. No git
credentials, school credentials, or signing files are sent as release assets.
"""
import http.client
import json
import os
from pathlib import Path
import secrets
import sys
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from check_assets import check, expected_assets

HOST = 'gitee.com'
BASE = '/api/v5/repos/ded_retr0/NUIST-AIO'


def api(method, path, fields=None, missing=False):
    data = None if fields is None else urlencode(fields).encode()
    request = Request('https://' + HOST + BASE + path, data=data, method=method,
                      headers={'Content-Type': 'application/x-www-form-urlencoded',
                               'User-Agent': 'NUIST-AIO-Release-CI'})
    try:
        with urlopen(request, timeout=90) as response:
            return json.load(response)
    except HTTPError as error:
        if missing and error.code == 404:
            return None
        raise RuntimeError(f'Gitee {method} failed: HTTP {error.code}') from None
    except Exception:
        raise RuntimeError('Gitee API request failed') from None


def upload(release_id, file, token):
    boundary = 'nuistaio-' + secrets.token_hex(16)
    prefix = (f'--{boundary}\r\nContent-Disposition: form-data; name="access_token"\r\n\r\n'
              f'{token}\r\n--{boundary}\r\nContent-Disposition: form-data; name="file"; '
              f'filename="{file.name}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode()
    suffix = f'\r\n--{boundary}--\r\n'.encode()
    connection = http.client.HTTPSConnection(HOST, timeout=300)
    try:
        connection.putrequest('POST', f'{BASE}/releases/{release_id}/attach_files')
        connection.putheader('Content-Type', f'multipart/form-data; boundary={boundary}')
        connection.putheader('Content-Length', str(len(prefix) + file.stat().st_size + len(suffix)))
        connection.endheaders()
        connection.send(prefix)
        with file.open('rb') as content:
            while chunk := content.read(1024 * 1024):
                connection.send(chunk)
        connection.send(suffix)
        response = connection.getresponse()
        if response.status not in (200, 201):
            raise RuntimeError(f'Gitee attachment upload failed: HTTP {response.status}')
        result = json.loads(response.read(2 * 1024 * 1024))
        if not isinstance(result, dict) or not isinstance(result.get('id'), int):
            raise RuntimeError('Gitee returned an invalid attachment')
    finally:
        connection.close()


def publish():
    token = os.environ.get('GITEE_TOKEN', '')
    if not token:
        message = 'Gitee mirror skipped: configure GITEE_TOKEN; default Gitee updates need mirrored releases.'
        print('::warning::' + message)
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as file:
                file.write('\n' + message + '\n')
        return
    tag = os.environ['RELEASE_TAG']
    commit = os.environ['GITHUB_SHA']
    check('dist', tag)
    # Refuse to silently point the release at a different branch revision.
    if api('GET', '/commits/' + quote(commit, safe=''), missing=True) is None:
        raise RuntimeError('Mirror the tagged source commit to Gitee before publishing')
    release = api('GET', '/releases/tags/' + quote(tag, safe=''), missing=True)
    fields = {'access_token': token, 'tag_name': tag, 'name': tag,
              'body': Path('RELEASE_NOTE.md').read_text(), 'prerelease': 'false'}
    if release is None:
        release = api('POST', '/releases', {**fields, 'target_commitish': commit})
    else:
        release = api('PATCH', f'/releases/{int(release["id"])}', fields)
    release_id = int(release['id'])
    existing = []
    for page in range(1, 11):
        batch = api('GET', f'/releases/{release_id}/attach_files?per_page=100&page={page}')
        if not isinstance(batch, list):
            raise RuntimeError('Gitee returned an invalid attachment list')
        existing.extend(batch)
        if len(batch) < 100:
            break
    for name in [*expected_assets(tag), 'SHA256SUMS.txt']:
        file = Path('dist') / name
        matches = [a for a in existing if a.get('name') == name]
        if matches:
            if len(matches) != 1 or matches[0].get('size') != file.stat().st_size:
                raise RuntimeError('Gitee attachment conflict; review existing release files before retrying')
            print(f'Keeping existing Gitee attachment: {name}')
            continue
        upload(release_id, file, token)
        print(f'Uploaded Gitee attachment: {name}')


if __name__ == '__main__':
    try:
        publish()
    except Exception as error:
        # Never include request URLs, response bodies, or token-bearing traceback.
        message = str(error) if isinstance(error, RuntimeError) else 'Gitee release publication failed'
        print('::error::' + message, file=sys.stderr)
        sys.exit(1)
