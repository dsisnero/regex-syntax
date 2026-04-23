# Regex Syntax Completion Plan

## Goal

Finish the Crystal port so Rust `regex-syntax` remains the source of truth for:

- parser behavior
- HIR behavior
- Unicode behavior
- error behavior
- exported surface area where this repo intends API parity
- upstream test coverage and parity tracking

This plan is based on the current Crystal codebase and the vendored Rust source under `vendor/regex-syntax/`. It avoids speculative work. Every gap below is tied to code or manifests that exist in this repository today.

## Verified Current State

The current port is no longer a toy parser. These areas are already working and covered:

- single staged pipeline: source -> AST -> HIR
- one AST parser path only (`AstParser`)
- named captures and capture indices
- `nest_limit` enforcement
- class-set binary operators `&&`, `--`, `~~`
- ASCII classes and bracketed class parsing
- Unicode property namespaces currently wired locally: `gc`, `sc`, `scx`, `age`, `gcb`, `wb`, `sb`
- Rust-style special word boundaries and angle forms
- Unicode simple-fold support now backed by vendored `case_folding_simple`
- full quality gates currently pass: `make format`, `make lint`, `make test`

## Verified Remaining Gaps

## 1. Parity Inventories Are Stale

The manifests in:

- [plans/inventory/rust_test_parity.tsv](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/plans/inventory/rust_test_parity.tsv)
- [plans/inventory/rust_source_parity.tsv](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/plans/inventory/rust_source_parity.tsv)
- [plans/inventory/rust_port_inventory.tsv](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/plans/inventory/rust_port_inventory.tsv)

still mark almost everything as `missing`, including features that are already implemented and tested. Right now they are not trustworthy as a progress report.

### Completion work

1. Regenerate the source/test inventories from the vendored Rust source using the existing scripts in [scripts/](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/scripts).
2. Replace baseline placeholder statuses with real statuses:
   - `done`
   - `partial`
   - `missing`
   - `not_applicable`
3. Add Crystal references for each completed or partial item.
4. Keep `plans/plan.md` and the TSV files aligned after each parity slice.

### Done when

- the TSV manifests reflect current repo reality
- already-ported features are no longer reported as missing
- new work can be pulled from the manifests directly without manual re-audit

## 2. Entire Upstream Modules Are Still Unported

The current Crystal source tree only contains:

- [src/regex-syntax.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex-syntax.cr)
- [src/regex/syntax/ast.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/ast.cr)
- [src/regex/syntax/parser.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/parser.cr)
- [src/regex/syntax/translate.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/translate.cr)
- [src/regex/syntax/hir.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/hir.cr)
- [src/regex/syntax/unicode.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/unicode.cr)

Compared with the vendored Rust crate, these upstream modules are still missing as Crystal modules/files:

- `ast/print.rs`
- `ast/visitor.rs`
- `error.rs` equivalent with structured error formatting
- `hir/interval.rs`
- `hir/literal.rs`
- `hir/print.rs`
- `utf8.rs`

This is not just a testing gap. It is missing implementation surface.

### Completion work

1. Port `hir/interval.rs` first.
   - This is foundational for class operations, canonicalization, negation, and case folding.
   - It should replace the current ad hoc interval-array helpers in [src/regex/syntax/translate.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/translate.cr).
2. Port `hir/literal.rs`.
   - This unlocks literal extraction, optimization, and a large block of upstream HIR tests currently marked missing.
3. Port `utf8.rs`.
   - This is required for upstream UTF-8 validation/range behavior parity.
4. Port `hir/print.rs` and `ast/print.rs`.
   - These are lower risk but necessary for module/test parity.
5. Port `ast/visitor.rs` if the project intends source-level API parity with upstream.
6. Port structured error formatting support.

### Done when

- the missing upstream modules above have Crystal equivalents or are explicitly marked `not_applicable`
- the corresponding TSV inventory rows are no longer blanket `missing`

## 3. AST Surface Is Still Simpler Than Rust

The AST in [src/regex/syntax/ast.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/ast.cr) is materially simpler than Rust:

- `Position` only stores `offset`
- `Span` only stores start/end offsets
- there is no Rust-style rich position metadata with line/column
- there is no `Comment` node surface
- there is no `WithComments`
- there is no `CaptureName` structure
- there is no rich `ClassUnicodeKind` / `ClassUnicodeOpKind` AST representation

The current parser stores Unicode class queries as a raw `name : String`, then resolves semantics later in [src/regex/syntax/unicode.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/unicode.cr). That is workable, but it is not Rust AST parity.

### Completion work

1. Decide the target explicitly:
   - full Rust AST shape parity
   - or intentional Crystal-only AST with behavioral parity only
2. If full AST parity is required, port the missing AST data model:
   - richer positions/spans
   - `Comment`
   - `WithComments`
   - `CaptureName`
   - structured Unicode class AST kinds
3. After the AST shape is ported, add AST-only specs for construction/printing/visitor behavior.

### Done when

- the intended AST parity target is documented
- the inventory no longer claims full AST API parity while the AST remains intentionally simplified

## 4. Escape Parsing Is Still Incomplete

The parser in [src/regex-syntax.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex-syntax.cr) now supports `\xNN`, but the escape surface is still narrower than upstream.

Verified from current code:

- `parse_escape` handles `dDsSwW`, `bB`, `< >`, `A z Z`, `pP`, and generic escaped literals
- there is no parser path for Rust-style Unicode literal escapes such as `\uXXXX`, `\UXXXXXXXX`, or brace forms
- there is no parser path for octal escapes
- there is no explicit numeric backreference rejection path; unsupported backreference handling is still missing as a dedicated parse behavior

This lines up with the still-missing upstream parser tests listed in `rust_test_parity.tsv`:

- `parse_hex_brace`
- `parse_hex_two`
- `parse_hex_four`
- `parse_hex_eight`
- `parse_octal`
- `parse_unsupported_backreference`

### Completion work

1. Port the Rust AST escape parser behavior from `vendor/regex-syntax/src/ast/parse.rs`.
2. Match Rust error surfaces for:
   - invalid digits
   - unexpected EOF
   - unsupported backreferences
3. Add the corresponding upstream parser specs before adding any new escape form.

### Done when

- Rust escape parser tests for supported forms are ported
- unsupported backreferences fail the Rust way
- no escape behavior is inferred from Crystal convenience rules alone

## 5. Flag Parsing and Flag Diagnostics Are Weaker Than Rust

Current flag parsing in [src/regex-syntax.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex-syntax.cr) is permissive:

- `parse_flags_items` accepts any characters until `:` or `)`
- `apply_flags_from_items` silently ignores unknown flags
- there is no duplicate flag diagnostic
- there is no duplicate negation diagnostic

Rust has explicit parser and error behavior for these cases.

There is also a stale comment in [spec/flag_handling_spec.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/spec/flag_handling_spec.cr) claiming class translation is not implemented, which is no longer true.

### Completion work

1. Port Rust flag parsing semantics from `vendor/regex-syntax/src/ast/parse.rs`.
2. Reject invalid flags instead of silently accepting them.
3. Add duplicate flag and duplicate negation diagnostics.
4. Update or remove the stale TODO/spec commentary in `spec/flag_handling_spec.cr`.
5. Port upstream flag parser tests:
   - `parse_flag`
   - `parse_flags`

### Done when

- invalid/duplicate flag cases behave like Rust
- stale flag-handling TODOs are gone

## 6. Structured Error Parity Is Missing

Current failures raise a simple `ParseError` in [src/regex-syntax.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex-syntax.cr) with plain strings such as:

- `unsupported group syntax`
- `unclosed group`
- `invalid escape sequence`
- `duplicate capture name`

Upstream Rust has structured error kinds, spans, and in some cases auxiliary spans.

This affects:

- parser parity
- test portability
- diagnostics quality
- future feature work

### Completion work

1. Port a structured error representation modeled on upstream `ast::ErrorKind` and HIR error kinds.
2. Preserve main span and auxiliary span data where upstream does.
3. Add an error formatter layer comparable to Rust’s `error.rs`.
4. Update specs to assert error kinds/spans where feasible, not just message substrings.

### Done when

- parser and translator errors carry structured machine-checkable information
- upstream error-focused tests can be ported directly instead of reduced to string matching

## 7. HIR Interval Algebra Still Needs a Real Upstream Port

Class operations are improved, but they still live as custom helpers inside [src/regex/syntax/translate.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/src/regex/syntax/translate.cr) rather than a dedicated upstream-style interval module.

The inventories still show the entire `hir/interval.rs` surface as missing, and that is accurate.

### Completion work

1. Port `hir/interval.rs` into a dedicated Crystal module.
2. Move interval canonicalization, union, intersection, difference, symmetric difference, negation, iteration, and simple folding there.
3. Replace translator-local interval helpers with the ported module.
4. Port the `hir/mod.rs` interval and class canonicalization tests.

### Done when

- interval algebra is no longer embedded ad hoc in `translate.cr`
- the `hir/interval.rs` inventory rows are substantially complete

## 8. HIR Literal Extraction/Optimization Is Missing

The vendored Rust crate has a substantial `hir/literal.rs` surface. There is no Crystal equivalent today.

This means the following upstream capabilities remain absent:

- literal extraction
- literal sequence optimization
- longest common prefix/suffix handling
- finite/infinite exactness tracking
- many literal-analysis tests

### Completion work

1. Port `hir/literal.rs` as a dedicated Crystal module.
2. Wire it into the HIR API only after the interval work is stable.
3. Port the upstream tests listed in `rust_test_parity.tsv` for `src/hir/literal.rs`.

### Done when

- a Crystal `hir/literal` module exists
- literal analysis tests are no longer blanket missing

## 9. HIR Analysis Surface Is Incomplete

The current HIR exposes only a smaller set of properties. The test inventory still shows these upstream translate/HIR analysis areas as missing:

- `captures_len`
- `static_captures_len`
- anchoredness queries
- look-set analysis
- UTF-8 analysis
- literal / alternation-literal analysis

Some local helpers exist, but there is no evidence of full upstream API parity or coverage for this analysis surface.

### Completion work

1. Audit the vendored HIR analysis API in `vendor/regex-syntax/src/hir/mod.rs` and `vendor/regex-syntax/src/hir/translate.rs`.
2. Port analysis properties in dependency order:
   - captures counts
   - anchoredness
   - assertion-only checks
   - UTF-8 analysis
   - look sets
3. Port the matching upstream tests immediately with each property.

### Done when

- HIR analysis tests in `rust_test_parity.tsv` have concrete Crystal coverage
- analysis methods are implemented as API, not just incidental helpers

## 10. AST and HIR Printing Surfaces Are Missing

The vendored crate includes AST and HIR printer modules and corresponding tests. Crystal currently has no ported print modules.

### Completion work

1. Port `ast/print.rs`.
2. Port `hir/print.rs`.
3. Add round-trip or printer-specific tests from upstream.

### Done when

- printer modules exist
- print-related inventory rows are no longer missing

## 11. UTF-8 Helper Surface Is Missing

There is no Crystal equivalent of upstream `utf8.rs`, and the inventory still marks all of its tests missing.

This matters for:

- scalar range behavior
- reverse UTF-8 generation
- no-surrogate validation

### Completion work

1. Port `utf8.rs`.
2. Port upstream tests:
   - `bmp`
   - `codepoints_no_surrogates`
   - `reverse`
   - `single_codepoint_one_sequence`

### Done when

- UTF-8 helper module exists and tests pass

## 12. Unicode Test Parity Is Still Incomplete

Unicode property/query behavior has improved significantly, but the dedicated upstream Unicode tests are still not ported as a suite. The inventory still lists missing tests such as:

- `simple_fold_a`
- `simple_fold_k`
- `sym_normalize`
- `valid_utf8_symbolic`
- `range_contains`

The recent `case_folding_simple` work should make these tractable now.

### Completion work

1. Port the upstream `src/unicode.rs` tests next.
2. Use the vendored tables already present instead of adding more custom logic.
3. Fold any failures back into `src/regex/syntax/unicode.cr` or `src/regex/syntax/hir.cr`.

### Done when

- the dedicated Unicode helper tests from upstream are in Crystal
- current Unicode behavior is locked by spec rather than by recent memory

## 13. Parser Test Parity Is Still Far Behind Implementation

The parser implementation has moved ahead of the manifests, but the AST parser test matrix is still far smaller than upstream.

Missing upstream parser areas still include:

- holistic parser coverage
- comments / ignore-whitespace edge cases
- decimal parsing
- counted and uncounted repetition edge cases
- set-class edge cases
- unsupported backreference behavior
- unsupported lookaround parser behavior

### Completion work

1. Port `ast/parse.rs` tests in clusters, not individually:
   - escapes
   - flags
   - groups/captures
   - repetition
   - class sets
   - comments/whitespace
   - regressions/fuzz regressions
2. Keep parser-only specs separate from public AST->HIR specs when possible.

### Done when

- `parser_spec.cr` covers the same major parser matrix as upstream
- most parser rows in `rust_test_parity.tsv` have moved out of `missing`

## 14. Translator Test Parity Is Still Far Behind Implementation

The translator has gained real parity work, but the inventory still shows most `hir/translate.rs` tests missing. That is still directionally true.

The remaining missing translator coverage includes:

- full assertion matrix
- dot behavior matrix
- class ASCII/Perl/unicode disabled-feature cases
- nested bracketed operations
- smart concat / smart alternation / smart repetition
- analysis tests
- regression/fuzz tests from upstream

### Completion work

1. Port upstream translator tests in file order from `vendor/regex-syntax/src/hir/translate.rs`.
2. Do not add broad Crystal-only specs when an upstream test already exists.
3. For any failing upstream port:
   - fix implementation
   - add exact parity assertion
   - update inventory row immediately

### Done when

- translator parity is driven by upstream test ports, not ad hoc local specs

## 15. Documentation And Repo Hygiene Need Cleanup

Verified repo issues:

- [spec/flag_handling_spec.cr](/Volumes/extreme_ssd/repos/github.com/dsisnero/regex-syntax/spec/flag_handling_spec.cr) still contains a stale TODO about character class translation
- the repo contains AppleDouble artifact files like `src/._regex-syntax.cr`, `src/regex/syntax/._ast.cr`, and many `scripts/._*` files

These do not block functionality, but they are real maintenance noise.

### Completion work

1. Remove stale comments/TODOs that are already false.
2. Remove AppleDouble artifact files from tracked source directories if they are versioned.
3. Add ignore rules or cleanup guidance so they do not reappear.
4. Update docs if the completion plan changes architectural claims.

### Done when

- no false TODOs remain
- no AppleDouble artifacts remain in tracked source paths

## Execution Order

Use this order to minimize churn and maximize parity gain per slice:

1. Repair parity inventories and mark current implemented work accurately.
2. Port structured error kinds/spans enough to support direct upstream parser/translator test ports.
3. Finish parser escape/flag/backreference parity.
4. Port `hir/interval.rs` and move current interval logic onto it.
5. Port upstream parser tests.
6. Port upstream translator tests as the primary driver for remaining parser/HIR fixes.
7. Port `unicode.rs` and `utf8.rs` helper tests.
8. Port `hir/literal.rs`.
9. Port AST/HIR print modules.
10. Decide and finish AST API parity scope.
11. Clean docs, manifests, and repo artifacts.

## Rules For Each Slice

- Use vendored Rust behavior and tests as the contract.
- Do not add Crystal-only semantics just to make local tests green.
- Prefer porting the upstream test before changing the Crystal code.
- Update the TSV inventories as part of the same slice, not later.
- End each slice with:
  - `make format`
  - `make lint`
  - `make test`

## Completion Criteria

This repo is complete when all of the following are true:

- parity inventories are accurate and current
- missing upstream modules are either ported or explicitly marked `not_applicable`
- parser and translator behavior is driven primarily by ported upstream tests
- structured parser/HIR errors exist where upstream uses them
- no duplicate/dead parser paths remain
- no stale docs/TODOs or AppleDouble artifacts remain
- `make format`, `make lint`, and `make test` pass after each parity slice
