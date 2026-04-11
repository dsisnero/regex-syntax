# regex-syntax

`regex-syntax` is the Crystal port of Rust's `regex-syntax` crate used by Logos.
It parses regex patterns into a typed HIR (high-level intermediate representation)
that is consumed by `regex-automata`.

## Installation

Add to `shard.yml`:

```yaml
dependencies:
  regex-syntax:
    github: dsisnero/logos
    path: lib/regex-syntax
```

Then run:

```bash
shards install
```

## Usage

```crystal
require "regex-syntax"

hir = Regex::Syntax.parse("[a-z]+")
puts hir.class                       # Regex::Syntax::Hir::Hir
puts hir.complexity                  # priority heuristic
puts hir.has_greedy_all?             # greedy-dot detection
puts hir.can_match_empty?            # empty-match analysis
```

### Supported constructs (Logos-focused)

- Literals and concatenation
- Alternation (`|`)
- Character classes (`[]`, `\d`, `\w`, `\s`, unicode properties)
- Repetition (`*`, `+`, `?`, `{m,n}`)
- Captures and non-capturing groups
- Start/end and word-boundary assertions (`^`, `$`, `\A`, `\z`, `\Z`, `\b`, `\B`)
- Inline flags used by Logos (`i`, `u`)

## Development

From this directory:

```bash
crystal tool format src spec
crystal spec
```

For full-repo checks, run from repository root:

```bash
ameba src spec
crystal spec
```

## Upstream reference

- Rust source of truth: `vendor/regex-syntax/`
- Crystal integration points:
  - `lib/regex-automata/`
  - `src/logos/macros.cr`

## License

MIT
