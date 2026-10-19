"""Synthetic archives only; no personal library, keys, or device access."""
import gzip
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import package_hygiene as hygiene


class PackageHygieneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def archive(self, entries, name='fixture.zip'):
        path = self.root / name
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
            for member, data in entries:
                info = zipfile.ZipInfo(member)
                info.filename = member
                archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
        return path

    def scan(self, entries, **kwargs):
        return hygiene.scan_archive(self.archive(entries), 'windows', allowlist=['app.exe'], **kwargs)

    def test_exact_contents(self):
        result = self.scan([('delivery/app.exe', b'synthetic binary')])
        self.assertEqual('PASS', result['result'])
        self.assertTrue(result['unchanged'])

    def test_extra_internal_doc_and_missing_runtime_fail(self):
        for name in ('SWITCH.md', 'README.txt', 'extra.dll', 'data/private.txt'):
            with self.subTest(name=name):
                result = self.scan([('delivery/' + name, b'synthetic')])
                self.assertEqual(['app.exe'], result['contents']['missing'])
                self.assertEqual([name], result['contents']['unexpected'])
                self.assertEqual('FAIL', result['result'])

    def test_directory_allowlist_and_multiple_roots(self):
        result = self.scan([('delivery/app.exe', b'ok'), ('delivery/private/', b'')])
        self.assertIn('private/', result['contents']['unexpected'])
        result = self.scan([('first/app.exe', b'ok'), ('second/app.exe', b'ok')])
        self.assertEqual('FAIL', result['result'])

    def test_unsafe_and_duplicate_names(self):
        for names in [('delivery/../app.exe',), ('delivery/app.exe', 'delivery/APP.exe'), ('/app.exe',), ('delivery\\..\\app.exe',)]:
            with self.subTest(names=names):
                result = self.scan([(name, b'ok') for name in names])
                self.assertTrue(result['errors'])

    def test_windows_archive_separators(self):
        result = self.scan([('delivery\\app.exe', b'synthetic')])
        self.assertEqual('PASS', result['result'])

    def test_personal_strings_in_all_encodings(self):
        # Construct fictional values so public-source scanners do not confuse
        # these intentional fixtures with personal identifiers.
        text = ' '.join(['Q:' + '/Users/fictional-builder/project',
                         '/home/' + 'fictional-builder/project',
                         'fictional' + '@example.invalid',
                         '192.0.' + '2.42', '2001:' + 'db8::42',
                         'DESKTOP-' + 'SYNTHETIC', 'adb -s ' + 'FAKEDEVICE42',
                         'username=' + 'fictional-builder',
                         'hostname=' + 'fixture-machine'])
        for encoding in ('utf-8', 'utf-16le', 'utf-16be'):
            with self.subTest(encoding=encoding):
                data = b'\x01' + text.encode(encoding) + b'\x00\x00'
                result = self.scan([('delivery/app.exe', data)])
                kinds = {f['kind'] for f in result['findings']}
                self.assertTrue({'absolute-path', 'email', 'ipv4', 'ipv6', 'device-or-host'} <= kinds)
                self.assertGreater(result['unresolved'], 0)

    def test_known_identifier_and_generic_account_label(self):
        result = self.scan([('delivery/app.exe', b'fixture-account User')], identifiers=['fixture-account', 'User'])
        self.assertTrue(any(f['kind'].startswith('build-identity') for f in result['findings']))
        self.assertFalse(any(f['value'] == 'User' for f in result['findings']))

    def test_nested_zip_and_gzip(self):
        nested = io.BytesIO()
        with zipfile.ZipFile(nested, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('notice.gz', gzip.compress(('fictional' + '@example.invalid').encode()))
        result = self.scan([('delivery/app.exe', nested.getvalue())])
        self.assertTrue(any(f['member'].endswith('notice.gz!gzip') and f['kind'] == 'email' for f in result['findings']))

    def test_comments_and_outer_bytes(self):
        path = self.archive([('delivery/app.exe', b'ok')])
        with zipfile.ZipFile(path, 'a') as archive:
            archive.comment = ('fictional' + '@example.invalid').encode()
        with path.open('ab') as stream:
            stream.write(('\x00hostname=' + 'fixture-machine\x00').encode())
        result = hygiene.scan_archive(path, 'windows', allowlist=['app.exe'])
        self.assertTrue(any(f['member'] == '@archive-comment' for f in result['findings']))
        self.assertTrue(any(f['member'] == '@container' and f['kind'] == 'device-or-host' for f in result['findings']))

    def test_approval_is_bound_to_exact_candidate_context_and_member(self):
        data = ('fixture ' + 'Q:' + '/generic/build/app.pdb\x00').encode()
        first = self.scan([('delivery/app.exe', data)])
        approvals = [dict(f, classification='generic-build-path', reason='Synthetic fixture') for f in first['findings']]
        self.assertEqual('PASS', self.scan([('delivery/app.exe', data)], approvals=approvals)['result'])
        changed = self.scan([('delivery/app.exe', b'changed ' + data)], approvals=approvals)
        self.assertEqual('FAIL', changed['result'])

    def test_truncated_gzip_and_limits_fail_closed(self):
        result = self.scan([('delivery/app.exe', b'\x1f\x8btruncated')])
        self.assertTrue(result['errors'])
        previous = hygiene.MAX_MEMBER
        try:
            hygiene.MAX_MEMBER = 4
            self.assertTrue(self.scan([('delivery/app.exe', b'too long')])['errors'])
        finally:
            hygiene.MAX_MEMBER = previous

    def test_crc_corruption_fails(self):
        path = self.root / 'corrupt.zip'
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_STORED) as archive:
            archive.writestr('delivery/app.exe', b'synthetic-content')
        path.write_bytes(path.read_bytes().replace(b'synthetic-content', b'corrupted-content'))
        self.assertTrue(hygiene.scan_archive(path, 'windows', allowlist=['app.exe'])['errors'])

    def test_allowlist_has_only_runtime_and_helpers(self):
        names = hygiene.load_allowlist()
        self.assertEqual(29, len(names))
        self.assertNotIn('SWITCH.md', names)
        self.assertNotIn('README.txt', names)
        self.assertIn('Create shortcut.cmd', names)
        self.assertIn('data/flutter_assets/NOTICES.Z', names)

    def test_invalid_approvals_fail_closed(self):
        path = self.root / 'approvals.json'
        for groups in ([{'classification': 'personal', 'reason': 'No', 'fingerprints': ['a'*64]}],
                       [{'classification': 'false-positive', 'reason': '', 'fingerprints': ['a'*64]}],
                       [{'classification': 'false-positive', 'reason': 'fixture', 'fingerprints': ['a'*64, 'a'*64]}]):
            path.write_text(json.dumps(groups))
            with self.assertRaises(ValueError):
                hygiene.load_approvals(path)

    def test_unicode_home_path(self):
        for encoding in ('utf-8', 'utf-16le', 'utf-16be'):
            data = ('Q:' + '/Users/fictional-\u00e9/project\x00').encode(encoding)
            findings = hygiene.findings_for('app.exe', data)
            self.assertTrue(any('fictional-\u00e9' in f['value'] for f in findings))

    def test_quoted_identifier_labels(self):
        labels = {'hostname': 'fixture-machine', 'serialnumber': 'FAKEDEVICE42',
                  'username': 'fictional-builder', 'serial': 'FAKEDEVICE43',
                  'host': 'fixture-machine-two', 'user': 'fictional-account'}
        for encoding in ('utf-8', 'utf-16le', 'utf-16be'):
            for quote in ('"', "'"):
                text = json.dumps(labels).replace('"', quote)
                findings = hygiene.findings_for('app.exe', text.encode(encoding))
                for label, value in labels.items():
                    self.assertTrue(any(label in f['value'] and value in f['value'] for f in findings), (encoding, quote, label))

    def test_packager_gates_success_on_scanner(self):
        # Integration contract: the owner entry point invokes this packager,
        # and cannot reach checksums/success without the scanner exit check.
        scripts = Path(__file__).parent
        packager = scripts / 'package-dev-release.ps1'
        if not packager.exists():
            self.skipTest('Owner-only packager is excluded from public source')
        text = packager.read_text()
        scan = text.index("'package_hygiene.py'")
        check = text.index('Assert-FlutterExit', scan)
        success = text.index('Write-Output "PASS')
        self.assertLess(scan, check)
        self.assertLess(check, success)
        self.assertNotIn("Join-Path $cookdexRoot 'SWITCH.md'", text)
        self.assertNotIn("Join-Path $bundle 'README.txt'", text)


if __name__ == '__main__':
    unittest.main()
