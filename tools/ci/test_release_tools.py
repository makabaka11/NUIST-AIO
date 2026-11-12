import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from release_metadata import metadata
from release_notes import PLATFORM_NOTES, compose
from restore_android_key import properties_escape, restore
from check_assets import check, expected_assets


class ReleaseToolsTest(unittest.TestCase):
    def setUp(self):
        # Simulated publication must not emit real Actions warning commands.
        printer = patch("builtins.print")
        printer.start()
        self.addCleanup(printer.stop)

    def test_release_version_and_build_come_from_tag(self):
        self.assertEqual(metadata('v0.5.1', '# v0.5.1\n\nChanges\n'),
                         {'version': '0.5.1', 'build': '501', 'tag': 'v0.5.1'})
        tags = ['v0.5.0', 'v0.5.1', 'v0.5.99', 'v0.6.0', 'v0.99.99', 'v1.0.0']
        builds = [int(metadata(tag, f'# {tag}\nChanges\n')['build']) for tag in tags]
        self.assertEqual(builds, sorted(set(builds)))
        self.assertGreater(builds[1], 15)  # Published v0.5.0 used versionCode 15.

    def test_invalid_tags_build_ranges_and_mismatched_notes_fail(self):
        for tag, notes in [
            ('v0.5.0-beta', '# v0.5.0-beta\nChanges'),
            ('v00.5.0', '# v00.5.0\nChanges'),
            ('0.5.0', '# 0.5.0\nChanges'),
            ('v0.100.0', '# v0.100.0\nChanges'),
            ('v0.5.100', '# v0.5.100\nChanges'),
            ('v0.0.0', '# v0.0.0\nChanges'),
            ('v6.55.36', '# v6.55.36\nChanges'),
            ('v0.5.1', '# v0.5.0\nChanges'),
            ('v0.5.1', '# v0.5.1\n'),
        ]:
            with self.subTest(tag=tag, notes=notes), self.assertRaises(ValueError):
                metadata(tag, notes)
        self.assertEqual(metadata('v6.55.35', '# v6.55.35\nChanges')['build'], '65535')

    def test_ci_entrypoint_does_not_require_pubspec(self):
        script = Path(__file__).with_name('release_metadata.py').resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'RELEASE_NOTE.md').write_text('# v0.5.1\n\n更新内容。\n', encoding='utf-8')
            output = root / 'outputs'
            subprocess.run([sys.executable, str(script)], cwd=root, check=True,
                           env={**os.environ, 'RELEASE_TAG': 'v0.5.1', 'GITHUB_OUTPUT': str(output)})
            self.assertEqual(output.read_text().splitlines(), ['version=0.5.1', 'build=501', 'tag=v0.5.1'])

    def test_platform_notes_are_appended_without_requiring_source_section(self):
        notes = '# v0.5.0\n\n## 修复\n\n- 修复构建。\n'
        self.assertEqual(metadata('v0.5.0', notes)['tag'], 'v0.5.0')
        self.assertEqual(compose(notes), notes.rstrip() + '\n\n' + PLATFORM_NOTES + '\n')

    def test_existing_platform_sections_are_replaced_and_other_sections_preserved(self):
        notes = ('# v0.5.0\n\n## 平台说明\n旧说明\n### 旧细节\n旧内容\n'
                 '## 修复\n- 修复构建。\n## 平台说明 ##\n另一份旧说明\n')
        result = compose(notes)
        self.assertEqual(result, '# v0.5.0\n\n## 修复\n- 修复构建。\n\n' + PLATFORM_NOTES + '\n')
        self.assertEqual(compose(result), result)
        self.assertEqual(compose(notes.replace('\n', '\r\n')), result)

    def test_headings_in_code_fences_are_preserved(self):
        notes = '# v0.5.0\n\n```markdown\n## 平台说明\n示例\n```\n'
        self.assertTrue(compose(notes).startswith(notes.rstrip()))

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

    def test_existing_signing_files_are_never_overwritten(self):
        with patch.dict('os.environ', {
            'GITHUB_ACTIONS': 'true', 'ANDROID_KEYSTORE_BASE64': 'dGVzdA==',
            'ANDROID_STORE_PASSWORD': 'test', 'ANDROID_KEY_ALIAS': 'test',
            'ANDROID_KEY_PASSWORD': 'test',
        }), patch.object(Path, 'exists', return_value=True), patch.object(Path, 'write_bytes') as write:
            with self.assertRaisesRegex(SystemExit, 'Refusing to overwrite'):
                restore()
            write.assert_not_called()

    def test_release_requires_only_requested_architectures(self):
        self.assertEqual(expected_assets('v0.5.0'), [
            'nuistaio-v0.5.0-android-armeabi-v7a.apk',
            'nuistaio-v0.5.0-android-arm64-v8a.apk',
            'nuistaio-v0.5.0-ios-unsigned.ipa',
            'nuistaio-v0.5.0-macos-arm64.zip',
            'nuistaio-v0.5.0-macos-x86_64.zip',
            'nuistaio-v0.5.0-windows-x64.zip',
        ])


if __name__ == '__main__':
    unittest.main()
