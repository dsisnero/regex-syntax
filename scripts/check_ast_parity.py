#!/usr/bin/env python3
"""Replay public AST parses for every input constructed by pinned Rust parser tests.

Public snapshots are supplemented by direct private-helper outputs and cursor
positions. Original assertions execute unchanged in a temporary source copy.
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
temp = ROOT / 'temp/ast-parity'
temp.mkdir(parents=True, exist_ok=True)
copy = temp / 'src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source, copy)
path = copy / 'ast/parse.rs'
original = path.read_text()
# Attach original source line IDs before inserting any instrumentation.
test_start = original.index('#[cfg(test)]\nmod tests')
lines = original.splitlines(keepends=True)
offset = 0
for number, line in enumerate(lines, 1):
    in_tests = offset >= test_start
    offset += len(line)
    if in_tests:
        line = re.sub(r'\bassert_eq!\(', f'parity_assert_eq!({number}, ', line)
        line = re.sub(r'\bassert!\(', f'parity_assert!({number}, ', line)
        lines[number - 1] = line
modified = ''.join(lines)
# The original local assert_eq macro stays intact and still checks expectations.
preamble = '''macro_rules! parity_assert_eq { ($line:expr, $($args:tt)*) => {{
    parity_snapshot::assertion($line); assert_eq!($($args)*);
}}; }
macro_rules! parity_assert { ($line:expr, $($args:tt)*) => {{
    parity_snapshot::assertion($line); assert!($($args)*);
}}; }
'''
modified = modified.replace('#[cfg(test)]\nmod tests', preamble + '#[cfg(test)]\nmod tests')
modified = modified.replace('        ParserI { parser, pattern }', '        parity_snapshot::record(parser.borrow(), pattern);\n        ParserI { parser, pattern }')
modified = modified.rstrip()[:-1] + r'''
    #[test]
    fn parity_ast_characterization() {
        for count in [250,251] {
            let pattern=std::format!("{}a{}","(".repeat(count),")".repeat(count));
            let _=parser(&pattern).parse();
        }
        for pattern in [r"(?-u)\xFF",r"(?-u)\x{100}",r"(?U)a+",r"a{2,2}",
                        r"(?x)a| b ",r"(?x: a ) b",r"(?x)[ - - a ]", "\\\n", "\\\t"] {
            let _ = parser(pattern).parse_with_comments();
        }
    }
}
'''
modified += '\nmod parity_snapshot { include!("' + str(ROOT / 'scripts/parity/ast_snapshot.rs') + '"); }\n'
# Wrap private helpers in the temporary copy, preserving native assertions.
for method, result_type, render in [
    ('parse_escape', 'Primitive', 'parity_snapshot::primitive'),
    ('parse_flags', 'ast::Flags', 'parity_snapshot::flags'),
    ('parse_decimal', 'u32', '|v: &u32| v.to_string()'),
    ('parse_flag', 'ast::Flag', '|v: &ast::Flag| std::format!("{:?}",v)'),
    ('parse_primitive', 'Primitive', 'parity_snapshot::primitive'),
    ('parse_set_class', 'ast::ClassBracketed', 'parity_snapshot::bracket'),
    ('parse_set_class_open', '(ast::ClassBracketed, ast::ClassSetUnion)', 'parity_snapshot::opening'),
]:
    signature = re.search(r'    fn ' + method + r'\(\s*&self\s*,?\s*\) -> Result<[^\n]+> \{', modified)
    if signature is None:
        # Opening helper uses a multiline signature.
        signature = re.search(r'    fn ' + method + r'\([\s\S]*?\) -> Result<[^\n]+> \{', modified)
    assert signature, method
    wrapper = f'''    fn {method}(&self) -> Result<{result_type}> {{
        let before = self.pos();
        let result = self.parity_original_{method}();
        let snapshot = match &result {{Ok(v)=>({render})(v),Err(e)=>parity_snapshot::error(e)}};
        parity_snapshot::helper(self,"{method}",&snapshot,before);
        result
    }}
'''
    modified = modified[:signature.start()] + wrapper + modified[signature.start():].replace('fn ' + method + '(', 'fn parity_original_' + method + '(', 1)
signature = '    fn maybe_parse_ascii_class(&self) -> Option<ast::ClassAscii> {'
assert modified.count(signature) == 1
wrapper = '''    fn maybe_parse_ascii_class(&self) -> Option<ast::ClassAscii> {
        let before = self.pos();
        let result = self.parity_original_maybe_parse_ascii_class();
        let snapshot = match &result {Some(c)=>std::format!("ascii({};{:?};{})",parity_snapshot::span(&c.span),c.kind,c.negated),None=>std::string::String::from("none")};
        parity_snapshot::helper(self,"maybe_parse_ascii_class",&snapshot,before);
        result
    }
'''
modified = modified.replace(signature, wrapper + signature.replace('fn maybe_', 'fn parity_original_maybe_'))
path.write_text(modified)
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case',
            'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
command = ['rustc', '--edition=2021', '--test', '--crate-name=regex_syntax', str(copy / 'lib.rs'), '-o', str(temp / 'rust-tests')]
for feature in features:
    command += ['--cfg', f'feature="{feature}"']
subprocess.run(command, check=True)
for name in ['runtime.tsv', 'assertions.tsv', 'helpers.tsv']:
    (temp / name).write_text('')
env = dict(os.environ, REGEX_AST_CAPTURE=str(temp / 'runtime.tsv'), REGEX_AST_ASSERTIONS=str(temp / 'assertions.tsv'), REGEX_AST_HELPERS=str(temp / 'helpers.tsv'))
subprocess.run([str(temp / 'rust-tests'), 'ast::parse::tests::', '--test-threads=1'], env=env, check=True)
rows = list(dict.fromkeys((temp / 'runtime.tsv').read_text().splitlines()))
fixture = ROOT / 'spec/fixtures/ast_runtime.tsv'
content = '# Pinned Rust parser-test inputs, replayed through public parse_with_comments; revision ' + revision + '\n'
content += '# test\tconfiguration\tpattern_hex\texpected_snapshot_hex\n' + '\n'.join(rows) + '\n'
if args.write_fixture:
    fixture.write_text(content)
elif fixture.read_text() != content:
    raise SystemExit('AST fixtures differ from pinned Rust')
helper_text = '# Exact private-helper outputs and cursor positions from pinned Rust\n' + (temp / 'helpers.tsv').read_text()
helper_path = ROOT / 'spec/fixtures/ast_helpers.tsv'
if args.write_fixture:
    helper_path.write_text(helper_text)
elif helper_path.read_text() != helper_text:
    raise SystemExit('Helper fixtures differ from pinned Rust')
executed = {int(row.split('\t')[1]) for row in (temp / 'assertions.tsv').read_text().splitlines()}
ledger = ['# source_assertion\tstatus\tcrystal_evidence\tnotes']
current = None
helper_tests = {'parse_decimal', 'parse_flag', 'parse_flags', 'parse_primitive_non_escape',
                'parse_set_class', 'parse_set_class_open', 'maybe_parse_ascii_class',
                'parse_escape', 'parse_octal', 'parse_hex_two', 'parse_hex_four',
                'parse_hex_eight', 'parse_hex_brace', 'parse_unicode_class',
                'parse_perl_class', 'parse_unsupported_backreference'}
for number, line in enumerate(original.splitlines(), 1):
    match = re.match(r'    fn (\w+)\(', line)
    if match:
        current = match[1]
    if number < original[:test_start].count('\n') or not re.search(r'\bassert(?:_eq)?!\(', line):
        continue
    assert number in executed, f'Unexecuted assertion {current}:{number}'
    evidence = 'spec/ast_runtime_parity_spec.cr'
    if current in helper_tests:
        evidence += ',spec/ast_helpers_parity_spec.cr'
    ledger.append(f'src/ast/parse.rs:{number}\truntime_verified\t{evidence}\t{current}: original Rust assertion executed; full result replayed')
mod = (source / 'ast/mod.rs').read_text()
for number, line in enumerate(mod.splitlines(), 1):
    if 'assert!(' not in line or number < 1750:
        continue
    reason = 'Rust explicit Drop and 16KiB native thread stack have no Crystal GC equivalent' if number < 1799 else 'Rust enum allocation size is not a Crystal object-layout contract'
    ledger.append(f'src/ast/mod.rs:{number}\tskipped_language_contract\t-\t{reason}')
audit = ROOT / 'plans/inventory/rust_ast_assertion_audit.tsv'
audit_text = '\n'.join(ledger) + '\n'
if args.write_fixture:
    audit.write_text(audit_text)
elif audit.read_text() != audit_text:
    raise SystemExit('AST assertion audit differs from pinned Rust')
subprocess.run([str(temp / 'rust-tests'), 'ast::tests::', '--test-threads=1'], check=True)
print(f'{len(executed)} executed parser assertion locations; two Rust layout/destructor exclusions')
print(f'{len(rows)} public AST snapshots from upstream parser-test inputs')
if not args.rust_only:
    subprocess.run(['crystal', 'spec', 'spec/ast_runtime_parity_spec.cr', 'spec/ast_helpers_parity_spec.cr'], env=dict(os.environ, CRYSTAL_CACHE_DIR=str(temp / 'crystal-cache')), check=True)
