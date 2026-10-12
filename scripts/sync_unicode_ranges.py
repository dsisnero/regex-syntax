#!/usr/bin/env python3
"""Check or regenerate Crystal range constants from the pinned Rust oracle fixture.

First run check_class_unicode_parity.py --write-fixture --rust-only to verify the
fixture against native Rust. This script never derives expected data from Crystal.
"""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
files = {}
for line in (ROOT / 'spec/fixtures/class_unicode.tsv').read_text().splitlines():
    if not line.startswith('table\t'):
        continue
    _, table, key, _, ranges = line.split('\t')
    ranges = '' if ranges == '-' else ranges
    path = ROOT / f'src/regex/syntax/unicode_tables/{table}.cr'
    text = files.get(path, path.read_text())
    constant = key.upper()
    body = ''.join(f'    0x{int(start):X}_u32..0x{int(end):X}_u32,\n' for start, end in (pair.split('-') for pair in ranges.split(',') if pair))
    pattern = rf'(  {constant} = \[\n).*?(  \])'
    text, count = re.subn(pattern, lambda m: m[1] + body + m[2], text, count=1, flags=re.S)
    assert count == 1, (table, constant)
    files[path] = text
changed = [path for path, content in files.items() if path.read_text() != content]
for path in changed:
    if args.write:
        path.write_text(files[path])
    else:
        print(f'Range table differs: {path.relative_to(ROOT)}')
if changed and not args.write:
    raise SystemExit(1)
print(f'{len(files)} complete range-table modules checked; {len(changed)} changed')
