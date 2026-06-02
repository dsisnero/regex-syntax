# Changelog

All notable changes to this Crystal port are documented here.

## 0.5.0 - 2026-06-01

This release tags the first parity-closed state for the staged Crystal port in
this repository.

### Added and completed

- Completed the public staged parser surface with `Regex::Syntax.parse`,
  `Parser` / `ParserBuilder`, and `AstParser` / `AstParserBuilder`.
- Completed the dedicated support modules that were still ad hoc earlier in the
  port: structured errors, interval sets, UTF-8 helpers, AST/HIR printers,
  AST/HIR visitors, and HIR literal extraction.
- Closed broad semantic parity for parser, translator, Unicode, HIR, and
  diagnostics behavior against vendored Rust `regex-syntax`.
- Closed AST span and position fidelity so byte-offset-sensitive parser cases
  now match vendored behavior across multibyte literals, comments, capture
  names, and class ranges.

### Repository and release metadata

- Updated shard metadata to point at `dsisnero/regex-syntax` instead of the old
  `logos` repository metadata.
- Synced the shard version and `Regex::Syntax::VERSION` constant to `0.5.0`.
- Tightened the public version spec so the release constant is asserted
  directly.
- Refreshed README and internal docs to describe the actual shipped surface and
  current parity state.

### Verification

- `make format`
- `make lint`
- `make test`

## Earlier history

Earlier porting work predates this changelog and remains available through the
Git history and parity manifests under [`plans/`](./plans/).
