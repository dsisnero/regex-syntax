# Architecture

This document describes the current Crystal implementation, not a hypothetical port shape.

## Core pipeline

The canonical runtime path is:

```text
pattern String
  -> Regex::Syntax::AstParser
  -> Regex::Syntax::AST::Ast
  -> Regex::Syntax::Translator
  -> Regex::Syntax::Hir::Node
  -> Regex::Syntax::Hir::Hir
```

The public helper:

```crystal
Regex::Syntax.parse(pattern)
```

is just:

- `Regex::Syntax::Parser.new.parse(pattern)`
- which builds an `AstParser`
- parses to AST
- translates that AST with `Translator`
- wraps the translated node in `Hir::Hir`

There is no second production parser path anymore. The old simplified split is gone.

## Entry points and where they live

### Top-level API

File: [`src/regex-syntax.cr`](../src/regex-syntax.cr)

This file exposes:

- `Regex::Syntax.parse`
- `Regex::Syntax.escape`
- `Regex::Syntax.escape_into`
- `Regex::Syntax.meta_character?`
- `Regex::Syntax.escapeable_character?`
- `Regex::Syntax.word_byte?`
- `Regex::Syntax.word_character?`
- `Regex::Syntax.try_is_word_character`
- `Regex::Syntax::AstParser`

It also requires the dedicated submodules so the shard can be used with a single `require "regex-syntax"`.

### Public parser facade

File: [`src/regex/syntax/parser.cr`](../src/regex/syntax/parser.cr)

This file defines two builder/parser surfaces:

- `AstParserBuilder`
  - `ignore_whitespace`
  - `nest_limit`
  - `octal`
  - `empty_min_range`
  - `build`
- `ParserBuilder`
  - `unicode`
  - `utf8`
  - `case_insensitive`
  - `multi_line`
  - `dot_matches_new_line`
  - `swap_greed`
  - `ignore_whitespace`
  - `crlf`
  - `nest_limit`
  - `octal`
  - `line_terminator`
  - `build`

`Parser#parse` is the canonical staged AST -> HIR path.

## AST layer

File: [`src/regex/syntax/ast.cr`](../src/regex/syntax/ast.cr)

The AST layer is intentionally faithful to source syntax:

- `AST::Literal` preserves literal kind and escape form metadata
  - `Verbatim`
  - `Escaped`
  - `Hex`
  - `Unicode`
  - `Octal`
- `AST::Assertion` preserves the parsed assertion form
  - `^`, `$`, `\A`, `\z`, `\Z`
  - `\b`, `\B`
  - `\b{start}`, `\b{end}`, `\b{start-half}`, `\b{end-half}`
  - `\<`, `\>`
- `AST::Class*` nodes preserve class-set syntax instead of prematurely flattening it
- `AST::WithComments` carries verbose-mode comments captured by `parse_with_comments`

The AST model is object-oriented rather than a single Rust enum. That is a documented model-shape difference, not semantic drift.

## Translator layer

File: [`src/regex/syntax/translate.cr`](../src/regex/syntax/translate.cr)

The translator is where syntax becomes semantics.

It is responsible for:

- Unicode-vs-byte mode decisions
- UTF-8 validity gating
- custom line-terminator handling
- ignore-case folding
- class-set algebra
- smart concat/alternation/repetition normalization
- lowering assertions into HIR look variants
- assigning HIR capture metadata

This separation matters because several Rust behaviors only become meaningful after parsing:

- `\d`, `\w`, `\s` differ by Unicode/byte mode
- `.` differs by `dot_matches_new_line`, `utf8`, and `line_terminator`
- negated byte classes can become `InvalidUtf8`
- bracketed class binary operators need interval algebra during lowering

## HIR layer

File: [`src/regex/syntax/hir.cr`](../src/regex/syntax/hir.cr)

`Hir::Hir` wraps a canonical `Hir::Node`. The node layer is normalized compared to AST:

- smart concat merges adjacent literals and flattens nested concatenations
- smart alternation flattens nested alternations and simplifies empty cases
- smart repetition simplifies zero-count and identity cases
- class intervals are canonicalized

The HIR surface also exposes analysis and property helpers:

- `minimum_len`
- `maximum_len`
- `utf8?`
- `explicit_captures_len`
- `static_explicit_captures_len`
- `look_set_prefix`
- `look_set_suffix`
- `look_set_prefix_any`
- `look_set_suffix_any`
- `literal?`
- `alternation_literal?`
- `all_assertions?`
- `properties`

## Interval algebra

There are two layers here:

- low-level canonical interval logic in [`src/regex/syntax/hir.cr`](../src/regex/syntax/hir.cr) under `IntervalOps`
- public interval-set wrapper in [`src/regex/syntax/hir_interval.cr`](../src/regex/syntax/hir_interval.cr)

Implemented operations include:

- canonicalize
- union
- intersect
- difference
- symmetric difference
- invert
- ASCII case folding
- Unicode simple case folding

Unicode inversion explicitly respects the surrogate gap instead of treating `0xD800..0xDFFF` as scalar values.

## Unicode layer

Files:

- [`src/regex/syntax/unicode.cr`](../src/regex/syntax/unicode.cr)
- [`src/regex/syntax/unicode_tables.cr`](../src/regex/syntax/unicode_tables.cr)
- [`src/regex/syntax/unicode_tables/`](../src/regex/syntax/unicode_tables/)

This layer resolves Rust-style property queries into class intervals.

It currently includes vendored tables for:

- general category
- script
- script extension
- age
- grapheme cluster break
- word break
- sentence break
- Perl word
- property name/value aliases
- simple case folding

This is also where normalized Rust-style query forms such as `gc`, `sc`, `scx`, `age`, `wb`, `gcb`, and `sb` are handled.

## Literal extraction subsystem

Files:

- [`src/regex/syntax/literal.cr`](../src/regex/syntax/literal.cr)
- [`src/regex/syntax/rank.cr`](../src/regex/syntax/rank.cr)

This is a dedicated port of vendored `src/hir/literal.rs`, not an ad hoc helper.

It provides:

- `LiteralExtraction::Literal`
- `LiteralExtraction::Seq`
- `LiteralExtraction::Extractor`
- `ExtractKind`

It supports:

- prefix and suffix extraction
- finite/infinite literal set tracking
- repetition-sensitive extraction
- sequence union/cross operations
- preference-based minimization
- Holmes-style optimization heuristics

## UTF-8 subsystem

File: [`src/regex/syntax/utf8.cr`](../src/regex/syntax/utf8.cr)

This module decomposes Unicode scalar ranges into UTF-8 byte-sequence ranges. It is used to preserve Rust-style byte-level semantics in Unicode-aware translation paths.

Important properties:

- surrogate ranges are never emitted
- width splits happen at UTF-8 sequence boundaries
- sequence masks are split like vendored upstream logic

## Error model

File: [`src/regex/syntax/error.cr`](../src/regex/syntax/error.cr)

There are three relevant layers:

- `Regex::Syntax::ParseError`
  - internal transport error used during parsing/translation
- `Regex::Syntax::AST::Error`
  - structured AST/parser error surface
- `Regex::Syntax::Hir::Error`
  - structured translator/HIR error surface

The formatter renders:

- single-line carets
- multiple same-line spans
- multiline notes with divider blocks
- exact translated spans for HIR errors such as `InvalidUtf8` and `InvalidLineTerminator`

## Printer and visitor modules

Files:

- [`src/regex/syntax/ast_print.cr`](../src/regex/syntax/ast_print.cr)
- [`src/regex/syntax/hir_print.cr`](../src/regex/syntax/hir_print.cr)
- [`src/regex/syntax/ast_visitor.cr`](../src/regex/syntax/ast_visitor.cr)
- [`src/regex/syntax/hir_visitor.cr`](../src/regex/syntax/hir_visitor.cr)

These are dedicated modules, not convenience wrappers. They matter for parity because upstream tests rely on:

- AST round-tripping that preserves escape forms the AST still remembers
- HIR pretty-print precedence
- non-recursive visitor traversal order
- visitor failure propagation

## Where the parity evidence lives

Runtime code is only half of the architecture story in this repo. The other half is the parity evidence:

- [`plans/parity.md`](../plans/parity.md)
- [`plans/inventory/rust_test_parity.tsv`](../plans/inventory/rust_test_parity.tsv)
- [`plans/inventory/rust_source_parity.tsv`](../plans/inventory/rust_source_parity.tsv)
- [`plans/inventory/rust_port_inventory.tsv`](../plans/inventory/rust_port_inventory.tsv)

These documents distinguish:

- implemented semantics
- intentional API/model differences
- Rust-specific non-applicable branches

They are part of how this port is maintained, not auxiliary documentation.
