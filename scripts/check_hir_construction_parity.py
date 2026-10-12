#!/usr/bin/env python3
"""Execute pinned Rust translator assertions and replay every runtime input in Crystal.

Only a temporary source copy is instrumented; vendor and original assertions stay
unchanged. Native tests must pass before any Rust fixture can be written.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import argparse

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
args = argparse.ArgumentParser(description=__doc__)
args.add_argument('--write-fixture', action='store_true')
options = args.parse_args()
source = ROOT / 'vendor/regex-syntax/src'
revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
assert revision == '72d650cb0a880a01ab6dc2137c0888e8f89740f7', 'Review upstream refresh first'
temp = ROOT / 'temp/hir-construction'
temp.mkdir(parents=True, exist_ok=True)
copy = temp / 'src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source, copy)
translator = copy / 'hir/translate.rs'
original = translator.read_text()
# Preserve original line numbers for assertion-level evidence.
test_start = original.index('#[cfg(test)]\nmod tests')
modified = original[:test_start] + original[test_start:].replace('assert_eq!(', 'parity_assert_eq!(').replace('assert!(', 'parity_assert!(')
entry = '        ast::visit(ast, TranslatorI::new(self, pattern))'
assert modified.count(entry) == 1
modified = modified.replace(entry, '''        let initial = self.clone();
        let result = ast::visit(ast, TranslatorI::new(self, pattern));
        parity_snapshot::record(&initial, pattern, &result);
        result''')
preamble = '''mod parity_snapshot { include!("SNAPSHOT"); }
macro_rules! parity_assert_eq { ($($args:tt)*) => {{
    parity_snapshot::assertion(line!()); assert_eq!($($args)*);
}}; }
macro_rules! parity_assert { ($($args:tt)*) => {{
    parity_snapshot::assertion(line!()); assert!($($args)*);
}}; }
'''.replace('SNAPSHOT', str(ROOT / 'scripts/parity/hir_snapshot.rs'))
# Append macros via insertion immediately before the tests module; correct offset below.
position = modified.index('#[cfg(test)]\nmod tests')
modified = modified[:position] + preamble + modified[position:]
modified = modified.rstrip()[:-1] + '\ninclude!("' + str(ROOT / 'scripts/parity/hir_construction_cases.rs') + '");\n}\n'
translator.write_text(modified)
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case',
            'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
command = ['rustc', '--edition=2021', '--test', '--crate-name=regex_syntax',
           str(copy / 'lib.rs'), '-o', str(temp / 'rust-tests')]
for feature in features:
    command += ['--cfg', f'feature="{feature}"']
subprocess.run(command, check=True)
for name in ['runtime.tsv', 'assertions.tsv']:
    (temp / name).write_text('')
env = dict(os.environ, REGEX_PARITY_CAPTURE=str(temp / 'runtime.tsv'),
           REGEX_PARITY_ASSERTIONS=str(temp / 'assertions.tsv'))
subprocess.run([str(temp / 'rust-tests'), 'hir::translate::tests::', '--test-threads=1'], env=env, check=True)
all_rows = (temp / 'runtime.tsv').read_text().splitlines()
rows = [r for r in all_rows if not r.startswith('hir::translate::tests::parity_construction_cases\t')]
construction = [r for r in all_rows if r.startswith('hir::translate::tests::parity_construction_cases\t')]
construction_text = '# Rust smart constructors; revision ' + revision + '\n' + '\n'.join(construction) + '\n'
construction_path = ROOT / 'spec/fixtures/hir_construction.tsv'
if options.write_fixture:
    construction_path.write_text(construction_text)
elif construction_path.read_text() != construction_text:
    raise SystemExit('Constructor fixtures differ from pinned Rust')
fixture = ROOT / 'spec/fixtures/hir_runtime.tsv'
content = '# Pinned Rust translator tests; revision ' + revision + '\n'
content += '# test\tconfiguration\tpattern_hex\texpected_snapshot_hex\n' + '\n'.join(rows) + '\n'
if options.write_fixture:
    fixture.write_text(content)
elif fixture.read_text() != content:
    raise SystemExit('Runtime fixtures differ from pinned Rust')
# Account for the three inserted entry lines and the macro preamble.
offset = len(preamble.splitlines()) + 3
executed = {(name, int(line) - offset) for name, line in
            (r.split('\t') for r in (temp / 'assertions.tsv').read_text().splitlines())}
ledger = ['# source_assertion\tstatus\tcrystal_evidence\tnotes']
current = None
for number, line in enumerate(original.splitlines(), 1):
    match = re.match(r'    fn (\w+)\(', line)
    if match:
        current = match[1]
    if number < original[:original.index('mod tests')].count('\n'):
        continue
    if re.search(r'\bassert(?:_eq)?!\(', line):
        test = f'hir::translate::tests::{current}'
        active = (test, number) in executed
        # Local helper assertion lines execute under their owning test thread.
        active |= any(n == number for _, n in executed)
        if not active and not current.endswith('_disabled'):
            raise SystemExit(f'Unaccounted upstream assertion: {current}:{number}')
        ledger.append(f'src/hir/translate.rs:{number}\t' +
                      ('runtime_verified' if active else 'feature_disabled') +
                      ('\tspec/hir_runtime_parity_spec.cr\t' if active else '\t-\t') + current)
    if 'let _ = t(pat)' in line:
        assert any(row.startswith(f'hir::translate::tests::{current}\t') for row in rows)
        ledger.append(f'src/hir/translate.rs:{number}\truntime_verified\tspec/hir_runtime_parity_spec.cr\t{current}: original no-panic regression; compare complete result')
path = ROOT / 'plans/inventory/rust_hir_assertion_audit.tsv'
ledger_text = '\n'.join(ledger) + '\n'
if options.write_fixture:
    path.write_text(ledger_text)
elif path.read_text() != ledger_text:
    raise SystemExit('Assertion audit differs from pinned Rust')
print(f'{len(rows)} runtime translator snapshots; {len(construction)} constructor snapshots; {len(executed)} executed assertion locations')
subprocess.run(['crystal', 'spec', 'spec/hir_runtime_parity_spec.cr',
                'spec/hir_construction_parity_spec.cr'], env=dict(os.environ,
                CRYSTAL_CACHE_DIR=str(temp / 'crystal-cache')), check=True)
