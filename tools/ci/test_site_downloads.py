import base64
import json
import unittest
from unittest.mock import patch

from site_downloads import PACKAGES, PROXY, UNIVERSAL, manifest, publish, update


REPOSITORY = 'makabaka11/NUIST-AIO'


def release(tag='v0.5.1'):
    names = [f'nuistaio-{tag}-{suffix}' for packages in PACKAGES.values() for suffix, _ in packages]
    return {'tag_name': tag, 'draft': False, 'prerelease': False, 'assets': [
        {'name': name, 'size': 1024,
         'browser_download_url': f'https://github.com/{REPOSITORY}/releases/download/{tag}/{name}'}
        for name in names]}


def page(data):
    return '<h1>Keep this</h1><script type="application/json" id="release-downloads">\n' + json.dumps(data) + '\n</script><footer>Keep that</footer>'


class SiteDownloadsTest(unittest.TestCase):
    def test_assets_have_proxy_prefix_and_architecture_order(self):
        data = manifest(release(), REPOSITORY)
        self.assertEqual([len(files) for files in data['platforms'].values()], [2, 1, 2, 1])
        self.assertIn('arm64-v8a', data['platforms']['Android'][0]['url'])
        self.assertIn('macos-arm64', data['platforms']['macOS'][0]['url'])
        for files in data['platforms'].values():
            for file in files:
                self.assertTrue(file['url'].startswith(PROXY + 'https://github.com/' + REPOSITORY + '/releases/download/'))

    def test_invalid_or_incomplete_releases_never_write_links(self):
        for mutate in [lambda r: r.update(draft=True), lambda r: r.update(prerelease=True),
                       lambda r: r['assets'].pop(), lambda r: r['assets'][0].update(size=0),
                       lambda r: r['assets'][0].update(browser_download_url='https://other.test/file')]:
            data = release()
            mutate(data)
            with self.assertRaises(ValueError):
                manifest(data, REPOSITORY)

    def test_existing_universal_release_remains_downloadable(self):
        data = release('v0.5.0')
        for platform in ('Android', 'macOS'):
            data['assets'] = [asset for asset in data['assets']
                              if not any(suffix in asset['name'] for suffix, _ in PACKAGES[platform])]
            name = f'nuistaio-v0.5.0-{UNIVERSAL[platform][0]}'
            data['assets'].append({'name': name, 'size': 1024,
                                   'browser_download_url': f'https://github.com/{REPOSITORY}/releases/download/v0.5.0/{name}'})
        result = manifest(data, REPOSITORY)
        self.assertEqual(len(result['platforms']['Android']), 1)
        self.assertEqual(len(result['platforms']['macOS']), 1)
        self.assertIn('universal', result['platforms']['Android'][0]['url'])

    def test_update_preserves_surroundings_and_never_downgrades(self):
        original = page({})
        current = update(original, manifest(release(), REPOSITORY))
        self.assertTrue(current.startswith('<h1>Keep this</h1>'))
        self.assertTrue(current.endswith('<footer>Keep that</footer>'))
        self.assertEqual(update(current, manifest(release(), REPOSITORY)), current)
        self.assertEqual(update(current, manifest(release('v0.5.0'), REPOSITORY)), current)
        with self.assertRaises(ValueError):
            update('<html>Missing manifest</html>', manifest(release(), REPOSITORY))

    def test_concurrent_edit_is_reread_before_retry(self):
        first = {'sha': 'old', 'content': base64.b64encode(page({}).encode()).decode()}
        second = {'sha': 'new', 'content': base64.b64encode(page({}).replace('Keep this', 'Concurrent edit').encode()).decode()}
        with patch('site_downloads.github') as api, patch('builtins.print'):
            api.side_effect = [release(), first, RuntimeError('Conflict'), second, {}]
            publish(REPOSITORY, 'main', 'v0.5.1')
        payload = api.call_args.args[1]
        self.assertEqual(payload['sha'], 'new')
        self.assertIn('Concurrent edit', base64.b64decode(payload['content']).decode())


if __name__ == '__main__':
    unittest.main()
