# Coding Guidelines

These guidelines are specific to this port. They are not generic Crystal style notes.

## First rule: preserve vendored behavior

Rust `vendor/regex-syntax` behavior is the semantic contract.

That means:

- port the behavior before “improving” the API
- port the tests, not just the happy path
- keep internal structure when it matters for correctness or performance
- document intentional shape differences instead of silently diverging

## Keep the staged design intact

Do not collapse everything into one parser or one helper because it looks smaller.

Keep responsibilities separated:

- `AstParser`
  - source-faithful syntax parsing
- `Translator`
  - AST -> HIR semantics
- `Hir`
  - normalized semantic representation and analysis
- dedicated modules
  - `error`, `literal`, `utf8`, `hir_interval`, `*_print`, `*_visitor`

If logic belongs in translation or HIR normalization, do not push it back into the AST parser.

## Crystal model differences should be explicit

Some upstream Rust shapes are intentionally modeled differently in Crystal:

- Rust enums often become concrete Crystal classes plus nested enums
- Rust `Option<T>` usually becomes `T?`
- Rust builder methods map to Crystal builder-style setters returning `self`
- parser/translator internal transport errors use `ParseError`, then surface as `AST::Error` or `Hir::Error`

Those differences are acceptable only when:

- semantics still match upstream
- specs prove the behavior
- inventories document the difference

## What to optimize for

Priorities in order:

1. semantic parity
2. structured error parity
3. interval/class correctness
4. performance on hot paths
5. API cleanliness

Do not trade away 1–3 for 5.

## Hot paths that should not be casually simplified

Be careful in:

- [`src/regex-syntax.cr`](../src/regex-syntax.cr)
  - AST parsing, escapes, flags, classes, repetition parsing
- [`src/regex/syntax/translate.cr`](../src/regex/syntax/translate.cr)
  - class lowering, mode switches, UTF-8 gating
- [`src/regex/syntax/hir.cr`](../src/regex/syntax/hir.cr)
  - interval ops, class canonicalization, case folding, property analysis
- [`src/regex/syntax/literal.cr`](../src/regex/syntax/literal.cr)
  - literal extraction, sequence union/cross, optimization heuristics
- [`src/regex/syntax/utf8.cr`](../src/regex/syntax/utf8.cr)
  - scalar splitting and UTF-8 sequence decomposition

If you refactor these files, keep the spec matrix nearby and re-run the full gates.

## Public API naming

Use idiomatic Crystal names when the meaning remains obvious:

- `prefix?` / `suffix?` instead of Rust `is_prefix` / `is_suffix`
- `word_byte?`, `word_character?`, `meta_character?`
- `valid?`, `negated?`, `capturing?`

But do not rename concepts so aggressively that the vendored source stops being easy to map mentally.

## Error handling

Use the existing structured error model:

- `Regex::Syntax::ParseError`
  - internal propagation
- `Regex::Syntax::AST::Error`
  - parser surface
- `Regex::Syntax::Hir::Error`
  - translator surface

Do not introduce ad hoc string-only exceptions for new parser or translator behavior.

If a new parity case needs a distinct structured kind, add it to the relevant enum and cover it in specs.

## Comments

Prefer comments that explain parity-sensitive behavior or architectural intent:

- why a parser backtracks here
- why a negated class stays structurally negated
- why UTF-8 gating must happen before lowering

Avoid comments that merely restate Crystal syntax.

## Spec-driven changes

For parity work:

1. add or tighten the spec first
2. make it fail for the right reason
3. implement the change
4. update parity manifests if coverage status changed

Do not “clean up” manifests without checking the real spec coverage and real vendored behavior.

## File organization expectations

Use existing module boundaries.

Examples:

- new AST shape helpers belong in [`src/regex/syntax/ast.cr`](../src/regex/syntax/ast.cr)
- new HIR property helpers belong in [`src/regex/syntax/hir.cr`](../src/regex/syntax/hir.cr)
- printer behavior belongs in [`src/regex/syntax/ast_print.cr`](../src/regex/syntax/ast_print.cr) or [`src/regex/syntax/hir_print.cr`](../src/regex/syntax/hir_print.cr)
- visitor behavior belongs in [`src/regex/syntax/ast_visitor.cr`](../src/regex/syntax/ast_visitor.cr) or [`src/regex/syntax/hir_visitor.cr`](../src/regex/syntax/hir_visitor.cr)

Do not hide dedicated subsystem behavior in `src/regex-syntax.cr` if a dedicated file already exists for it.
