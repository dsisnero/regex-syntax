# Architecture

## Overview

`regex-syntax` is a Crystal library for parsing regular expressions into a typed HIR (high-level intermediate representation). The Rust `regex-syntax` crate is the source of truth for behavior and structure, and this port keeps the same staged parse pipeline: source text -> AST -> HIR.

## Design Philosophy

### Porting Approach
- **Source fidelity**: Rust `regex-syntax` behavior is the contract
- **Staged lowering**: Parse into AST first, then translate AST into HIR
- **Zero-copy where possible**: Minimize allocations in parsing hot paths
- **Crystal integration**: Preserve semantics while fitting Crystal APIs

## Module Structure

### Core Modules
```
Regex::Syntax
├── Parser           # Public parse facade (regex string → AST → HIR)
├── AstParser        # AST parser used by the public parser facade
├── Hir              # High-level intermediate representation
│   ├── Hir          # Root HIR container
│   ├── Node         # Base HIR node type
│   ├── Literal      # String literals
│   ├── Concat       # Sequence concatenation
│   ├── Alternation  # Choice (| operator)
│   ├── Repetition   # *, +, ?, {m,n} quantifiers
│   ├── CharClass    # Character classes [a-z]
│   ├── UnicodeClass # Unicode property classes \p{L}
│   ├── Capture      # Capturing groups
│   ├── Look         # Assertions (^, $, \b, etc.)
│   └── DotNode      # . wildcard
├── Ast              # Abstract syntax tree types
├── Translator       # AST → HIR lowering
└── Unicode          # Unicode property support
    └── UnicodeTables # Compiled Unicode property data
```

## Data Flow

### Parsing Pipeline
```
Regex String
    │
    ▼
AstParser
    │
    ▼
AST Nodes
    │
    ▼
Translator
    │
    ▼
HIR Nodes
    │
    ▼
Hir Container
```

### Key Components

1. **`AstParser` class** (`src/regex-syntax.cr`)
   - Recursive descent parser for Rust-like AST structures
   - Handles flags, character classes, and escape parsing
   - Preserves class-set structure for later lowering

2. **`Translator` class** (`src/regex/syntax/translate.cr`)
   - Lowers AST into HIR
   - Applies flags and class-set operations
   - Keeps lowering behavior centralized

3. **`Hir` module** (`src/regex/syntax/hir.cr`)
   - Typed representation of regex semantics
   - Case folding operations (ASCII and Unicode)
   - Node simplification and normalization
   - Properties computation (complexity, emptiness, etc.)

4. **`Unicode` module** (`src/regex/syntax/unicode.cr`)
   - Unicode property lookups
   - Character class construction
   - Case folding tables
   - Compiled from Unicode data files

## Performance Characteristics

### Memory Efficiency
- **String slices**: Uses `String` indexing for zero-copy parsing where possible
- **Minimal allocations**: Reuses buffers and pre-allocates collections
- **Compiled tables**: Unicode data compiled into efficient lookup structures

### Parsing Strategy
- **Staged parsing**: AST creation followed by HIR lowering
- **Recursive descent**: Predictable stack usage
- **Early validation**: Syntax errors caught during AST parsing
- **Explicit lowering**: Semantic transforms happen in one translator layer

## Integration Points

### Dependencies
- **Self-contained**: No external dependencies beyond Crystal stdlib
- **`regex-automata`**: Consumes HIR for automaton construction
- **`logos`**: Uses parser for lexer generation

### API Design
```crystal
# Main entry point
hir = Regex::Syntax.parse("[a-z]+")

# Configuration options
parser = Regex::Syntax::Parser.new(
  unicode: true,
  ignore_case: false,
  nest_limit: 1000
)
hir = parser.parse(pattern)
```

## Trade-offs

### Current Trade-offs
- **Exception-based errors**: More idiomatic Crystal than Rust's result types
- **Crystal spans/strings**: Integrates with Crystal string handling instead of Rust slices
- **Separate lowering layer**: Keeps behavior closer to upstream and avoids parser/translator drift

### Unicode Support
- **Full Unicode 13.0**: Property classes, script ranges, case folding
- **ASCII fallback**: When `unicode: false` option is set
- **Compiled tables**: Fast lookups, larger binary size
