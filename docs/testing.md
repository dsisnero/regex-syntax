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
- simplified position/span modeling
- internal Rust helper functions that are not exposed as separate Crystal helpers

That distinction should be preserved when updating manifests.
