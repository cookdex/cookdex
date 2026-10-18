"""Inspect resolved release evidence and APK DEX types, not source declarations."""
import argparse
import collections
import hashlib
import json
import pathlib
import re
import struct
import xml.etree.ElementTree as ET
import zipfile


def dex_types(data):
    assert data.startswith(b'dex\n'), 'Not a DEX file'
    string_count, string_offset, type_count, type_offset = struct.unpack_from('<4I', data, 56)
    strings = []
    for index in range(string_count):
        offset = struct.unpack_from('<I', data, string_offset + index * 4)[0]
        while data[offset] & 0x80:
            offset += 1
        offset += 1
        strings.append(data[offset:data.index(b'\0', offset)].decode('utf-8', errors='replace'))
    return [strings[struct.unpack_from('<I', data, type_offset + i * 4)[0]] for i in range(type_count)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', type=pathlib.Path, required=True)
    parser.add_argument('--dependencies', type=pathlib.Path, required=True)
    parser.add_argument('--manifest', type=pathlib.Path, required=True)
    parser.add_argument('--apk-manifest', type=pathlib.Path, required=True)
    parser.add_argument('--before', type=pathlib.Path)
    args = parser.parse_args()
    dependencies = args.dependencies.read_text(encoding='utf-8-sig')
    assert 'BUILD SUCCESSFUL' in dependencies and 'releaseRuntimeClasspath' in dependencies
    assert 'FAILED' not in dependencies and 'Could not resolve' not in dependencies
    forbidden = r'com\.google\.(?:mlkit|firebase|android\.(?:gms|datatransport|odml))'
    assert not re.search(forbidden, dependencies, re.I), 'Prohibited release dependency'
    assert 'project :flutter_zxing' in dependencies and 'androidx.camera:' in dependencies
    manifest = args.manifest.read_text(encoding='utf-8-sig')
    apk_manifest = args.apk_manifest.read_text(encoding='utf-8-sig')
    for evidence in (manifest, apk_manifest):
        assert 'EmojiCompatInitializer' not in evidence, 'Automatic emoji initializer remains'
        assert not re.search(forbidden, evidence, re.I), 'Prohibited manifest component'
        for permission in ('ACCESS_NETWORK_STATE', 'RECORD_AUDIO', 'READ_EXTERNAL_STORAGE',
                           'WRITE_EXTERNAL_STORAGE', 'READ_MEDIA_IMAGES', 'ACCESS_FINE_LOCATION',
                           'ACCESS_COARSE_LOCATION'):
            assert f'android.permission.{permission}' not in evidence, permission
    root = ET.fromstring(manifest)
    key = '{http://schemas.android.com/apk/res/android}name'
    permissions = sorted(node.attrib[key] for node in root.findall('uses-permission'))
    expected = {'android.permission.INTERNET', 'android.permission.CAMERA',
                'android.permission.ACCESS_LOCAL_NETWORK',
                'com.sylph.cookdex.dev.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
    assert set(permissions) == expected, f'Unexpected permission set: {permissions}'
    for permission in permissions:
        assert permission in apk_manifest, f'APK permission mismatch: {permission}'
    with zipfile.ZipFile(args.apk) as archive:
        assert archive.testzip() is None
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        assert 'lib/arm64-v8a/libflutter_zxing.so' in names, 'Missing native scanner'
        assert not any(re.search(r'mlkit|firebase|barhopper|datatransport|\.tflite$', n, re.I) for n in names)
        descriptors = []
        for name in names:
            if re.fullmatch(r'classes\d*\.dex', name):
                descriptors.extend(dex_types(archive.read(name)))
        assert descriptors, 'No DEX evidence'
        prohibited_types = [d for d in descriptors if re.search(
            r'Lcom/google/(?:mlkit|firebase|android/(?:gms|datatransport|odml))/', d)]
        assert not prohibited_types, f'Prohibited APK DEX types: {prohibited_types[:10]}'
        sizes = collections.Counter()
        for entry in entries:
            name = entry.filename
            if name.startswith('lib/'):
                group = name.split('/')[-1]
            elif re.fullmatch(r'classes\d*\.dex', name):
                group = 'DEX bytecode'
            elif name.startswith('assets/flutter_assets/'):
                group = 'Flutter assets'
            else:
                group = 'Android resources and metadata'
            sizes[group] += entry.compress_size
    result = {
        'result': 'PASS', 'apk_bytes': args.apk.stat().st_size,
        'sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
        'permissions': permissions, 'dex_types_checked': len(descriptors),
        'prohibited_sdk_types': 0, 'automatic_emoji_initializer': False,
        'compressed_contributors': dict(sizes.most_common()),
    }
    if args.before:
        before = args.before.stat().st_size
        result.update(before_bytes=before, saved_bytes=before - result['apk_bytes'],
                      saved_percent=round(100 * (before - result['apk_bytes']) / before, 2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
