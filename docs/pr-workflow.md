# PR Workflow

This repo’s pull-request workflow is shaped by parity work, not just generic Crystal library maintenance.

## Before you open a PR

Make sure the change is grounded in one of these:

- vendored Rust source behavior
- vendored Rust test behavior
- Crystal-facing documentation or manifest reconciliation that reflects the current codebase

If a change alters parser, translator, Unicode, HIR, literal extraction, printer, visitor, or error behavior, it should usually point back to a specific vendored source/test area.

## Required gates

Before opening or updating a PR, run:

```bash
make format
make lint
make test
```

Do not rely on CI to discover local parity or formatting regressions that are already reproducible here.

## Commit grouping

Group commits by coherent feature/documentation slice.

Good commit groups:

- `feat: port Rust UTF-8 translator error split`
- `test: expand vendored hir literal parity coverage`
- `docs: rewrite architecture and testing docs for current staged pipeline`
- `chore: reconcile final parity manifests`

Bad commit groups:

- one commit per tiny helper change when they all belong to the same parity bucket
- mixing parser behavior, Unicode tables, and unrelated docs in a single “misc fixes” commit

## Commit message format

Use conventional commits:

- `feat:`
- `fix:`
- `docs:`
- `style:`
- `refactor:`
- `test:`
- `chore:`

Prefer messages that name the actual subsystem:

- `feat: close translator and HIR semantic parity bucket`
- `test: port vendored ast printer matrix`
- `docs: update README and internal docs for current parser pipeline`

## PR description contents

A good PR description here should include:

- what vendored Rust behavior or docs area it is based on
- which Crystal files changed
- which spec files were added or tightened
- whether parity manifests were updated
- the exact gates that were run

For example:

```text
Summary
- port vendored parser flag/Unicode EOF behavior
- tighten AST structured error spans
- reconcile parser rows in rust_test_parity.tsv

Files
- src/regex-syntax.cr
- src/regex/syntax/error.cr
- spec/parser_spec.cr
- plans/inventory/rust_test_parity.tsv

Verification
- make format
- make lint
- make test
```

## When docs must change

Update docs in the same PR when the change affects:

- public API usage
- supported parser/builder options
- architecture claims
- test organization
- parity workflow

This is especially important in this repo because stale docs have historically drifted away from the real staged architecture.

## Manifest expectations

If the PR changes parity status, update the relevant files:

- [`plans/parity.md`](../plans/parity.md)
- [`plans/inventory/rust_test_parity.tsv`](../plans/inventory/rust_test_parity.tsv)
- [`plans/inventory/rust_source_parity.tsv`](../plans/inventory/rust_source_parity.tsv)
- [`plans/inventory/rust_port_inventory.tsv`](../plans/inventory/rust_port_inventory.tsv)

Do not mark rows `done` unless the Crystal spec coverage is actually present.
Do not leave rows stale if the code/specs already changed.

## Review checklist

Reviewers should check:

- vendored behavior is actually the source of truth for the change
- code stays within the staged AST -> HIR architecture
- new error behavior uses structured AST/HIR error surfaces
- tests are added in the right subsystem spec file
- manifests were updated if parity status changed
- docs were updated if public or architectural claims changed

## Branch and local-environment notes

If you are working on a removable exFAT volume:

- avoid committing macOS artifact files like `._*` or `.DS_Store`
- confirm the worktree is clean before pushing
- if local Git needs help writing `.git/index.lock`, resolve that locally before assuming the repo state is broken
