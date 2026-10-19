"""Read-only release archive inventory and binary-string privacy checks.

Reports can contain personal candidates: keep them in ignored local evidence.
Unknown candidates fail closed. Approvals bind an exact member, kind, value
and surrounding string; no path-prefix or personal-identifier exemptions.
"""
import argparse
import gzip
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import zipfile
import zlib

HERE = Path(__file__).resolve().parent
MAX_MEMBER = 256 * 1024 * 1024
MAX_TOTAL = 1024 * 1024 * 1024
PATTERNS = {
    'absolute-path': r'(?i)(?<![a-z0-9])[a-z]:[\\/][^\x00-\x1f\x7f<>"|]*|(?<![\w:/.])/[a-z_][a-z0-9_.-]*/[^\s\x00<>"|]*|\\\\[\w.-]+\\[^\x00-\x1f<>"|]*',
    'email': r'(?<![\w.+-])[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}',
    'ipv4': r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])',
    'ipv6': r'(?<![\w:])(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:.]{0,39}(?:%[\w.-]+)?',
    'mac': r'(?i)(?<![\da-f])(?:[\da-f]{2}[:-]){5}[\da-f]{2}(?![\da-f])',
    'device-or-host': r'''(?i)\b(?:DESKTOP|LAPTOP)-[A-Z0-9-]+\b|\badb\s+-s\s+[\w.:-]+|\b(?:host(?:name)?|computername|device[_ -]?serial|serial(?:number)?|user(?:name)?)\b["']?\s*[:=]\s*["']?[\w.@-]+|\b[\w-]+\.(?:local|lan|internal)\b''',
}
COMPILED = {k: re.compile(v) for k, v in PATTERNS.items()}
CLASSIFICATIONS = {'generic-build-path', 'runtime-path', 'third-party-contact',
                   'loopback', 'false-positive'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load_approvals(path):
    result = []
    seen = set()
    for group in json.loads(path.read_text(encoding='utf-8')):
        if group['classification'] not in CLASSIFICATIONS or not group['reason'].strip():
            raise ValueError('Invalid package scan approval')
        for fingerprint in group['fingerprints']:
            if not re.fullmatch('[0-9a-f]{64}', fingerprint) or fingerprint in seen:
                raise ValueError('Duplicate or invalid package scan approval fingerprint')
            seen.add(fingerprint)
            result.append({'fingerprint': fingerprint, 'classification': group['classification'], 'reason': group['reason']})
    return result


def load_allowlist(path=HERE / 'windows-package-files.json'):
    names = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(names, list) or not names or len(set(names)) != len(names):
        raise ValueError('Invalid Windows allowlist')
    for name in names:
        safe_name(name)
        if name.endswith('/') or any(c in name for c in '*?['):
            raise ValueError('Windows allowlist must contain exact file paths')
    return names


def safe_name(name):
    if (not name or '\\' in name or ':' in name or name.startswith('/') or any(ord(c) < 32 for c in name) or
            any(p in ('', '.', '..') for p in name.rstrip('/').split('/'))):
        raise ValueError('Unsafe archive member name')


def contents_check(names, expected):
    """One versioned top folder; exact files, only their parent directories."""
    roots = {n.split('/')[0] for n in names}
    if len(roots) != 1 or any('/' not in n for n in names):
        return {'missing': sorted(expected), 'unexpected': sorted(names)}
    actual = {n.split('/', 1)[1] for n in names if not n.endswith('/')}
    dirs = {n.split('/', 1)[1].rstrip('/') for n in names if n.endswith('/')}
    allowed_dirs = {str(p) for n in expected for p in PurePosixPath(n).parents if str(p) != '.'}
    return {'missing': sorted(set(expected) - actual),
            'unexpected': sorted(actual - set(expected)) + sorted(d + '/' for d in dirs - allowed_dirs if d)}


def text_views(data):
    # UTF-8 includes ASCII strings in DEX/ELF/PE; both UTF-16 byte orders and
    # alignments cover native Windows resources and Android string pools.
    printable = re.compile(r'[^\x00-\x1f\x7f-\x9f\ufffd]{4,}')
    yield 'utf8', '\n'.join(printable.findall(data.decode('utf-8', errors='replace')))
    for encoding in ('utf-16le', 'utf-16be'):
        for offset in (0, 1):
            chunks = printable.findall(data[offset:].decode(encoding, errors='replace'))
            yield encoding + ':' + str(offset), '\n'.join(c for c in chunks if re.search(r'[ -~]{4}', c))


def findings_for(member, data, identifiers=()):
    found = {}
    patterns = dict(COMPILED)
    for index, identifier in enumerate(identifiers):
        if identifier and identifier.lower() not in ('user', 'admin', 'administrator'):
            patterns['build-identity-' + str(index)] = re.compile(r'(?i)(?<!\w)' + re.escape(identifier) + r'(?!\w)')
    for encoding, text in text_views(data):
        for kind, pattern in patterns.items():
            for match in pattern.finditer(text):
                value = match[0].rstrip()
                if kind in ('ipv4', 'ipv6'):
                    try:
                        ipaddress.ip_address(value.split('%')[0])
                    except ValueError:
                        continue
                # Avoid binary garbage in context; retain enough text for a
                # reviewer to distinguish a license/contact from private data.
                start = max(text.rfind('\n', 0, match.start()) + 1, match.start() - 60)
                end = text.find('\n', match.end())
                context = text[start:min(len(text) if end < 0 else end, match.end()+60)]
                context = ''.join(c if c.isprintable() else ' ' for c in context)
                fingerprint = digest((member + '\n' + kind + '\n' + value + '\n' + context).encode('utf-8'))
                key = (kind, value, fingerprint)
                if key not in found:
                    found[key] = {'member': member, 'kind': kind, 'value': value,
                                  'context': context, 'encoding': encoding,
                                  'fingerprint': fingerprint, 'occurrences': 0}
                found[key]['occurrences'] += 1
    return list(found.values())


def scan_archive(path, platform, approvals=(), identifiers=(), allowlist=None):
    before = digest(path.read_bytes())
    report = {'package': path.name, 'sha256': before, 'platform': platform,
              'inventory': [], 'findings': [], 'errors': [], 'contents': None}
    approved = {a['fingerprint']: a for a in approvals}
    total = 0

    def scan_data(member, data, depth):
        nonlocal total
        total += len(data)
        if len(data) > MAX_MEMBER or total > MAX_TOTAL or depth > 4:
            raise ValueError('Archive scan limit exceeded')
        report['findings'].extend(findings_for(member, data, identifiers))
        if data.startswith(b'PK\x03\x04'):
            walk(io.BytesIO(data), member + '!', depth + 1)
        elif data.startswith(b'\x1f\x8b'):
            with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
                expanded = stream.read(MAX_MEMBER + 1)
            scan_data(member + '!gzip', expanded, depth + 1)

    def walk(source, prefix, depth):
        nonlocal total
        with zipfile.ZipFile(source) as archive:
            entries = archive.infolist()
            # Windows Compress-Archive writes backslash separators. Validate
            # the original name before Python can truncate/normalize it, then
            # compare its portable slash form with the exact contents list.
            names = [e.orig_filename.replace('\\', '/') for e in entries]
            for name in names:
                safe_name(name)
            if len(set(n.casefold() for n in names)) != len(names):
                raise ValueError('Duplicate/case-colliding archive entries')
            if not prefix and platform == 'windows':
                report['contents'] = contents_check(names, allowlist if allowlist is not None else load_allowlist())
            if archive.comment:
                scan_data(prefix + '@archive-comment', archive.comment, depth)
            for entry, normalized in zip(entries, names):
                if entry.flag_bits & 1 or stat.S_ISLNK(entry.external_attr >> 16):
                    raise ValueError('Encrypted or linked archive member')
                if entry.file_size > MAX_MEMBER or total + entry.file_size > MAX_TOTAL:
                    raise ValueError('Archive scan limit exceeded')
                name = normalized
                if not prefix and platform == 'windows':
                    name = name.split('/', 1)[-1]
                member = prefix + name
                report['findings'].extend(findings_for(member + '!name', entry.orig_filename.encode(), identifiers))
                if entry.comment:
                    scan_data(member + '!comment', entry.comment, depth)
                if entry.extra:
                    scan_data(member + '!extra', entry.extra, depth)
                if entry.is_dir():
                    continue
                data = archive.read(entry)  # Includes CRC verification.
                report['inventory'].append({'member': member, 'bytes': len(data), 'sha256': digest(data)})
                scan_data(member, data, depth)
    try:
        # Scan metadata, APK signing blocks and appended bytes, without treating
        # compressed payload as strings or scanning stored members twice.
        raw = path.read_bytes()
        with zipfile.ZipFile(path) as outer:
            cursor = 0
            for entry in sorted(outer.infolist(), key=lambda e: e.header_offset):
                offset = entry.header_offset
                name_size, extra_size = struct.unpack_from('<HH', raw, offset + 26)
                start = offset + 30 + name_size + extra_size
                report['findings'].extend(findings_for('@container', raw[cursor:start], identifiers))
                cursor = start + entry.compress_size
            report['findings'].extend(findings_for('@container', raw[cursor:], identifiers))
        walk(path, '', 0)
    except (ValueError, OSError, zipfile.BadZipFile, RuntimeError, EOFError, struct.error, zlib.error) as exc:
        report['errors'].append(type(exc).__name__ + ': ' + str(exc))
    for finding in report['findings']:
        approval = approved.get(finding['fingerprint'])
        finding['classification'] = approval['classification'] if approval else 'unreviewed'
        finding['reason'] = approval['reason'] if approval else ''
    report['scanned_bytes'] = total
    report['unresolved'] = sum(f['classification'] == 'unreviewed' for f in report['findings'])
    report['unchanged'] = before == digest(path.read_bytes())
    contents_ok = not report['contents'] or not any(report['contents'].values())
    report['result'] = 'PASS' if (not report['errors'] and not report['unresolved'] and contents_ok and report['unchanged']) else 'FAIL'
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--windows', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--approvals', type=Path, default=HERE / 'package-scan-approvals.json')
    parser.add_argument('--identifiers', type=Path, help='Optional private JSON list of known identifiers; never commit')
    args = parser.parse_args()
    if not args.apk and not args.windows:
        parser.error('Specify an APK and/or Windows ZIP')
    if args.report.exists():
        parser.error('Report already exists; choose fresh evidence')
    approvals = load_approvals(args.approvals)
    identifiers = [os.environ.get('USERNAME', ''), os.environ.get('COMPUTERNAME', '')]
    if args.identifiers:
        identifiers += json.loads(args.identifiers.read_text(encoding='utf-8'))
    reports = [scan_archive(p, platform, approvals, identifiers) for p, platform in
               ((args.apk, 'android'), (args.windows, 'windows')) if p]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({'packages': reports}, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
    for report in reports:
        print(f"{report['result']} {report['platform']}: {len(report['inventory'])} members; "
              f"{len(report['findings'])} candidates, {report['unresolved']} unresolved; "
              f"{len(report['errors'])} scan errors; contents={report['contents']}; unchanged={report['unchanged']}")
    return 0 if all(r['result'] == 'PASS' for r in reports) else 1


if __name__ == '__main__':
    sys.exit(main())
