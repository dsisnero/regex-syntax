# regex-syntax for Crystal

`regex-syntax` is a Crystal port of Rust's [`regex-syntax`](./vendor/regex-syntax/) crate. It parses regex source into a faithful AST and then lowers that AST into a typed HIR suitable for analysis, printing, and downstream automata work.

This port tracks vendored Rust behavior as the contract. The implementation is not a simplified Crystal-only regex parser: it includes the staged AST -> HIR pipeline, structured parser and translator errors, Unicode property tables, interval algebra, literal extraction, UTF-8 helpers, and dedicated printer/visitor modules.

## Documentation

- [Architecture](./docs/architecture.md)
- [Development](./docs/development.md)
- [Coding Guidelines](./docs/coding-guidelines.md)
- [Testing](./docs/testing.md)
- [PR Workflow](./docs/pr-workflow.md)

## Installation

Add this shard to your `shard.yml`:

```yaml
dependencies:
  regex-syntax:
    github: dsisnero/regex-syntax
```

Then install dependencies:

```bash
shards install
```

## Public entry points

The main entry points are:

- `Regex::Syntax.parse(pattern)` for the default staged parse-to-HIR path
- `Regex::Syntax::Parser` and `Regex::Syntax::ParserBuilder` for HIR parsing with explicit options
- `Regex::Syntax::AstParser` and `Regex::Syntax::AstParserBuilder` for direct AST parsing
- `Regex::Syntax::AST::Printer` and `Regex::Syntax::Hir::Printer` for round-tripping
- `Regex::Syntax::AST.visit` and `Regex::Syntax::Hir.visit` for non-recursive traversal
- `Regex::Syntax::Hir::LiteralExtraction` for prefix/suffix literal extraction

## Examples

Parse directly to HIR:

```crystal
require "regex-syntax"

hir = Regex::Syntax.parse("(?i)[a-z]+")

pp hir.node
pp hir.minimum_len
pp hir.maximum_len
pp hir.look_set_prefix
pp hir.utf8?
```

Configure the public parser:

```crystal
require "regex-syntax"

parser = Regex::Syntax::ParserBuilder.new
  .unicode(true)
  .utf8(true)
  .case_insensitive(true)
  .multi_line(true)
  .dot_matches_new_line(false)
  .ignore_whitespace(true)
  .crlf(false)
  .nest_limit(250)
  .octal(false)
  .line_terminator('\n'.ord.to_u8)
  .build

hir = parser.parse("(?x) [[:alpha:]_]+ ")
pp hir.node
```

Parse directly to AST and preserve verbose-mode comments:

```crystal
require "regex-syntax"

parser = Regex::Syntax::AstParserBuilder.new
  .ignore_whitespace(true)
  .nest_limit(100)
  .build

with_comments = parser.parse_with_comments("(?x) a # first\n b # second")

pp with_comments.ast.root
pp with_comments.comments.map(&.comment)
```

Handle structured parse errors:

```crystal
require "regex-syntax"

begin
  Regex::Syntax.parse("[z-a]")
rescue ex : Regex::Syntax::Hir::Error
  puts ex.kind
  puts ex.raw_message
  puts ex
end
```

Use the helper surface that mirrors vendored `src/lib.rs` behavior:

```crystal
require "regex-syntax"

Regex::Syntax.escape("a+b")                # => "a\\+b"
Regex::Syntax.meta_character?('+')         # => true
Regex::Syntax.escapeable_character?('=')   # => true
Regex::Syntax.word_byte?('A'.ord.to_u8)    # => true
Regex::Syntax.word_character?('β')         # => true
```

## What is implemented

This port includes the major upstream subsystems, not just the main parse call:

- AST parsing with scoped/global flags, named captures, class-set binary operators, octal mode, verbose mode, and special word-boundary forms
- HIR translation with Unicode-vs-byte mode, UTF-8 gating, custom line terminators, smart concat/alternation/repetition normalization, and structured translator errors
- Unicode/property support for general categories, scripts, script extensions, age, grapheme/word/sentence break classes, Perl word tables, and vendored alias tables
- HIR interval algebra for union, intersection, difference, symmetric difference, negation, and case folding
- Literal extraction and optimization modeled on vendored `src/hir/literal.rs`
- Dedicated AST/HIR printer and visitor surfaces
- UTF-8 range splitting helpers modeled on vendored `src/utf8.rs`

## Quality gates

Verified commands in this repo:

```bash
make install
make update
make format
make lint
make test
make clean
```

`make format`, `make lint`, and `make test` are the expected gates before committing.

## Repository layout

Key implementation files:

- [`src/regex-syntax.cr`](./src/regex-syntax.cr): top-level API and direct `AstParser`
- [`src/regex/syntax/parser.cr`](./src/regex/syntax/parser.cr): `AstParserBuilder`, `ParserBuilder`, and staged public parser
- [`src/regex/syntax/ast.cr`](./src/regex/syntax/ast.cr): AST model
- [`src/regex/syntax/hir.cr`](./src/regex/syntax/hir.cr): HIR model, interval ops, and HIR property surface
- [`src/regex/syntax/translate.cr`](./src/regex/syntax/translate.cr): AST -> HIR lowering
- [`src/regex/syntax/unicode.cr`](./src/regex/syntax/unicode.cr): Unicode property resolution and case folding helpers
- [`src/regex/syntax/error.cr`](./src/regex/syntax/error.cr): structured AST/HIR error types and formatter
- [`src/regex/syntax/literal.cr`](./src/regex/syntax/literal.cr): literal extraction and optimization
- [`src/regex/syntax/utf8.cr`](./src/regex/syntax/utf8.cr): UTF-8 range decomposition

Key spec files:

- [`spec/parser_spec.cr`](./spec/parser_spec.cr): direct AST parser behavior
- [`spec/regex-syntax_spec.cr`](./spec/regex-syntax_spec.cr): public parser/HIR parity matrix
- [`spec/translator_spec.cr`](./spec/translator_spec.cr): translator-specific regressions
- [`spec/hir_semantic_parity_spec.cr`](./spec/hir_semantic_parity_spec.cr): vendored HIR semantics matrix
- [`spec/hir_literal_spec.cr`](./spec/hir_literal_spec.cr): vendored literal extraction matrix
- [`spec/unicode_spec.cr`](./spec/unicode_spec.cr) and [`spec/utf8_spec.cr`](./spec/utf8_spec.cr): dedicated Unicode/UTF-8 helpers

Parity tracking lives in:

- [`plans/parity.md`](./plans/parity.md)
- [`plans/inventory/rust_test_parity.tsv`](./plans/inventory/rust_test_parity.tsv)
- [`plans/inventory/rust_source_parity.tsv`](./plans/inventory/rust_source_parity.tsv)
- [`plans/inventory/rust_port_inventory.tsv`](./plans/inventory/rust_port_inventory.tsv)

## Upstream source of truth

Rust remains the behavioral contract:

- Vendored upstream source: [`vendor/regex-syntax/`](./vendor/regex-syntax/)
- Public docs inspiration: upstream `README.md`, `src/ast/*`, `src/hir/*`, `src/parser.rs`, `src/unicode.rs`, and `src/utf8.rs`

Where Crystal differs, the inventories document whether the difference is:

- a deliberate API/model-shape choice
- a runtime/layout difference that is not meaningful to port literally
- or a feature branch that only exists in Rust as a compile-time-disabled Cargo configuration

## License

Dual licensed under `MIT OR Apache-2.0`, matching the project metadata in [`shard.yml`](./shard.yml).
