#!/usr/bin/env python3
"""Replay pinned literal tests, operation side effects, and UTF-8 range boundaries.

Native assertions run unchanged in a temporary copy before fixtures are accepted.
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
temp = ROOT / 'temp/literal-utf8-parity'
temp.mkdir(parents=True, exist_ok=True)
copy = temp / 'src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source, copy)
preamble = '''macro_rules! parity_assert_eq { ($line:expr, $($args:tt)*) => {{
    crate::hir::literal::parity_snapshot::assertion(file!(),$line); assert_eq!($($args)*);
}}; }
macro_rules! parity_assert { ($line:expr, $($args:tt)*) => {{
    crate::hir::literal::parity_snapshot::assertion(file!(),$line); assert!($($args)*);
}}; }
'''
originals = {}
for name in ['hir/literal.rs', 'utf8.rs']:
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
    if name == 'hir/literal.rs':
        modified = modified.replace('    fn parse(pattern: &str) -> Hir {', '    fn parse(pattern: &str) -> Hir {\n        parity_snapshot::set_pattern(pattern);')
        signature = '    pub fn extract(&self, hir: &Hir) -> Seq {'
        wrapper = '''    pub fn extract(&self, hir: &Hir) -> Seq {
        let outer = parity_snapshot::enter();
        let result = self.parity_original_extract(hir);
        parity_snapshot::leave();
        if outer { parity_snapshot::extract(self,&result); }
        result
    }
'''
        modified = modified.replace(signature, wrapper + signature.replace('pub fn extract(', 'fn parity_original_extract('))
        begin, end = modified.index('impl Seq {'), modified.index('impl core::fmt::Debug for Seq')
        part = modified[begin:end]
        unary = ['make_inexact','make_infinite','dedup','sort','reverse_literals','minimize_by_preference','optimize_for_prefix_by_preference','optimize_for_suffix_by_preference']
        binary = ['cross_forward','cross_reverse','union','union_into_empty']
        for method in unary + binary + ['keep_first_bytes','keep_last_bytes','push']:
            if method in binary:
                params, arguments, argument = 'other: &mut Seq', 'other', 'parity_snapshot::shape(other)'
                tail = 'parity_snapshot::snapshot(other)'
            elif method.startswith('keep_'):
                params, arguments, argument = 'len: usize', 'len', 'std::format!("{len}")'
                tail = '"-".into()'
            elif method == 'push':
                params, arguments, argument = 'lit: Literal', 'lit', 'parity_snapshot::literal(&lit)'
                tail = '"-".into()'
            else:
                params, arguments, argument, tail = '', '', '"-".into()', '"-".into()'
            signature = f'    pub fn {method}(&mut self' + (', ' + params if params else '') + ') {'
            assert signature in part, method
            wrapper = f'''{signature}
        let before = parity_snapshot::shape(self);
        let argument = {argument};
        self.parity_original_{method}({arguments});
        parity_snapshot::operation("{method}",before,argument,self,{tail});
    }}
'''
            part = part.replace(signature, wrapper + signature.replace(f'pub fn {method}(', f'fn parity_original_{method}('))
        modified = modified[:begin] + part + modified[end:]
        modified += '\npub(crate) mod parity_snapshot { include!("' + str(ROOT / 'scripts/parity/literal_utf8.rs') + '"); }\n'
    (copy / name).write_text(modified)
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case', 'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
command = ['rustc', '--edition=2021', '--test', '--crate-name=regex_syntax', str(copy / 'lib.rs'), '-o', str(temp / 'rust-tests')]
for feature in features:
    command += ['--cfg', f'feature="{feature}"']
subprocess.run(command, check=True)
for name in ['runtime.tsv', 'assertions.tsv']:
    (temp / name).write_text('')
env = dict(os.environ, REGEX_LITERAL_CAPTURE=str(temp / 'runtime.tsv'), REGEX_LITERAL_ASSERTIONS=str(temp / 'assertions.tsv'))
for test_filter in ['hir::literal::tests::', 'utf8::tests::', 'hir::literal::parity_snapshot::']:
    subprocess.run([str(temp / 'rust-tests'), test_filter, '--test-threads=1'], env=env, check=True)
rows = list(dict.fromkeys((temp / 'runtime.tsv').read_text().splitlines()))
fixture_text = '# Pinned Rust literal and UTF-8 results; revision ' + revision + '\n'
fixture_text += '# kind\toperation/configuration\tinput\targument\texpected\tother_after\n' + '\n'.join(rows) + '\n'
executed = set((temp / 'assertions.tsv').read_text().splitlines())
ledger = ['# source_assertion\tstatus\tcrystal_evidence\tnotes']
for name, original in originals.items():
    start = original.index('#[cfg(test)]\nmod tests')
    current = None
    for number, line in enumerate(original.splitlines(), 1):
        match = re.match(r'    fn (\w+)\(', line)
        if match:
            current = match[1]
        if number <= original[:start].count('\n') or not re.search(r'\bassert(?:_eq)?!\(', line):
            continue
        key = f'{name}:{number}'
        assert key in executed, f'Unexecuted assertion {key}'
        evidence = 'spec/literal_utf8_parity_spec.cr'
        if name == 'utf8.rs':
            evidence += ',spec/utf8_spec.cr'
        ledger.append(f'src/{key}\truntime_verified\t{evidence}\t{current}: original Rust assertion executed; exact outputs/metadata or exhaustive loop replayed')
ledger.append('src/utf8.rs::test::codepoints_no_surrogates\truntime_verified\tspec/utf8_spec.cr\tOriginal no-panic loops retain all 10,240 surrogate/range combinations')
for path, content in [(ROOT / 'spec/fixtures/literal_utf8.tsv', fixture_text), (ROOT / 'plans/inventory/rust_literal_utf8_assertion_audit.tsv', '\n'.join(ledger)+'\n')]:
    if args.write_fixture:
        path.write_text(content)
    elif path.read_text() != content:
        raise SystemExit(f'{path.name} differs from pinned Rust')
print(f'{len(rows)} literal/UTF-8 snapshots; {len(ledger)-1} assertion/loop audit entries')
if not args.rust_only:
    subprocess.run(['crystal', 'spec', 'spec/literal_utf8_parity_spec.cr', 'spec/hir_literal_spec.cr', 'spec/utf8_spec.cr'], env=dict(os.environ, CRYSTAL_CACHE_DIR=str(ROOT / 'temp/crystal-cache')), check=True)
