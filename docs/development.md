# Development

This repo is maintained as a source-faithful port of vendored Rust `regex-syntax`, with Crystal-facing APIs layered on top of the same semantic pipeline.

## Setup

Prerequisites:

- Crystal `>= 1.19.1`
- `shards`
- Git

Install dependencies:

```bash
make install
```

Update dependencies:

```bash
make update
```

## Verified commands

These are the repo-supported commands:

```bash
make install
make update
make format
make lint
make test
make clean
```

What they actually do today:

- `make format`
  - `crystal tool format --check src spec`
- `make lint`
  - `./bin/ameba src spec`
- `make test`
  - `crystal spec`
- `make clean`
  - removes files under `./temp/*`

## Development workflow

The expected loop for code changes is:

1. Find the vendored Rust behavior in [`vendor/regex-syntax/`](../vendor/regex-syntax/)
2. Add or tighten the Crystal spec first
3. Implement or adjust the Crystal code
4. Update parity manifests if the surface moved
5. Run `make format`, `make lint`, and `make test`

This repo is maintained with red-green parity work, not feature guessing.

## Which parser surface to use

Use the correct parser entry point for the job:

- `Regex::Syntax.parse`
  - default public parse to `Hir::Hir`
- `Regex::Syntax::Parser`
  - explicit HIR parsing with options like `utf8`, `line_terminator`, `unicode`, `octal`
- `Regex::Syntax::AstParser`
  - direct AST parsing when you need source-faithful syntax shape or parser error parity
- `Regex::Syntax::AstParser#parse_with_comments`
  - verbose-mode comment capture

Do not introduce alternate production parse paths. The staged AST -> HIR pipeline is the canonical path.

## Current important source files

Core implementation:

- [`src/regex-syntax.cr`](../src/regex-syntax.cr)
- [`src/regex/syntax/parser.cr`](../src/regex/syntax/parser.cr)
- [`src/regex/syntax/ast.cr`](../src/regex/syntax/ast.cr)
- [`src/regex/syntax/hir.cr`](../src/regex/syntax/hir.cr)
- [`src/regex/syntax/translate.cr`](../src/regex/syntax/translate.cr)
- [`src/regex/syntax/unicode.cr`](../src/regex/syntax/unicode.cr)
- [`src/regex/syntax/error.cr`](../src/regex/syntax/error.cr)

Dedicated subsystems:

- [`src/regex/syntax/literal.cr`](../src/regex/syntax/literal.cr)
- [`src/regex/syntax/hir_interval.cr`](../src/regex/syntax/hir_interval.cr)
- [`src/regex/syntax/utf8.cr`](../src/regex/syntax/utf8.cr)
- [`src/regex/syntax/ast_print.cr`](../src/regex/syntax/ast_print.cr)
- [`src/regex/syntax/hir_print.cr`](../src/regex/syntax/hir_print.cr)
- [`src/regex/syntax/ast_visitor.cr`](../src/regex/syntax/ast_visitor.cr)
- [`src/regex/syntax/hir_visitor.cr`](../src/regex/syntax/hir_visitor.cr)

## Parity workflow

Parity is tracked explicitly:

- [`plans/parity.md`](../plans/parity.md)
- [`plans/inventory/rust_test_parity.tsv`](../plans/inventory/rust_test_parity.tsv)
- [`plans/inventory/rust_source_parity.tsv`](../plans/inventory/rust_source_parity.tsv)
- [`plans/inventory/rust_port_inventory.tsv`](../plans/inventory/rust_port_inventory.tsv)

Use them correctly:

- `rust_test_parity.tsv`
  - maps vendored Rust test names to Crystal spec coverage
- `rust_source_parity.tsv`
  - maps vendored source API/items to Crystal equivalents or intentional differences
- `rust_port_inventory.tsv`
  - consolidated source/test inventory used for reconciliation
- `parity.md`
  - tracks broad feature buckets, not tactical one-off tasks

When you finish a meaningful feature bucket, reconcile the manifests. Do not leave stale `partial` or `missing` rows after the code and specs already moved.

## Temporary files and generated output

Use `./temp/` for generated work files and scratch artifacts.

Examples:

- generated conversion outputs
- one-off parity scratch files
- local diff captures

Do not leave generated files untracked at repo root.

## How to use vendored Rust code

Vendored Rust is the contract, not just inspiration.

Typical workflow:

1. Identify the Rust source file and test:
   - `vendor/regex-syntax/src/ast/parse.rs`
   - `vendor/regex-syntax/src/hir/translate.rs`
   - `vendor/regex-syntax/src/hir/literal.rs`
   - `vendor/regex-syntax/src/unicode.rs`
2. Port the relevant behavior into Crystal
3. Port the corresponding test intent into `spec/`
4. If Crystal keeps a different public shape, document that in the inventories

Good reasons for a documented difference:

- Crystal object model versus Rust enum layout
- internal Rust helper function not exposed as a public Crystal helper
- compile-time feature-disabled Cargo branch that does not exist in always-on Crystal surface

Bad reasons:

- “simpler in Crystal”
- “too much work”
- “not needed for current caller”

## Commit and branch expectations

Use conventional commit messages:

- `feat:`
- `fix:`
- `docs:`
- `style:`
- `refactor:`
- `test:`
- `chore:`

Group commits by completed feature slice or documentation slice. Do not mix unrelated parity buckets into one commit if they can be separated cleanly.

## ExFAT / removable-drive note

This repo may be developed on a removable exFAT volume. In that environment:

- keep macOS artifact files out of version control
- expect local Git config to use `core.filemode=false` and `core.ignorecase=true`
- if Git cannot create `.git/index.lock`, the operation may need elevated permissions in the local tooling environment
