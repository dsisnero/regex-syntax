#!/usr/bin/env python3
"""Verify pinned Rust diagnostics, printers and visitor traces without modifying vendor."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--write-fixture', action='store_true')
parser.add_argument('--rust-only', action='store_true')
args = parser.parse_args()
source = ROOT / 'vendor/regex-syntax/src'
revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
assert revision == '72d650cb0a880a01ab6dc2137c0888e8f89740f7'
temp = ROOT / 'temp/diagnostic-parity'
temp.mkdir(parents=True, exist_ok=True)
copy = temp / 'src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source, copy)
originals = {}
preamble = '''macro_rules! parity_assert_eq { ($line:expr, $($args:tt)*) => {{
    crate::parity_diagnostic::assertion(file!(),$line); assert_eq!($($args)*);
}}; }
macro_rules! parity_assert { ($line:expr, $($args:tt)*) => {{
    crate::parity_diagnostic::assertion(file!(),$line); assert!($($args)*);
}}; }
'''
for name in ['error.rs', 'ast/print.rs', 'hir/print.rs']:
    original = (source / name).read_text()
    originals[name] = original
    start = original.index('#[cfg(test)]\nmod tests')
    lines = original.splitlines(keepends=True)
    for number, line in enumerate(lines, 1):
        if number > original[:start].count('\n'):
            line = re.sub(r'\bassert_eq!\(', f'parity_assert_eq!({number}, ', line)
            line = re.sub(r'\bassert!\(', f'parity_assert!({number}, ', line)
            lines[number - 1] = line
    modified = ''.join(lines).replace('#[cfg(test)]\nmod tests', preamble + '#[cfg(test)]\nmod tests')
    if name.endswith('print.rs'):
        domain = name.split('/')[0]
        entry = f'        printer.print(&{ "ast" if domain == "ast" else "hir"}, &mut dst).unwrap();'
        modified = modified.replace(entry, entry + f'\n        crate::parity_diagnostic::emit("{domain}_print", "-", given, &dst);')
        if domain == 'hir':
            modified = re.sub(r'(        parity_assert_eq!\(\d+, [^\n]+expr.to_string\(\)\);)',
                              r'        crate::parity_diagnostic::hir_tree(&expr);\n\1', modified)
    (copy / name).write_text(modified)
with (copy / 'ast/mod.rs').open('a') as file:
    file.write('\npub(crate) fn parity_error(kind: ErrorKind, pattern: String, span: Span) -> Error { Error { kind, pattern, span } }\n')
with (copy / 'lib.rs').open('a') as file:
    file.write('\n#[cfg(test)]\nmod parity_diagnostic { include!("' + str(ROOT / 'scripts/parity/diagnostic.rs') + '"); }\n')
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case', 'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
command = ['rustc', '--edition=2021', '--test', '--crate-name=regex_syntax', str(copy / 'lib.rs'), '-o', str(temp / 'rust-tests')]
for feature in features:
    command += ['--cfg', f'feature="{feature}"']
subprocess.run(command, check=True)
for name in ['runtime.tsv', 'assertions.tsv']:
    (temp / name).write_text('')
env = dict(os.environ, REGEX_DIAGNOSTIC_CAPTURE=str(temp / 'runtime.tsv'), REGEX_DIAGNOSTIC_ASSERTIONS=str(temp / 'assertions.tsv'), REGEX_PARITY_ROOT=str(ROOT))
for test_filter in ['error::tests::', 'ast::print::tests::', 'hir::print::tests::', 'parity_diagnostic::']:
    subprocess.run([str(temp / 'rust-tests'), test_filter, '--test-threads=1'], env=env, check=True)
rows = list(dict.fromkeys((temp / 'runtime.tsv').read_text().splitlines()))
fixture = '# Pinned Rust diagnostic/printer/visitor results; revision ' + revision + '\n'
fixture += '# kind\tconfiguration\tinput_hex\texpected_hex\n' + '\n'.join(rows) + '\n'
executed = set((temp / 'assertions.tsv').read_text().splitlines())
ledger = ['# source_assertion\tstatus\tcrystal_evidence\tnotes']
for name, original in originals.items():
    start = original.index('#[cfg(test)]\nmod tests')
    for number, line in enumerate(original.splitlines(), 1):
        if number <= original[:start].count('\n') or not re.search(r'\bassert(?:_eq)?!\(', line):
            continue
        key = f'{name}:{number}'
        assert key in executed, f'Unexecuted assertion {key}'
        ledger.append(f'src/{key}\truntime_verified\tspec/diagnostic_parity_spec.cr\tOriginal Rust assertion executed; exact diagnostic or printer output replayed')
for name in ['ast/visitor.rs', 'hir/visitor.rs']:
    assert '#[test]' not in (source / name).read_text()
    ledger.append(f'src/{name}::visitor_contract\tcharacterized\tspec/diagnostic_parity_spec.cr\tNo upstream unit tests; native traces and errors at every fallible hook occurrence')
for path, content in [(ROOT / 'spec/fixtures/diagnostic.tsv', fixture), (ROOT / 'plans/inventory/rust_diagnostic_assertion_audit.tsv', '\n'.join(ledger) + '\n')]:
    if args.write_fixture:
        path.write_text(content)
    elif path.read_text() != content:
        raise SystemExit(f'{path.name} differs from pinned Rust')
print(f'{len(rows)} diagnostic/printer/visitor snapshots; {len(ledger)-1} audit entries')
if not args.rust_only:
    subprocess.run(['crystal', 'spec', 'spec/diagnostic_parity_spec.cr'], env=dict(os.environ, CRYSTAL_CACHE_DIR=str(ROOT / 'temp/crystal-cache')), check=True)
