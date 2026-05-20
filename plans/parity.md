# Regex Syntax Parity Checklist

This is the live high-level checklist for finishing Rust `regex-syntax` parity in Crystal.

Rules for this file:

- `[x]` means the feature area is complete enough that it should no longer drive day-to-day parity work.
- `[]` means there is still verified remaining work in that feature area.
- This file tracks closure-sized feature buckets, not individual upstream test rows or one-off fixes.
- Detailed evidence lives in `vendor/regex-syntax/` and the inventories under `plans/inventory/`.

## Completed Foundation

- [x] Canonical architecture is in place.
  Crystal now runs a single staged `source -> AST -> HIR` pipeline, duplicate parser paths are gone, and public parsing uses the same canonical AST-to-HIR flow.

- [x] Rust feature scope is established and enforced.
  Rust feature surfaces are treated as always-on parity targets in Crystal unless the upstream behavior only exists as a Cargo compile-time feature-absent branch or depends on Rust-specific layout/runtime behavior that Crystal cannot expose in the same form.

- [x] Core parse/translate surface is broadly ported.
  This includes captures, flags, class-set operators, octal mode, special word boundaries, verbose mode, repetition forms, Unicode/property classes, UTF-8 gating, class algebra, smart HIR construction, interval algebra, and capture metadata.

- [x] Dedicated module structure exists for the major upstream subsystems.
  Crystal now has dedicated modules for UTF-8 handling, interval sets, AST/HIR printers, AST/HIR visitors, structured errors, and HIR literal extraction/optimization instead of burying those behaviors in ad hoc helpers.

- [x] Inventory discipline is in place.
  The source, test, and port inventories are reconciled, no longer contain baseline `missing` noise, and are suitable as evidence-backed parity manifests instead of aspirational lists.

## Remaining Feature Buckets

### Parser and AST Closure

- [x] Finish the remaining vendored `src/ast/parse.rs` parity as one closure pass.
  The remaining real parser behavior gaps in repetitions, capture-name errors, verbose counted repetitions, and flag/repetition interaction are now closed. The parser rows still marked `partial` in the inventories are there because of intentional AST-shape coalescing, simplified Position/Span modeling, or internal-helper surfaces that Crystal does not expose separately, not because of open parser semantics.

- [x] The parser foundation underneath that closure pass is already in place.
  The public parser/builders, direct AST parser/builders, `parse_with_comments`, scoped/global flag parsing, capture handling, octal support, special boundaries, and structured parser errors are all already present and exercised.

- [x] AST API shape differences are already reconciled.
  Remaining AST source rows are documented as explicit Crystal model differences where applicable instead of being treated as accidental drift.

### Translator and HIR Semantic Closure

- [] Finish the remaining vendored `src/hir/translate.rs` and `src/hir/mod.rs` parity as one combined semantics pass.
  This bucket includes the remaining translator matrix, remaining HIR analysis/property rows, the last look/anchor/literal/property edge cases, and any remaining behavior where the inventories still say `partial` because the long-tail upstream matrix is not fully locked down yet.

- [x] The heavy semantic substrate is already in place.
  Unicode/property translation, byte-vs-Unicode behavior, UTF-8 gating, class flattening, group-local flag scoping, swap-greed behavior, smart concat/alternation/repetition, interval algebra, literal extraction/optimization, and the public HIR property surface all already exist. The vendored literal case-fold and scoped-flag matrices are now substantially covered too, including byte-mode toggles, hex/raw byte literals, punctuation preservation, and structured InvalidUtf8 translator spans.

- [x] Core HIR helper/API reconciliation is already done.
  The public HIR wrapper, `LookSet`, class helpers, constructor helpers, properties wrapper, and the broad AST/HIR API surface have already been brought close to Rust and documented in the inventories.

### Error and Diagnostics Closure

- [x] Finish structured error parity end-to-end.
  Parser-side kind/span coverage is dense, translator-originated structured diagnostics now include exact formatter assertions for InvalidUtf8 and InvalidLineTerminator, and the remaining source-level difference in this area is the intentional Crystal AST/HIR subclass split instead of a single Rust enum wrapper.

- [x] The structured error model and formatter foundation already exist.
  Crystal now has dedicated AST and HIR structured error types, formatter output comparable to upstream for the currently covered cases, duplicate-span handling, multiline span rendering, and real parser-side kind/span assertions for many vendored cases.

### Print, Visitor, and Module Round-Trip Closure

- [x] Finish the remaining round-trip and helper parity for dedicated modules as one closure pass.
  Dedicated AST/HIR printer coverage now closes the vendored print matrices, UTF-8 helper coverage closes the vendored utf8 tests, and the remaining source-level partial rows in this area are documented intentional API/model differences such as Crystal trait/enum shaping rather than missing behavior.

- [x] Most of this surface is already ported.
  Dedicated AST/HIR printers, AST/HIR visitors, interval sets, UTF-8 helpers, and the HIR literal subsystem are already present with broad upstream-backed coverage.

### Final Reconciliation and Done Pass

- [] Do one final parity closeout pass across all manifests and broad buckets.
  The goal of this bucket is to eliminate the remaining high-level `[]` items by either implementing the remaining semantics, explicitly documenting intentional shape differences, or proving that the remaining partial rows are only partial because of non-blocking model-shape differences rather than missing behavior.

- [x] The project is already in a strong closeout state.
  Quality gates pass, inventories are synced, the parity scope is documented, and the remaining work is concentrated in a few large semantic closure passes instead of scattered foundational debt.

## Project-Level Done Criteria

- [x] Every former `missing` row is now either implemented, explicitly marked `not_applicable`, or documented as an intentional API difference.

- [] All remaining open feature buckets above are closed.
  This means no broad parity workstream is still being driven by open semantic drift; only documented intentional shape differences may remain.

- [x] Verified gates continue to pass after each slice:
  `make format`, `make lint`, `make test`.

- [x] New parity work remains tied to vendored Rust code and vendored Rust tests instead of local invention.
