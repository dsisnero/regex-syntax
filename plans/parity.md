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

- `[x]` means the whole feature bucket is closed enough that it should no
  longer drive active parity work.
- `[]` means there is still verified remaining work in that bucket.
- Buckets here should stay branch-sized and user-visible. Detailed row-by-row
  drift belongs in the inventories.

## Evidence Sources

- Upstream source of truth: `vendor/regex-syntax/`
- Curated working ledger: `plans/inventory/rust_port_inventory.tsv`
- Generated source manifest: `plans/inventory/rust_source_parity.tsv`
- Generated test manifest: `plans/inventory/rust_test_parity.tsv`

## Current State

- `rust_test_parity.tsv`: `139 done`, `14 not_applicable`, `5 partial`
- `rust_source_parity.tsv`: `870 done`, `1 not_applicable`, `7 partial`

Interpretation:

- The remaining test partials are narrow `src/ast/parse.rs` helper-surface rows,
  not broad semantic drift.
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

## Feature Buckets

### Active Work

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
  behavior, compile-time Rust-only `not_applicable` rows, and intentional
  Crystal model differences instead of mixing those states together.

- [x] Broad parity work is fully closed.
  Semantic closure now includes the AST span/position fidelity pass. The
  remaining `partial` rows are helper-surface or API-shape differences, not an
  open implementation bucket.

## What Still Shows As `partial`

These do not justify separate helper-sized buckets by themselves:

- Narrow parser-helper rows in `rust_test_parity.tsv`
  `parse_decimal`, `parse_flag`, `parse_primitive_non_escape`,
  `parse_set_class`, and `parse_set_class_open` remain partial because Crystal
  does not expose those helpers as separate entry points even though the
  corresponding parser behavior is covered through the real public or AST parser
  surfaces.

- Source-level API-shape rows in `rust_source_parity.tsv`
  Most remaining partial rows are deliberate language-model differences:
  Crystal uses concrete node classes instead of Rust enums, direct initializers
  instead of free constructor functions, wrapper objects instead of sum types,
  and idiomatic predicates or builders instead of one-for-one method names.

## If Parity Work Resumes

Use the inventories to choose scope, then reopen only one broad bucket at a
time:

1. Source/API shape reconciliation
   Only if we want to mirror more Rust surface area one-for-one instead of
   keeping documented Crystal-native wrappers.
2. New upstream refresh
   If `vendor/regex-syntax` moves, regenerate manifests intentionally, update
   the port inventory, and reopen the smallest closure-sized bucket affected by
   that upstream delta.
3. Adversarial verification pass
   Use the existing inventories plus quality gates as the base for an
   independent signoff pass after any future upstream refresh.

## Project-Level Done Criteria

- [x] No generated parity manifest is still carrying baseline `missing` drift.
- [x] Broad semantic parity and AST fidelity are both closed.
- [x] Remaining `partial` rows are documented and evidence-backed.
- [x] Quality gates continue to pass:
  `make format`, `make lint`, `make test`
- [x] New parity changes stay anchored to vendored Rust code and vendored Rust
  tests instead of local invention.
