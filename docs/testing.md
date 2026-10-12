# Testing

Testing in this repo is organized around vendored Rust behavior, not around generic unit-test categories.

## Primary command

Run the full suite with:

```bash
make test
```

That runs:

```bash
crystal spec
```

Before committing, also run:

```bash
make format
make lint
make test
```

## Spec layout

The current spec suite is intentionally split by subsystem.

### Public parser / HIR behavior

- [`spec/regex-syntax_spec.cr`](../spec/regex-syntax_spec.cr)
  - broad public API, parser, translator, HIR analysis, look sets, class helpers, constructors, Unicode property, and parity matrix coverage
- [`spec/parser_builder_spec.cr`](../spec/parser_builder_spec.cr)
  - public `ParserBuilder` surface
- [`spec/translator_spec.cr`](../spec/translator_spec.cr)
  - focused translator regressions and byte/Unicode cases
- [`spec/translator_builder_spec.cr`](../spec/translator_builder_spec.cr)
  - translator option surface

### Direct AST parser behavior

- [`spec/parser_spec.cr`](../spec/parser_spec.cr)
  - vendored `src/ast/parse.rs` behavior through the Crystal `AstParser` surface
- [`spec/flag_handling_spec.cr`](../spec/flag_handling_spec.cr)
  - detailed scoped/global flag parsing and error spans
- [`spec/ast_parser_builder_spec.cr`](../spec/ast_parser_builder_spec.cr)
  - direct `AstParserBuilder` surface

### AST / HIR API shape

- [`spec/ast_api_spec.cr`](../spec/ast_api_spec.cr)
- [`spec/hir_literal_api_spec.cr`](../spec/hir_literal_api_spec.cr)

These lock down Crystal-facing helpers that intentionally differ in shape from Rust while still preserving behavior.

### Printers and visitors

- [`spec/ast_print_spec.cr`](../spec/ast_print_spec.cr)
- [`spec/hir_print_spec.cr`](../spec/hir_print_spec.cr)
- [`spec/ast_visitor_spec.cr`](../spec/ast_visitor_spec.cr)
- [`spec/hir_visitor_spec.cr`](../spec/hir_visitor_spec.cr)

These matter because round-tripping and traversal order are explicit parity surfaces.

### Dedicated subsystems

- [`spec/hir_interval_spec.cr`](../spec/hir_interval_spec.cr)
  - interval-set operations
- [`spec/hir_literal_spec.cr`](../spec/hir_literal_spec.cr)
  - vendored `src/hir/literal.rs` matrix
- [`spec/unicode_spec.cr`](../spec/unicode_spec.cr)
  - Unicode helper and normalization surfaces
- [`spec/utf8_spec.cr`](../spec/utf8_spec.cr)
  - vendored UTF-8 decomposition behavior
- [`spec/error_spec.cr`](../spec/error_spec.cr)
  - structured parser/HIR formatter output
- [`spec/lib_spec.cr`](../spec/lib_spec.cr)
  - top-level helper functions from the `src/lib.rs` parity surface

### Focused parity slices

- [`spec/hir_semantic_parity_spec.cr`](../spec/hir_semantic_parity_spec.cr)
  - concentrated vendored HIR translator and analysis matrices
- [`spec/perl_class_unicode_spec.cr`](../spec/perl_class_unicode_spec.cr)
  - byte-vs-Unicode Perl class behavior

## How parity tests are written

Tests should be sourced from vendored Rust whenever possible.

Typical mapping:

- vendored parser test in `vendor/regex-syntax/src/ast/parse.rs`
  - port to `spec/parser_spec.cr` or `spec/flag_handling_spec.cr`
- vendored translator/analysis test in `vendor/regex-syntax/src/hir/translate.rs`
  - port to `spec/regex-syntax_spec.cr`, `spec/translator_spec.cr`, or `spec/hir_semantic_parity_spec.cr`
- vendored literal test in `vendor/regex-syntax/src/hir/literal.rs`
  - port to `spec/hir_literal_spec.cr`
- vendored helper test in `vendor/regex-syntax/src/unicode.rs` or `src/utf8.rs`
  - port to `spec/unicode_spec.cr` or `spec/utf8_spec.cr`

## What counts as “done”

A parity slice is not done just because the code works on a hand-written example.

It is done when:

1. the relevant vendored behavior is implemented
2. the corresponding Crystal spec exists
3. the parity manifests are reconciled
4. `make format`, `make lint`, and `make test` pass

## Structured error assertions

Use the helpers in [`spec/spec_helper.cr`](../spec/spec_helper.cr) when checking parser and translator diagnostics.

Important distinction:

- parser errors should assert structured `AST::Error` kind/span behavior where relevant
- translator errors should assert structured `Hir::Error` kind/span behavior where relevant

Do not reduce a structured parity case to “message contains text” if the current code exposes a stronger surface.

## Partial rows in parity manifests

Not every `partial` row means missing semantics.

At the current project state, remaining `partial` rows in the inventories are largely:

- intentional AST model-shape differences
- internal Rust helper functions that are not exposed as separate Crystal helpers
- a small number of visitor/interval trait-shape differences caused by Rust
  traits mapping to Crystal mixins or typed generics

That distinction should be preserved when updating manifests.

## Executable Rust output comparison

Run `python3 scripts/check_hir_output_parity.py --rust-tests` to run the 147
vendored default-feature unit tests, compile the pinned Rust
crate and Crystal oracle, extract every literal `t`/`t_bytes` call from
`src/hir/translate.rs`, and compare 316 exact HIR display outputs. The script
uses `rustc` directly, requires no registry downloads, and writes all build
artifacts under `temp/hir-parity/`. Its source revision check prevents an
unreviewed vendor refresh from silently changing expected outputs.

`spec/fixtures/hir_translate.tsv` records the Rust expectations as hexadecimal
UTF-8 to preserve embedded whitespace and control characters. Regenerate only
with `python3 scripts/check_hir_output_parity.py --write-fixture`; never derive
expected values from Crystal. `make test` exercises every fixture. Independent
structural expectations in `spec/hir_alternation_spec.cr` additionally verify
the complete eight-case Rust `smart_alternation` matrix and byte/Unicode edges.

Run `python3 scripts/check_hir_output_parity.py --properties` to compare 457
literal translator and analysis-helper inputs plus eight length-boundary cases
across all twelve HIR property fields. `spec/fixtures/hir_properties.tsv` contains the Rust snapshots; regenerate
with `--properties --write-fixture`. The property specs run with `make test`.

This is evidence for the extracted cases, not a claim that dynamic fixtures,
all direct-constructor property assertions, or all support-module assertions were audited.
The remaining audit is tracked in `plans/parity.md`.

Inventory statuses are `ported`, `partial`, `missing`, `in_progress`, `skipped`,
and `intentional_divergence`. Earlier `done`/`not_applicable` labels have been
migrated; mappings and non-port rationales remain curated.

HIR and Properties length results use `UInt64?` to match the pinned Rust build’s
64-bit `usize`: minimum lengths saturate, and maximum lengths become `nil` on
overflow. Class-local length helpers remain small integer byte counts.

## HIR construction and complete translator runtime audit

Run `python3 scripts/check_hir_construction_parity.py` to compile a temporary
instrumented copy of the pinned Rust source and execute all 47 default-feature
translator tests, preserving their original assertions. A separate Rust
characterization test supplies constructor and property-union compositions.
No vendored files are modified and no registry downloads are needed.

The committed fixtures contain 565 translator calls, 444 constructor
compositions, and 144 standalone property unions. Crystal compares exact node kinds and nesting, literal bytes, effective
class intervals, capture indices/names, repetition bounds/greediness, display,
and all twelve property fields. Error cases compare kind and complete primary
span positions. The three manually constructed AST regressions are reconstructed
as AST nodes; the fuzz-match case retains its verbose parser configuration.

`plans/inventory/rust_hir_assertion_audit.tsv` maps all 545 upstream assertion
locations: 537 execute under the default Unicode features and eight belong to
six feature-disabled tests. It also maps the two no-panic fuzz calls to complete
runtime snapshots. Unaccounted assertions fail the audit instead of becoming
implicit skips. Disabled Unicode build modes remain excluded from this phase;
Crystal supplies its Unicode tables unconditionally.

Regenerate expectations only with
`python3 scripts/check_hir_construction_parity.py --write-fixture`; Rust tests
must pass before expectations are written. Artifacts and logs stay under
`temp/hir-construction/`. Both new fixture specs run with `make test` without
requiring Rust. The constructor recipes are characterization cases, not a claim
that all arbitrary HIR trees have been enumerated.

Use `Hir::Hir.character_class` for Rust-equivalent smart class construction from
concrete byte/Unicode classes or the `Hir::Class` wrapper. `Hir::Hir.new(Node)`
remains a raw wrapper. Smart construction lowers singleton classes to literals
and empty classes to the byte fail node; repetition simplification uses the
child's maximum length, including captured empty expressions.

### Unicode tables and character-class assertion audit

```bash
python3 scripts/check_class_unicode_parity.py
python3 scripts/sync_unicode_ranges.py
```

The class/Unicode oracle copies the pinned Rust source under `temp/`, preserves
and executes all enabled class and Unicode test assertions, and captures raw
constructor inputs plus complete operation results. Additional native cases
exercise scalar boundaries, byte conversion, complement folding, and internal
folded-state sequences. The audit ledger records every native assertion and the
three unavailable feature-mode contracts individually.

The fixture contains every Unicode 16.0.0 range-table entry, property alias,
property-value alias, and simple-case-fold mapping. Every alias query is checked
through the direct Unicode helper and through parsing, comparing full intervals
or exact error kinds and spans. Specs also verify table key inventories and
walk every valid scalar through the stateful simple-case folder.

To intentionally regenerate expectations from a passing native run:

```bash
python3 scripts/check_class_unicode_parity.py --write-fixture --rust-only
python3 scripts/sync_unicode_ranges.py --write
python3 scripts/check_class_unicode_parity.py
```

The sync script regenerates Crystal range constants from the Rust fixture;
it never reads Crystal results to establish expected data. Changes to the
pinned upstream revision require a separately reviewed inventory refresh.

### Literal extraction and UTF-8 assertion audit

```bash
python3 scripts/check_literal_utf8_parity.py
```

The oracle runs all 20 original literal/UTF-8 Rust tests and three native
characterization tests in a temporary source copy. It checks the assertion
ledger, compares freshly captured expectations with the committed fixture,
then runs the focused Crystal specs. The 7,524 fixture cases preserve literal
bytes, order, exactness, sequence metadata, consumed operands, extraction
configuration and limits, all byte ranks, and ordered UTF-8 range/reset output.
Both languages also verify exact encodings across every valid Unicode scalar
and retain the upstream surrogate-range loop.

To regenerate expectations after a reviewed upstream change:

```bash
python3 scripts/check_literal_utf8_parity.py --write-fixture --rust-only
python3 scripts/check_literal_utf8_parity.py
```

Expectations are written only after the native tests pass, never from Crystal
results. Generated sources and logs stay under `temp/literal-utf8-parity/`.

### Diagnostics, printers, and visitor contracts

```bash
python3 scripts/check_diagnostic_parity.py
```

This oracle runs the 21 original Rust error/printer tests with their assertions
intact, plus native characterization tests for diagnostics, class ranges,
Unicode whitespace, all error-kind messages, raw byte literals, writer failures,
and visitor contracts. It replays parser/translator test inputs through the
pinned Rust parsers to obtain formatted diagnostics, including primary and
auxiliary positions. Explicit formatter cases verify that span line/column
metadata controls caret placement, independently of byte offsets.

Visitor modules contain no upstream unit tests. The native characterization
records every hook in expression and class-set traversals and injects an error
at every fallible hook occurrence, including `finish`. Rust uses `Result` and
Crystal uses exceptions; both must stop at the same event without later hooks.
Writers fail at each byte boundary and compare both the error and emitted bytes.
Printing and traversal also run on directly constructed 50,000-level trees.
Crystal printers use the iterative visitor path to preserve constant stack use.

All expectations come from Rust. To intentionally regenerate them:

```bash
python3 scripts/check_diagnostic_parity.py --write-fixture --rust-only
python3 scripts/check_diagnostic_parity.py
```

Temporary sources and logs stay under `temp/diagnostic-parity/`. The assertion
ledger maps every assertion in the original error/printer unit tests; visitor
characterizations are labeled separately. AST error enums retain kind identity;
`AST::Error#nest_limit` and `#kind_message` preserve the nesting-limit payload
and its formatted text.
