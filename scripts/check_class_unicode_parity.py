#!/usr/bin/env python3
"""Replay pinned native class tests and exhaustive Unicode tables/aliases in Crystal.

Only a temporary source copy is instrumented. Native assertions remain in place;
fixtures are written only after all corresponding Rust tests pass.
"""
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
versions = {re.search(r'Unicode version: ([0-9.]+)\.', path.read_text())[1]
            for path in (source / 'unicode_tables').glob('*.rs') if path.name != 'mod.rs'}
assert versions == {'16.0.0'}, versions
temp = ROOT / 'temp/class-unicode-parity'
temp.mkdir(parents=True, exist_ok=True)
copy = temp / 'src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source, copy)
preamble = '''macro_rules! parity_assert_eq { ($line:expr, $($args:tt)*) => {{
    crate::parity_class::assertion(file!(),$line); assert_eq!($($args)*);
}}; }
macro_rules! parity_assert { ($line:expr, $($args:tt)*) => {{
    crate::parity_class::assertion(file!(),$line); assert!($($args)*);
}}; }
'''
originals = {}
for name in ['hir/mod.rs', 'unicode.rs']:
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
    if name == 'hir/mod.rs':
        # Capture raw constructor input, then each operation's complete operands/result.
        for prefix, cls, bound in [('u', 'ClassUnicode', 'char'), ('b', 'ClassBytes', 'u8')]:
            needle = f'    fn {prefix}class(ranges: &[({bound}, {bound})]) -> {cls} {{'
            wrapper = f'''    fn {prefix}class(ranges: &[({bound}, {bound})]) -> {cls} {{
        let result = {prefix}class_original(ranges);
        crate::parity_class::record("{prefix}","new",crate::parity_class::{prefix}raw(ranges),"".into(),crate::parity_class::{prefix}ranges(&result));
        result
    }}
'''
            modified = modified.replace(needle, wrapper + needle.replace(f'{prefix}class(', f'{prefix}class_original('))
            for operation, method in [('casefold', 'case_fold_simple'), ('union', 'union'), ('intersect', 'intersect'), ('difference', 'difference'), ('symdifference', 'symmetric_difference'), ('negate', 'negate')]:
                pattern = rf'    fn {prefix}{operation}\([\s\S]*?\) -> {cls} \{{'
                match = re.search(pattern, modified)
                assert match
                binary = operation in ['union', 'intersect', 'difference', 'symdifference']
                signature = f'cls1: &{cls}, cls2: &{cls}' if binary else f'cls: &{cls}'
                arguments = 'cls1,cls2' if binary else 'cls'
                left = 'cls1' if binary else 'cls'
                right = f'crate::parity_class::{prefix}ranges(cls2)' if binary else '"".into()'
                cfg = '#[cfg(feature = "unicode-case")]\n' if prefix == 'u' and operation == 'casefold' else ''
                wrapper = f'''    {cfg}    fn {prefix}{operation}({signature}) -> {cls} {{
        let result = {prefix}{operation}_original({arguments});
        crate::parity_class::record("{prefix}","{method}",crate::parity_class::{prefix}ranges({left}),{right},crate::parity_class::{prefix}ranges(&result));
        result
    }}
'''
                modified = modified[:match.start()] + wrapper + modified[match.start():].replace(f'fn {prefix}{operation}(', f'fn {prefix}{operation}_original(', 1)
    (copy / name).write_text(modified)
# Private folded-state characterization supplements the upstream public-class tests.
with (copy / 'hir/interval.rs').open('a') as output:
    output.write('\n#[test]\nfn parity_interval_state() {\n')
    for kind, cls, bound in [('b', 'ClassBytesRange', 'u8'), ('u', 'ClassUnicodeRange', 'char')]:
        for empty, steps in [(False, 'fold,clone'), (False, 'fold,push_same'), (False, 'fold,push_subset'), (True, 'negate,clone'), (False, 'fold,negate,clone'), (False, 'fold,union'), (False, 'fold,intersect'), (False, 'fold,difference'), (False, 'fold,symmetric_difference')]:
            initial = 'std::vec![]' if empty else f"std::vec![crate::hir::{cls}::new(65 as {bound},90 as {bound})]"
            output.write(f'{{ let mut set: IntervalSet<crate::hir::{cls}>=IntervalSet::new({initial});\n')
            for step in steps.split(','):
                if step in ['union', 'intersect', 'difference', 'symmetric_difference']:
                    output.write(f'let mut other=IntervalSet::new(std::vec![crate::hir::{cls}::new(66 as {bound},67 as {bound})]);other.case_fold_simple().unwrap();set.{step}(&other);\n')
                    continue
                code = {'fold': 'set.case_fold_simple().unwrap();', 'clone': 'set=set.clone();',
                        'negate': 'set.negate();', 'push_same': f'set.push(crate::hir::{cls}::new(65 as {bound},90 as {bound}));',
                        'push_subset': f'set.push(crate::hir::{cls}::new(65 as {bound},66 as {bound}));'}[step]
                output.write(code+'\n')
            raw = '' if empty else '65-90'
            output.write(f'crate::parity_class::record("state_{kind}","{steps}","{raw}".into(),"".into(),std::format!("{{}};{{}}",set.intervals().iter().map(|r|std::format!("{{}}-{{}}",r.start() as u32,r.end() as u32)).collect::<std::vec::Vec<_>>().join(","),set.folded)); }}\n')
    output.write('}\n')
with (copy / 'lib.rs').open('a') as output:
    output.write('\nmod parity_class { include!("' + str(ROOT / 'scripts/parity/class_unicode.rs') + '"); }\n')
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case', 'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
command = ['rustc', '--edition=2021', '--test', '--crate-name=regex_syntax', str(copy / 'lib.rs'), '-o', str(temp / 'rust-tests')]
for feature in features:
    command += ['--cfg', f'feature="{feature}"']
subprocess.run(command, check=True)
for name in ['runtime.tsv', 'assertions.tsv']:
    (temp / name).write_text('')
env = dict(os.environ, REGEX_CLASS_CAPTURE=str(temp / 'runtime.tsv'), REGEX_CLASS_ASSERTIONS=str(temp / 'assertions.tsv'))
for test_filter in ['hir::tests::class_', 'unicode::tests::', 'parity_class::', 'hir::interval::parity_interval_state']:
    subprocess.run([str(temp / 'rust-tests'), test_filter, '--test-threads=1'], env=env, check=True)
rows = list(dict.fromkeys((temp / 'runtime.tsv').read_text().splitlines()))
# A dash encodes an empty result without trailing TSV whitespace.
rows = [row + '-' if row.endswith('\t') else row for row in rows]
fixture = ROOT / 'spec/fixtures/class_unicode.tsv'
content = '# Pinned Rust class operations and Unicode tables/queries; revision ' + revision + '\n'
content += '# kind\toperation\tinput\tother\texpected\n' + '\n'.join(rows) + '\n'
executed = set((temp / 'assertions.tsv').read_text().splitlines())
ledger = ['# source_assertion\tstatus\tcrystal_evidence\tnotes']
for name, original in originals.items():
    current = None
    start = original.index('#[cfg(test)]\nmod tests')
    for number, line in enumerate(original.splitlines(), 1):
        match = re.match(r'    fn (\w+)\(', line)
        if match:
            current = match[1]
        if number <= original[:start].count('\n') or not re.search(r'\bassert(?:_eq)?!\(', line):
            continue
        if name == 'hir/mod.rs' and not current.startswith('class_'):
            continue
        key = f'{name}:{number}'
        if 'disabled' in current:
            ledger.append(f'src/{key}\tskipped_build_mode\t-\t{current}: Crystal always includes Unicode case data; default-mode mappings verified exhaustively')
        else:
            assert key in executed, f'Unexecuted assertion {key}'
            evidence = 'spec/class_unicode_parity_spec.cr' if name == 'hir/mod.rs' else 'spec/unicode_spec.cr,spec/class_unicode_parity_spec.cr'
            ledger.append(f'src/{key}\truntime_verified\t{evidence}\t{current}: original Rust assertion executed; exact intervals or helper assertions replayed')
ledger.append('src/hir/mod.rs::test::class_case_fold_unicode_disabled_panics\tskipped_build_mode\t-\tRust should_panic requires omitted Unicode case tables; Crystal always includes the exhaustively verified default-mode mappings')
audit = ROOT / 'plans/inventory/rust_class_unicode_assertion_audit.tsv'
audit_text = '\n'.join(ledger) + '\n'
for path, expected in [(fixture, content), (audit, audit_text)]:
    if args.write_fixture:
        path.write_text(expected)
    elif path.read_text() != expected:
        raise SystemExit(f'{path.name} differs from pinned Rust')
print(f'{len(rows)} class/Unicode snapshots; {len(ledger)-1} audited assertion locations')
if not args.rust_only:
    subprocess.run(['crystal', 'spec', 'spec/class_unicode_parity_spec.cr', 'spec/unicode_spec.cr', 'spec/hir_interval_spec.cr'], env=dict(os.environ, CRYSTAL_CACHE_DIR=str(ROOT / 'temp/crystal-cache')), check=True)
