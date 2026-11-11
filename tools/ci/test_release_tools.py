import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from release_metadata import metadata
from restore_android_key import properties_escape, restore
from check_assets import check, expected_assets
import publish_gitee


class ReleaseToolsTest(unittest.TestCase):
    def setUp(self):
        # Simulated publication must not emit real Actions warning commands.
        printer = patch("builtins.print")
        printer.start()
        self.addCleanup(printer.stop)

    def test_tag_version_and_notes_must_match(self):
        self.assertEqual(metadata('v0.5.0', 'version: 0.5.0+15\n', '# v0.5.0\n\nChanges\n')['build'], '15')
        for tag, version, notes in [
            ('v0.5.0-beta', '0.5.0+15', '# v0.5.0-beta\nChanges'),
            ('v0.5.0', '0.4.0+15', '# v0.5.0\nChanges'),
            ('v0.5.0', '0.5.0+15', '# v0.4.0\nChanges'),
            ('v0.5.0', '0.5.0', '# v0.5.0\nChanges'),
            ('v0.5.0', '0.5.0+2147483647', '# v0.5.0\nChanges'),
        ]:
            with self.assertRaises(ValueError):
                metadata(tag, 'version: ' + version, notes)

    def test_all_platform_packages_required(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                check(directory, 'v0.5.0')
            for name in expected_assets('v0.5.0'):
                Path(directory, name).write_bytes(b'package')
            check(directory, 'v0.5.0')
            Path(directory, expected_assets('v0.5.0')[0]).write_bytes(b'')
            with self.assertRaises(ValueError):
                check(directory, 'v0.5.0')

    def test_signing_escapes_java_properties_without_replacing_key(self):
        self.assertEqual(properties_escape(' a:b=c\\\n密'), r'\ a\:b\=c\\\n\u5bc6')
        with patch.dict('os.environ', {'GITHUB_ACTIONS': 'false'}):
            with self.assertRaises(SystemExit):
                restore()
        with patch.dict('os.environ', {}, clear=True):
            with self.assertRaises(SystemExit):
                restore()

    def test_unconfigured_mirror_never_requests_network(self):
        with patch.dict('os.environ', {}, clear=True), patch.object(publish_gitee, 'api') as api:
            publish_gitee.publish()
            api.assert_not_called()

    def test_existing_signing_files_are_never_overwritten(self):
        with patch.dict('os.environ', {
            'GITHUB_ACTIONS': 'true', 'ANDROID_KEYSTORE_BASE64': 'dGVzdA==',
            'ANDROID_STORE_PASSWORD': 'test', 'ANDROID_KEY_ALIAS': 'test',
            'ANDROID_KEY_PASSWORD': 'test',
        }), patch.object(Path, 'exists', return_value=True), patch.object(Path, 'write_bytes') as write:
            with self.assertRaisesRegex(SystemExit, 'Refusing to overwrite'):
                restore()
            write.assert_not_called()

    def test_gitee_release_body_is_checked_in_notes_and_commit_is_exact(self):
        with patch.dict('os.environ', {'GITEE_TOKEN': 'test-only', 'RELEASE_TAG': 'v0.5.0', 'GITHUB_SHA': 'a' * 40}), \
             patch.object(publish_gitee, 'check'), patch.object(publish_gitee, 'api') as api, \
             patch.object(publish_gitee, 'upload') as upload:
            api.side_effect = [{'sha': 'a' * 40}, None, {'id': 7}, []]
            publish_gitee.publish()
            self.assertEqual(api.call_args_list[0].args[1], '/commits/' + 'a' * 40)
            fields = api.call_args_list[2].args[2]
            self.assertEqual(fields['body'], Path('RELEASE_NOTE.md').read_text())
            self.assertEqual(fields['target_commitish'], 'a' * 40)
            self.assertEqual(upload.call_count, 5)


if __name__ == '__main__':
    unittest.main()
