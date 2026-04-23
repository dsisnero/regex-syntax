# Coding Guidelines

## Crystal Conventions

### Naming
- `PascalCase` for classes, modules, structs, enums
- `snake_case` for methods, variables, files
- `SCREAMING_SNAKE_CASE` for constants
- `@instance_variables` for instance variables
- `@@class_variables` for class variables

### Style
- Use 2-space indentation
- Prefer `def` over `fun` for method definitions
- Use `private` for internal methods
- Document public APIs with YARD-style comments

### Types
- Always specify return types for public methods
- Use union types (`Type1 | Type2`) for flexible APIs
- Leverage Crystal's type inference for internal code

## Porting from Rust

### Type Mapping
- Rust `struct` → Crystal `struct` or `class`
- Rust `enum` → Crystal `enum` or union types
- Rust `Option<T>` → Crystal `T?` or `T | Nil`
- Rust `Result<T, E>` → Crystal exception handling or `T | E`

### Error Handling
- Use exceptions for unrecoverable errors
- Return `nil` or `T?` for optional values
- Follow Crystal's `raise/rescue` pattern

### Performance
- Maintain Rust's zero-copy semantics where possible
- Use `String` slices (`String::Substring`) for parsing
- Avoid unnecessary allocations in hot paths

## Project Structure

### File Organization
```
src/
  regex-syntax.cr           # Main entry point
  regex/
    syntax/                 # Core implementation
      ast.cr               # Abstract syntax tree
      hir.cr               # High-level IR
      parser.cr            # Parser
      unicode.cr           # Unicode support
      unicode_tables/      # Generated tables
```

### Module Hierarchy
```crystal
module Regex
  module Syntax
    # Main API
    class Parser
    class Error < Exception
    module Hir
      class Hir
    end
  end
end
```