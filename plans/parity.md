# Regex Syntax Parity Plan

This file is the curated parity roadmap for the Crystal port of Rust
`regex-syntax`.

It follows the `cross-language-crystal-parity` workflow:

- `plans/parity.md` decides sequence.
- `plans/inventory/rust_port_inventory.tsv` is the curated day-to-day ledger.
- `plans/inventory/rust_source_parity.tsv` and
  `plans/inventory/rust_test_parity.tsv` are evidence manifests, not the roadmap.
- Work closes by feature bucket, not by helper method.

Checklist rules:

- `[x]` in the verification audit or remaining phases means the stated scope
  has reproducible evidence and no required work remains within that scope.
- `[ ]` means implementation, verification, or integration work remains.
- Checkboxes in the historical feature buckets record prior implementation
  milestones; they do not provide independent exhaustive parity signoff.
- Buckets here should stay branch-sized and user-visible. Detailed row-by-row
  drift belongs in the inventories.

## Evidence Sources

- Upstream source of truth: `vendor/regex-syntax/`
- Curated working ledger: `plans/inventory/rust_port_inventory.tsv`
- Generated source manifest: `plans/inventory/rust_source_parity.tsv`
- Generated test manifest: `plans/inventory/rust_test_parity.tsv`

## Verification audit (2026-10-11)

- Source revision: `72d650cb0a880a01ab6dc2137c0888e8f89740f7`,
  `regex-syntax` 0.8.11. The vendor symlink resolves to the same pinned tree
  used by the consuming `regex-automata` repository.
- [x] Repair parsed alternation normalization and verify translator outputs.
  `a|b` now lowers to Unicode class `[a-b]`. The full eight-assertion Rust
  `smart_alternation` matrix has independent expected node shapes, including
  common-prefix lifting. Singleton raw bytes, Unicode-first class merging,
  byte fallback, duplicate literals, and empty/singleton branches are covered.
- The prior `smart_alternation` mapping was inaccurate: only three of its eight
  assertions had been represented, and the public parsing spec explicitly
  expected the wrong `a|b` shape. Inventory labels alone did not establish
  semantic parity.
- `scripts/check_hir_output_parity.py` extracts all 316 distinct literal
  `t`/`t_bytes` pattern/configuration pairs from the vendored translator tests,
  compiles both implementations without registry downloads, and compares exact
  printed HIR. The Rust-generated fixture is also run by `make test`.
- That comparison exposed and repaired additional gaps: dot lowering to classes,
  Unicode scalar interval canonicalization and assigned-property printing,
  large-range case folding, negated Perl classes inside unions, escaped ASCII punctuation
  in classes, and verbose comments around counted repetitions.
- Validation: 147 default-feature Rust unit tests; 683 Crystal specs; 316/316
  exact output comparisons; and 22 downstream Thompson specs run through a
  temporary harness against this checkout, including exact `a|b`, Unicode,
  invalid-byte, repetition, and capture graphs.
- Inventory checks now accept the canonical `ported`/`skipped` statuses. A
  duplicate source `repetition` row was removed; source/test/port checks pass
  with the recorded regex discovery backend (877 source items, 158 test items).
- [x] Verify literal translator property calls, including local helper closures.
  `--properties` compares 457 distinct pattern/configuration pairs across all
  twelve HIR property fields against Rust-generated snapshots. Nested negated
  singleton classes now lower to literals, and empty property unions report an
  unknown static capture count as Rust does. Corrected singleton class node
  assertions in the existing ports. Dynamic fixtures remain outside this slice.
- [x] Verify 64-bit length boundaries with eight additional Rust oracle cases.
  HIR and Properties lengths use UInt64, minimum arithmetic saturates at
  UInt64::MAX, and maximum arithmetic returns nil on overflow. Coverage includes
  large bounded repetitions, nested multiplication, concatenation, alternation,
  and optional repetitions. The property fixture now has 465 cases. Validation:
  1,149 Crystal specs, 465/465 property comparisons, and 22 downstream Thompson
  specs pass; formatting, lint, and all three inventory checks pass.
- [ ] Full independent assertion-by-assertion audit of the remaining Rust test
  ports. Phase 1 below now verifies the complete default-feature translator
  runtime and HIR constructor compositions. Phase 2 verifies Parser/AST.
  Unicode/class algebra,
  extraction/UTF-8, and diagnostic/support-module assertion audits remain open
  in phases 3–6. Follow-up bead: `regex-syntax-u0w`. Existing mappings outside
  the verified slices must not be mistaken for a fresh exhaustive signoff.

## Current State

- `rust_test_parity.tsv`: `144 ported`, `14 skipped`, `0 partial`
- `rust_source_parity.tsv`: `869 ported`, `1 skipped`, `7 partial`

Interpretation (inventory coverage, not independent assertion signoff):

- The five parser-helper test partials are now closed by exact helper-result
  and cursor-position replays. Rows outside completed phases still require
  independent assertion audits despite their `ported` labels.
- The remaining source partials are still mostly API/model-shape mappings:
  Crystal class hierarchies, wrapper objects, builder-style APIs, and
  idiomatic replacements for Rust enums, traits, and free functions.
- The remaining source partials are now concentrated mostly in AST/HIR node
  shape differences and a few explicit cross-language model differences rather
  than top-level lib, parser, Unicode, interval, or translator helper
  surfaces.
- Vendored Unicode-table compatibility namespaces like `perl_decimal`,
  `perl_space`, `PROPERTY_NAMES`, and `PROPERTY_VALUES` are now exposed
  directly in Crystal instead of being left as documented alias drift.
- The remaining source partials are now almost entirely explicit
  cross-language type-shape differences: Rust enums/traits versus Crystal
  wrapper classes, mixins, and generic specializations.
- Broad semantic parity is no longer being driven by generated-manifest
  `missing` rows. The manifests are now mostly documentation of intentional
  cross-language shape differences.

## Remaining Work in Feature-Sized Phases

No unfixed runtime mismatch has been confirmed by the completed comparisons.
The known remaining discrepancies are incomplete assertion coverage in phases
3–6, seven source/API model mappings, and the downstream installed shard still
containing the older implementation. Suspected edge cases
below are audit targets, not established bugs. Keep the upstream revision pinned
while completing these phases; fix any newly reproduced mismatch in its phase.

Work in order. Each phase should produce a reviewable feature commit containing
its tests, fixes, and evidence updates. Track the audit under `regex-syntax-u0w`.

### Phase 1 — HIR construction and dynamic translator parity

- [x] Close the gap between parsed patterns and directly constructed HIR.
  Compare Rust `src/hir/mod.rs` smart constructors and `Properties` with Crystal
  direct constructors and wrappers. Cover empty/singleton classes and branches,
  impossible branches, nested repetitions, capture counts, look sets, and length
  overflow in compositions. In particular, check negated-class helper results
  and static capture analysis when an alternation contains an impossible branch.
- [x] Port dynamic translator assertions that the literal-call extractor misses.
  Review every test in `src/hir/translate.rs` against the existing specs, including
  generated patterns, configuration changes, and expected errors. Record which
  assertions the 316 output and 465 property fixtures cover and add exact
  assertions for the remainder. Do not count a test-name mapping as coverage of
  all its assertions.

**Exit evidence:** an assertion mapping for the full translator test module,
Rust-derived structural/property expectations for direct constructors, and no
unexplained differences in the covered output or property fields. Retain the
existing eight-case `smart_alternation` structural matrix.

**Completed evidence (2026-10-11):** tests were ported before implementation.
The initial focused run had 19 failures across 568 examples; the expanded
constructor matrix exposed further differences before fixes. Final fixtures
replay 565 calls from all 47 default-feature upstream translator tests, 444
constructor compositions, and 144 standalone property unions. The assertion
ledger `plans/inventory/rust_hir_assertion_audit.tsv` accounts for all 545
assertion locations (537 executed, eight excluded by disabled-feature tests)
and the two no-panic fuzz calls. Original Rust assertions remain in the native
run; new constructor cases are Rust-derived characterization, not upstream tests.

Fixed maximum-length-based repetition simplification for captured empty
expressions; impossible-branch length/static-capture properties; smart class
construction and empty-class fail node kinds; negated class helper queries and
conversions; persistent flag negation; and translator error spans. Corrected the
existing complement-of-Any node expectation and the five exact-empty literal
expectations that had mistranslated Rust's `inexact([E("")], ...)` helper.

Reproduce with `python3 scripts/check_hir_construction_parity.py`; expectations
can only be regenerated from the passing Rust run using `--write-fixture`.
All 2,308 Crystal specs, 147 default-feature Rust unit tests, 316 display cases,
465 property cases, and 22 downstream Thompson harness specs pass. Formatting,
lint, no-codegen compilation, and all three inventory checks pass. No vendored
files or installed downstream dependency were changed. Phase 2 completion
is recorded below; phases 3–7 retain their open status.

### Phase 2 — Parser and AST behavior

- [x] Audit `src/ast/parse.rs` and `src/ast/mod.rs` tests assertion by assertion.
  Compare exact AST kinds, nesting, flags, capture metadata, comments, byte
  offsets, line/column positions, and successful parse results. Include Unicode
  input, verbose mode, repetitions, escapes, and class-set operators.
- [x] Resolve the five partial test mappings as one parser feature:
  `parse_decimal`, `parse_flag`, `parse_primitive_non_escape`, `parse_set_class`,
  and `parse_set_class_open`. Exercise equivalent public behavior where possible;
  document genuinely inaccessible internal-only assertions individually instead
  of treating representative public tests as a complete port.

**Exit evidence:** complete parser/AST assertion mapping with exact independent
expectations; each partial row either fully covered or explicitly justified by
its remaining unsupported helper contract. No blanket closure from passing
representative patterns.

**Completed evidence (2026-10-12):** ported the Rust-derived tests before
implementation. The initial public corpus had 208 failures in 854 examples;
the direct helper corpus then exposed 16 additional failures. Characterization
cases and the default nesting-limit regression also failed before fixes.
`python3 scripts/check_ast_parity.py` executes all 29 original parser tests with
their assertions preserved and accounts for all 344 assertion locations in
`plans/inventory/rust_ast_assertion_audit.tsv`. It replays 862 exact public AST
results (851 original test inputs plus 11 characterization inputs) and 708
helper results with final cursor positions, including nonzero starting offsets.
The three generated fixed-hex loops retain all 127,232 upstream scalar cases,
with exact character, escape kind/form, and span expectations. Fixtures can only
be regenerated from a passing native Rust run via `--write-fixture`.

Fixed AST operator/flags/capture-name spans, brace-vs-one-letter property kinds,
bounded repetition identity, raw control escape metadata, class union structure,
class prefix/verbose spans, nested class depth accounting, malformed escape and
group diagnostics, repeated flag negation, and unmatched closing groups. AST
greediness now records syntax; the translator applies `U`. The public parser and
builder defaults now use Rust's nesting limit of 250. Corrected older specs that
expected collapsed `ClassSet::union` constructors and incorrect hex-error spans.

All five partial parser-test mappings are now ported. Test-only helper access
keeps private parser APIs private in the library. The only two assertions in
`src/ast/mod.rs` remain explicitly excluded Crystal contracts: Rust enum memory
size and explicit destruction on a 16KiB thread stack; both original native tests
still execute successfully. Crystal uses object allocation and garbage collection.

Final gates: 3,882 Crystal examples, formatting, lint, no-codegen compilation,
147 original default-feature Rust tests, 316 exact HIR display and 465 property
comparisons, the Phase 1 translator/construction oracle, all three inventories,
and 22 downstream Thompson harness specs pass. Phase 3 is next. The downstream
installed shard and the downstream Thompson parity signoff remain unchanged.

### Phase 3 — Unicode and character-class algebra

- [x] Independently verify `src/unicode.rs`, `src/unicode_tables/`,
  `src/hir/interval.rs`, and class tests in `src/hir/mod.rs`.
  Cover canonicalization, union/intersection/difference/symmetric difference,
  complements, scalar boundaries and surrogates, byte conversion, case folding,
  property aliases, and property queries. Compare complete intervals and errors,
  including direct class helper calls as well as parsed classes.
- [x] Recheck skipped feature-disabled tests against Crystal's always-available
  Unicode tables. Retain only skips justified by unavailable build modes;
  validate the corresponding default-mode behavior and table version.

**Exit evidence:** exact interval/table/query assertions for the pinned upstream
and documented reasons for feature-mode exclusions. Existing large-range fold
and surrogate fixes remain covered without sampling away boundary cases.

**Completed evidence (2026-10-12):** tests were added before fixes. The first
replay had 20 failing comparisons; complemented-class folding then exposed five
more, and two additional symmetric-difference state regressions failed before
their fix. `python3 scripts/check_class_unicode_parity.py` runs all 16 enabled
upstream class tests and six Unicode tests with their original assertions intact,
plus three characterization tests. It accounts for 137 executed assertion
locations and three feature-mode exclusions in
`plans/inventory/rust_class_unicode_assertion_audit.tsv`.

The Rust-generated fixture replays 8,986 exact results: 574 class operations and
boundary/conversion cases, 18 folded-state sequences, 515 complete range tables,
1,179 property-name/value aliases, 2,938 simple-fold mappings, and 1,881 queries
both directly and through parsing (including complete error kinds and spans).
The Crystal folder also traverses all 1,112,064 Unicode scalars against those
independent mappings, checking unmapped scalars as well as mapped ones. Table key
inventories are compared exactly, including absence of additional aliases. All
14 generated table modules match the pinned Unicode 16.0.0 data or are verified
aliases of those tables; native table headers also enforce the version.

Fixed missing `%`–apostrophe entries in `Other_Punctuation`, missing apostrophes
in `Case_Ignorable` and `Quotation_Mark`, property lookup bypassing canonical
names (`incb` and `word`), case folding after class complementation, and cached
folding-state preservation through clone, identical push, and symmetric
difference. Perl `\w`/`\W` translation uses the dedicated word helper.
`python3 scripts/sync_unicode_ranges.py` checks every range constant;
`--write` repairs generated constants from the independently verified Rust
fixture. No fixture expectations are generated from Crystal.

The two disabled-case-fold assertions and the disabled-case-fold panic test
require a Rust build without case tables. Crystal always includes those tables,
so the exclusions remain explicit while default-mode behavior is exhaustively
checked. The `Bound`/`Interval` trait representation rows remain partial for
Phase 6 API reconciliation; the byte/scalar operation behavior is now verified.

Final gates: 12,874 Crystal examples, formatting, lint, compilation, 147 original
Rust unit tests, 316 HIR display comparisons, 465 property comparisons, the
Phase 1 HIR and Phase 2 AST oracles, all three inventory checks, the full Unicode
range sync check, and 22 downstream Thompson harness specs pass. Phase 4 is
next; downstream dependency adoption and Thompson signoff remain in Phase 7.

### Phase 4 — Literal extraction, optimization, and UTF-8 helpers

- [ ] Audit `src/hir/literal.rs` and `src/utf8.rs` against the Crystal support
  modules. Port dynamic loops and edge cases, including empty/infinite literal
  sequences, prefix/suffix extraction, exactness flags, ordering, deduplication,
  extraction limits, and UTF-8 range boundaries.

**Exit evidence:** full relevant upstream assertion mapping, exact ordered
literal sequences with their metadata, and exact UTF-8 byte-range expectations.
Rust ownership/destructor-only checks may stay skipped with explicit rationale.

### Phase 5 — Diagnostics, printing, and visitor contracts

- [ ] Compare parser/translator error kinds, primary and auxiliary spans,
  multiline formatting, and public error text with Rust expectations. The
  current output oracle only compares successful parses; add an error oracle or
  Rust-derived diagnostic fixtures for this phase.
- [ ] Audit AST/HIR printer and visitor tests, including escaping, round trips,
  hook order, class-set traversal, and early failure propagation. Distinguish
  language-specific exception mechanics from observable traversal behavior.

**Exit evidence:** exact diagnostic fixtures, printer outputs and traversal
traces, with any intentional presentation/API differences recorded explicitly.
Do not infer diagnostic fidelity from successful HIR output comparisons.

### Phase 6 — Public API reconciliation and audit completeness

- [ ] Reconcile the seven source partials after behavioral phases 1–5:
  AST `Ast`, `ClassSet`, and `ClassSetItem`; AST/HIR `Visitor`; interval `Bound`
  and `Interval`. Verify public contracts, then classify each remaining shape
  difference with a precise rationale and tests for the equivalent behavior.
- [ ] Review all 14 skipped test rows and the skipped internal `Either` API.
  Check that each exclusion concerns Rust runtime/build mechanics rather than
  untested user-visible behavior. Reconcile the 158 test inventory rows with
  the 147 executable default-feature Rust tests, including configuration and
  exclusion reasons; the counts are not interchangeable.
- [ ] Complete the assertion audit ledger across all modules. Keep the existing
  regex-discovery backend explicit; if switching to tree-sitter discovery,
  review manifest changes separately rather than silently regenerating them.

**Exit evidence:** every upstream assertion has a test/fixture reference or a
specific supported exclusion, all manifest checks pass, and no broad semantic
claim rests solely on a `ported` label.

### Phase 7 — Downstream adoption and parity signoff

- [ ] Refresh the `regex-automata` installed dependency to the reviewed
  `regex-syntax` revision through its normal dependency workflow. The 22 passing
  Thompson specs used a temporary harness that selected this checkout; they
  do not prove the older installed shard has been updated.
- [ ] Run the downstream suite with normal dependency resolution and compare
  exact Thompson graphs for alternation, captures, repetitions, Unicode, and
  invalid-byte patterns against the pinned Rust implementation. Investigate any
  remaining graph difference in the owning library.
- [ ] Update the downstream parity plan with its own evidence, then reconcile
  this plan's completion criteria. Keep Thompson parity open until that
  downstream verification is complete.

**Exit evidence:** recorded dependency revision, reproducible normal-resolution
integration commands, exact Rust/Crystal graph comparisons, and passing upstream
and downstream gates. An upstream syntax fix alone does not close Thompson parity.

## Historical Feature Buckets

These are prior implementation milestones. Their closure claims below are
historical and are subject to the independent phases above.

### Previously Completed Implementation Work

- [x] Parser and AST span/position fidelity
  AST `Position` and `Span` now track vendored Rust byte offsets while
  preserving line/column tracking and parser backtracking. The parser cursor
  model now keeps scan position and byte offset separate, and direct coverage
  exists for multibyte literal spans, multibyte capture-name error spans,
  non-ASCII flag error spans, multiline comment spans, and multibyte
  class-range spans.

- [x] AST source/API compatibility layer
  The Crystal AST now exposes a larger Rust-shaped compatibility surface
  instead of leaving those rows as pure documentation drift: dedicated
  `Flag`, `CaptureName`, `ClassUnicodeKind`, `ClassUnicodeOpKind`,
  `HexLiteralKind`, `SpecialLiteralKind`, and `RepetitionRange` wrappers,
  Rust-like `Ast.*` constructor helpers, enum-based `Flags.flag_state`,
  duplicate-detecting `Flags.add_item`, `SetFlags#flags`, parser-backed named
  capture metadata, non-capturing groups with explicit empty `Flags`, and
  Rust-style empty/singleton collapsing for `Alternation#into_ast` and
  `Concat#into_ast`.

- [x] AST compatibility aliases and vendored predicates
  The Crystal AST now exposes more of vendored `src/ast/mod.rs` with the
  Rust-facing names instead of only nested Crystal-native helpers: explicit
  `AssertionKind`, `ClassAsciiKind`, `ClassPerlKind`,
  `ClassSetBinaryOpKind`, `FlagsItemKind`, `GroupKind`, `LiteralKind`, and
  `RepetitionKind` aliases; vendored predicate names such as `is_one_line`,
  `is_valid`, `is_negation`, and `is_capturing`; direct `ClassSet.union` and
  `ClassSetUnion.into_item` compatibility helpers; and direct constructor
  coverage for the remaining concrete AST node types.

- [x] Vendored ast::parse compatibility namespace
  The Crystal port now exposes the upstream `ast::parse` surface through
  `Regex::Syntax::AST::Parse`, with direct `Parser` and `ParserBuilder`
  compatibility aliases and coverage for `new`, `build`, `parse`,
  `parse_with_comments`, `ignore_whitespace`, `nest_limit`, `octal`, and
  `empty_min_range`.

- [x] HIR class and look-set compatibility layer
  The Crystal HIR now exposes a larger Rust-shaped compatibility surface for
  class dispatch and look-set APIs instead of leaving those rows as pure
  documentation drift: dedicated `Hir::Class`, `ClassBytesRange`,
  `ClassUnicodeRange`, `ClassBytesIter`, `ClassUnicodeIter`, and
  `LookSetIter` wrappers, exact `LookSet#set_insert` / `set_remove` /
  `set_union` / `set_intersect` / `set_subtract` aliases, explicit `iter`
  wrappers, direct start/end/len range helpers, and HIR constructor overloads
  for `literal`, `concat`, and `alternation` on HIR wrapper values.

- [x] HIR node and class compatibility aliases
  The Crystal HIR now exposes more of vendored `src/hir/mod.rs` with the
  Rust-facing names instead of only equivalent Crystal-native helpers:
  explicit `HirKind`, `ClassBytes`, and `ClassUnicode` compatibility aliases,
  direct `is_alternation_literal`, `is_ascii`, `is_utf8`, and `is_empty`
  predicates, wrapper-range constructors and `push` overloads for byte and
  Unicode classes, and direct coverage for those vendored names.

### Semantics Closure

- [x] Parser and AST semantics are closed as a feature bucket.
  This includes captures, flags, class parsing, verbose mode, octal mode,
  special word boundaries, Unicode property parsing, repetition forms,
  structured parser errors, comment capture, and direct AST behavior across the
  vendored parser matrix.

- [x] Translator and HIR semantics are closed as a feature bucket.
  This includes AST-to-HIR lowering, Unicode and byte behavior, UTF-8 gating,
  class-set algebra, smart concat/alternation/repetition construction,
  look/anchor handling, line terminator behavior, case folding, and the
  vendored translator regression matrix.

- [x] Unicode and character-class parity are closed as a feature bucket.
  This includes vendored Unicode tables, property aliasing, `gc` / `sc` / `scx`
  / `age` / `wb` / `gcb` / `sb` queries, Perl classes, ASCII classes, Unicode
  word behavior, simple case folding, and byte-vs-Unicode class behavior.

### Support Module Closure

- [x] Dedicated support modules are closed as a feature bucket.
  The Crystal port now has dedicated subsystems for structured errors,
  interval sets, UTF-8 helpers, AST printers, HIR printers, AST visitors, HIR
  visitors, and HIR literal extraction/optimization instead of leaving those
  behaviors embedded in ad hoc parser or translator helpers.

- [x] Public parser, AST, HIR, and helper APIs are closed as a feature bucket.
  The public surface now includes the staged parser/builders, top-level helper
  APIs, HIR properties and look-set analysis, class helpers, literal-extractor
  APIs including the vendored `src/hir/literal.rs` helper surface, and the
  direct AST/HIR helper surface needed for vendored-style behavioral coverage.

### Diagnostics and Round-Trip Closure

- [x] Error and diagnostics behavior is closed as a feature bucket.
  Structured AST and HIR errors exist, parser and translator errors have
  vendored-style kind/span coverage, and formatter behavior is exercised for
  representative multiline and structured-diagnostic cases.

- [x] Print, visitor, and round-trip behavior is closed as a feature bucket.
  AST/HIR printers, AST/HIR visitors, escape-form preservation, and the
  vendored print/visitor regression matrices are covered closely enough that
  they no longer drive active parity work.

### Reconciliation Closure

- [x] Manifest and ledger reconciliation is closed as a feature bucket.
  The inventories are no longer aspirational. They distinguish implemented
  behavior, compile-time Rust-only `skipped` rows, and intentional
  Crystal model differences instead of mixing those states together.

- [ ] Broad parity work is fully closed.
  The independent assertion audit above remains open. Previously closed
  buckets are historical mappings, not evidence that every upstream assertion
  has been checked for fidelity.

## What Still Shows As `partial`

These do not justify separate helper-sized buckets by themselves:

- Test mappings now contain 144 ported tests and 14 explicit build-mode or
  runtime-layout/destructor exclusions, with no partial test rows. Phase 2
  closed the five parser-helper mappings using exact helper outputs and cursors.

- Source-level API-shape rows in `rust_source_parity.tsv`
  Most remaining partial rows are deliberate language-model differences:
  Crystal uses concrete node classes instead of Rust enums, direct initializers
  instead of free constructor functions, wrapper objects instead of sum types,
  and idiomatic predicates or builders instead of one-for-one method names.

## Execution and Verification

For each phase, reproduce differences against the pinned Rust checkout, add
failing parity specs first, make the fixes, update the affected inventory rows
and assertion evidence, and commit before starting the next phase.

Run the existing oracles where applicable:

```bash
python3 scripts/check_hir_output_parity.py --rust-tests
python3 scripts/check_hir_output_parity.py --properties
```

Before each feature commit, run `make format`, `make lint`, `make test`, and the
source/test/port inventory checks. Keep generated artifacts in `temp/`. Add
phase-specific comparison commands to `docs/testing.md` so closure can be
reproduced. A future upstream refresh is a separate scoped task: regenerate
manifests intentionally, record the new revision, and reopen affected phases.

## Project-Level Done Criteria

- [x] No generated parity manifest is still carrying baseline `missing` drift.
- [ ] Phases 1–6 provide independent semantic, AST, and assertion-level signoff.
- [ ] Phase 7 verifies downstream dependency adoption and Thompson graph parity.
- [x] Remaining `partial` rows are documented and evidence-backed.
- [x] Quality gates continue to pass:
  `make format`, `make lint`, `make test`
- [x] New parity changes stay anchored to vendored Rust code and vendored Rust
  tests instead of local invention.
