"""Synthetic standard-library ZIP interoperability and hostile archive fixtures."""
import io
import json
import pathlib
import struct
import sys
import zipfile

mode, folder = sys.argv[1:]
root = pathlib.Path(folder)
root.mkdir(parents=True, exist_ok=True)
recipes = json.loads((pathlib.Path(__file__).parent / 'corpus.json').read_text(encoding='utf-8'))['recipes']
(root / 'recipes.json').write_text(json.dumps(recipes, ensure_ascii=False), encoding='utf-8')

class Streaming(io.BytesIO):
    def seekable(self):
        return False
    def seek(self, *args):
        raise io.UnsupportedOperation('stream')

def make(entries, method=zipfile.ZIP_STORED, streaming=False):
    out = Streaming() if streaming else io.BytesIO()
    with zipfile.ZipFile(out, 'w', compression=method) as archive:
        for name, data in entries:
            archive.writestr(name, data)
    return out.getvalue()

entries = [(r['id'] + '.json', json.dumps(r, ensure_ascii=False).encode()) for r in recipes]
if mode == 'prepare':
    (root / 'legacy.zip').write_bytes(make(entries))
    valid = {}
    for name, method, streaming in [('python-store.zip', 0, False), ('python-deflate.zip', 8, False), ('python-descriptor.zip', 8, True)]:
        valid[name] = make(entries, method, streaming)
        (root / name).write_bytes(valid[name])
    setup = {'categories': [{'id': 'produce', 'name': 'Farm stand'}, {'id': 'other', 'name': 'Other'}], 'placements': {'white onion': 'produce'}}
    for method, streaming in [(0, False), (8, False), (8, True)]:
        name = f'python-setup-{method}-{int(streaming)}.zip'
        valid[name] = make(entries + [('.cookdex-shopping.json', json.dumps(setup).encode())], method, streaming)
        (root / name).write_bytes(valid[name])
    invalid = {}
    invalid['duplicate-setup'] = make([('.cookdex-shopping.json', json.dumps(setup).encode())] * 2)
    invalid['bad-setup'] = make([('.cookdex-shopping.json', b'{"categories":[],"placements":{}}')])
    invalid['unknown-category'] = make([('.cookdex-shopping.json', json.dumps({**setup, 'placements': {'onion': 'missing'}}).encode())])
    invalid['setup-bomb'] = make([('.cookdex-shopping.json', b' ' * (4 * 1024 * 1024 + 1))], 8)
    invalid['nested-path'] = make([('nested/' + entries[0][0], entries[0][1])])
    invalid['traversal'] = make([('../' + entries[0][0], entries[0][1])])
    invalid['absolute-path'] = make([('/' + entries[0][0], entries[0][1])])
    invalid['duplicate'] = make([entries[0], entries[0]])
    invalid['identity-mismatch'] = make([('wrong-id.json', entries[0][1])])
    invalid['invalid-json'] = make([(entries[0][0], b'{')])
    invalid['utf8'] = make([(entries[0][0], b'\xff')])
    invalid['bad-amount'] = make([(entries[0][0], entries[0][1].replace(b'"denominator": 3', b'"denominator": 0'))])
    invalid['zip-bomb'] = make([('bomb.json', b'x' * (32 * 1024 * 1024 + 1))], 8)
    base = valid['python-store.zip']
    directory = struct.unpack_from('<I', base, len(base)-6)[0]
    for name, offset, fmt, value in [
        ('encrypted', 6, '<H', 1), ('unsupported-method', directory+10, '<H', 99),
        ('wrong-local-crc', 14, '<I', 0), ('wrong-central-crc', directory+16, '<I', 0),
        ('wrong-local-size', 22, '<I', 0), ('wrong-central-size', directory+24, '<I', 0),
        ('bad-local-offset', directory+42, '<I', directory), ('bad-central-offset', len(base)-6, '<I', 0),
        ('multi-disk', len(base)-18, '<H', 1), ('entry-disk', directory+34, '<H', 1),
        ('count-limit', len(base)-12, '<H', 10001), ('directory-size', len(base)-10, '<I', 1),
        ('name-disagreement', 30, '<B', ord('x')), ('zip64-size', directory+24, '<I', 0xffffffff),
    ]:
        bad = bytearray(base)
        struct.pack_into(fmt, bad, offset, value)
        invalid[name] = bad
    descriptor = bytearray(valid['python-descriptor.zip'])
    descriptor_at = descriptor.index(b'PK\x07\x08')
    struct.pack_into('<I', descriptor, descriptor_at+4, 0)
    invalid['descriptor-crc'] = descriptor
    invalid['truncated-deflate'] = valid['python-deflate.zip'][:-1]
    # A local record referenced twice under distinct names must fail closed.
    overlap = bytearray(base)
    first_name, first_extra, first_comment = struct.unpack_from('<HHH', base, directory+28)
    second = directory+46+first_name+first_extra+first_comment
    struct.pack_into('<I', overlap, second+42, 0)
    invalid['overlapping-local'] = overlap
    for name, data in invalid.items():
        (root / ('bad-' + name + '.zip')).write_bytes(data)
    (root / 'manifest.json').write_text(json.dumps({'valid': list(valid), 'invalid': ['bad-'+name+'.zip' for name in invalid]}))
    print(f'C3 ZIP fixtures: {len(valid)} Python variants, {len(invalid)} hostile archives.')
else:
    for name in ['rust.zip', 'rust-setup.zip', 'legacy.zip', 'python-store.zip', 'python-deflate.zip', 'python-descriptor.zip']:
        with zipfile.ZipFile(root / name) as archive:
            assert archive.testzip() is None
            expected = json.loads((root / 'expected-rust.json').read_text(encoding='utf-8')) if name.startswith('rust') else recipes
            assert [json.loads(archive.read(r['id'] + '.json')) for r in expected] == expected
            if name == 'rust-setup.zip':
                setup = json.loads(archive.read('.cookdex-shopping.json'))
                assert setup['categories'][0]['id'] == 'other'
                assert setup['placements']['white onion'] == 'frozen'
    print('A3 ZIP: Python CRC, ranges, category setup and legacy STORE/DEFLATE/descriptor archives PASS.')
