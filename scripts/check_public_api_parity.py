#!/usr/bin/env python3
"""Verify public API output, native test configuration and the complete assertion ledger.

Regex discovery deliberately matches the existing inventory backend. Assertions
are counted by source location in #[cfg(test)] modules, not runtime invocations.
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
temp = ROOT / 'temp/public-api-parity'
temp.mkdir(parents=True, exist_ok=True)
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case',
            'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
cfg = [arg for feature in features for arg in ['--cfg', f'feature="{feature}"']]

def run(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs)

def verify(path, value):
    if args.write_fixture:
        path.write_text(value)
    elif path.read_text() != value:
        raise SystemExit(f'{path.name} differs from pinned Rust; review before regenerating')

# Earlier feature ledgers remain independently reproducible by their own oracles.
covered = {}
for path in sorted((ROOT / 'plans/inventory').glob('rust_*_assertion_audit.tsv')):
    if path.name.startswith('._') or path.name == 'rust_public_api_assertion_audit.tsv':
        continue
    for line in path.read_text().splitlines():
        if line and not line.startswith('#'):
            cols = line.split('\t')
            covered.setdefault(cols[0], []).append((path.name, cols))
assertions = {}
for path in sorted(source.rglob('*.rs')):
    if path.name.startswith('._'):
        continue
    text = path.read_text()
    start = re.search(r'#\[cfg\(test\)\]', text)
    if not start:
        continue
    for number, line in enumerate(text.splitlines(), 1):
        if number > text[:start.start()].count('\n') and re.search(r'\b(?:assert(?:_eq|_ne)?|debug_assert(?:_eq|_ne)?)!\(', line):
            assertions[f'src/{path.relative_to(source)}:{number}'] = line
missing = set(assertions) - covered.keys()
expected_missing = {f'src/lib.rs:{n}' for n in [393, 401, 402, *range(408, 419), 425, 431]}
expected_missing |= {f'src/hir/mod.rs:{n}' for n in [3831, 3850, 3853, 3857, 3860, 3863, 3869, 3871]}
expected_missing.add('src/hir/translate.rs:3478')
assert missing == expected_missing, (missing - expected_missing, expected_missing - missing)

# Instrument only remaining locations in a disposable source copy. Original
# assert/assert_eq/assert_ne still run with their complete arguments unchanged.
copy = temp / 'src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source, copy)
for name in ['lib.rs', 'hir/mod.rs', 'hir/translate.rs']:
    lines = (source / name).read_text().splitlines(keepends=True)
    for number, line in enumerate(lines, 1):
        if f'src/{name}:{number}' in missing:
            lines[number - 1] = re.sub(r'\b(assert(?:_eq|_ne)?)!\(',
                lambda m: f'crate::parity_{m[1]}!({number}, ', line)
    (copy / name).write_text(''.join(lines))
with (copy / 'lib.rs').open('a') as file:
    file.write('''
#[cfg(test)]
fn parity_record(file: &str, line: u32) {
    use std::io::Write;
    let mut out = std::fs::OpenOptions::new().create(true).append(true)
        .open(std::env::var("REGEX_API_ASSERTIONS").unwrap()).unwrap();
    writeln!(out, "{}:{}", file.split("/public-api-parity/").last().unwrap(), line).unwrap();
}
''')
    for macro in ['assert', 'assert_eq', 'assert_ne']:
        file.write(f'#[allow(missing_docs)]\n#[macro_export]\nmacro_rules! parity_{macro} {{ ($line:expr, $($args:tt)*) => {{{{ crate::parity_record(file!(), $line); {macro}!($($args)*); }}}}; }}\n')
binary = temp / 'rust-tests'
subprocess.run(['rustc', '--edition=2021', '--test', '--crate-name=regex_syntax', str(copy / 'lib.rs'), '-o', str(binary), *cfg], check=True)
record = temp / 'assertions.tsv'
record.write_text('')
output = run([str(binary), '--test-threads=1'], env=dict(os.environ, REGEX_API_ASSERTIONS=str(record)))
assert '147 passed; 0 failed' in output
executed = set(record.read_text().splitlines())
excluded = {'src/lib.rs:425', 'src/lib.rs:431'}
assert executed == missing - excluded, (executed, missing)
ledger = ['# source_assertion\tstatus\tcrystal_evidence\tnotes']
for key in sorted(missing):
    status, evidence, note = 'runtime_verified', 'spec/public_api_parity_spec.cr', 'Original Rust assertion executes; exact assertion port and native public API snapshots'
    if key in excluded:
        status, evidence, note = 'excluded_feature', 'plans/inventory/rust_test_configuration.tsv', 'Requires absent unicode-perl; Crystal ships all Unicode tables and has no table-disabled build'
    elif key == 'src/hir/mod.rs:3831':
        status, evidence, note = 'excluded_runtime', 'plans/inventory/rust_test_configuration.tsv', 'Rust recursive value Drop stress test; Crystal GC-managed references have no custom Drop contract'
    ledger.append('\t'.join([key, status, evidence, note]))
verify(ROOT / 'plans/inventory/rust_public_api_assertion_audit.tsv', '\n'.join(ledger) + '\n')

# Match identities, not just totals, against the executable default-feature list.
native = {line.removesuffix(': test') for line in run([str(binary), '--list']).splitlines() if line.endswith(': test')}
configuration = ['# source_test_id\tnative_test\tdefault_features\tcrystal_status\treason']
listed = set()
for line in (ROOT / 'plans/inventory/rust_test_parity.tsv').read_text().splitlines():
    if not line or line.startswith('#'):
        continue
    key, status, refs, note = line.split('\t')
    file, test = key.split('::test::')
    module = file.removeprefix('src/').removesuffix('.rs').removesuffix('/mod')
    module = '' if module == 'lib' else module.replace('/', '::') + '::'
    name = module + 'tests::' + test
    enabled = name in native
    if enabled:
        listed.add(name)
    if status == 'ported':
        assert enabled, key
        reason = 'Default-feature Rust test; Crystal assertion evidence in rust_test_parity.tsv'
    else:
        assert status == 'skipped'
        assert enabled == (test in ['ast_size', 'no_stack_overflow_on_drop']), key
        reason = note
    configuration.append('\t'.join([key, name, str(enabled).lower(), status, reason]))
assert listed == native and len(native) == 147
assert len(configuration) - 1 == 158
verify(ROOT / 'plans/inventory/rust_test_configuration.tsv', '\n'.join(configuration) + '\n')

# A single index makes the scope of the full location audit inspectable.
index = ['# source_assertion\tfeature_ledger\tstatus\tcrystal_evidence\tnotes']
for key in sorted(assertions):
    if key in covered:
        name, cols = covered[key][0]
    else:
        name = 'rust_public_api_assertion_audit.tsv'
        cols = next(row.split('\t') for row in ledger[1:] if row.startswith(key + '\t'))
    assert len(cols) == 4, (key, cols)
    cols = cols.copy()
    if cols[2] == '-':
        assert cols[1] in ['feature_disabled', 'skipped_build_mode', 'skipped_language_contract'], (key, cols)
        cols[2] = 'plans/inventory/rust_test_configuration.tsv'
    for ref in re.split('[;,]', cols[2]):
        assert (ROOT / ref).exists(), (key, ref)
    index.append('\t'.join([key, name, *cols[1:]]))
verify(ROOT / 'plans/inventory/rust_assertion_audit.tsv', '\n'.join(index) + '\n')

rlib = temp / 'libregex_syntax.rlib'
subprocess.run(['rustc', '--edition=2021', '--crate-type=rlib', '--crate-name=regex_syntax', str(source / 'lib.rs'), '-o', str(rlib), *cfg], check=True)
subprocess.run(['rustc', '--edition=2021', 'scripts/parity/public_api.rs', '--extern', f'regex_syntax={rlib}', '-o', str(temp / 'oracle')], check=True)
rows = run([str(temp / 'oracle')])
verify(ROOT / 'spec/fixtures/public_api.tsv', '# Pinned Rust public API; revision ' + revision + '\n# domain\tinput\texpected\n' + rows)
print(f'{len(assertions)} assertion locations accounted for; 158 test identities = 147 default + 11 disabled; {len(rows.splitlines())} public API snapshots')
if not args.rust_only:
    subprocess.run(['crystal', 'spec', 'spec/public_api_parity_spec.cr'], env=dict(os.environ, CRYSTAL_CACHE_DIR=str(ROOT / 'temp/crystal-cache')), check=True)
