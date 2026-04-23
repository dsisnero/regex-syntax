# Testing

## Philosophy

**Test parity**: Port Rust tests faithfully to ensure behavioral correctness with the upstream `regex-syntax` crate.

## Test Structure

### Spec Files
- `spec/regex/syntax/parser_spec.cr` - Parser tests
- `spec/regex/syntax/ast_spec.cr` - AST tests
- `spec/regex/syntax/hir_spec.cr` - HIR tests
- `spec/regex/syntax/unicode_spec.cr` - Unicode tests

### Test Patterns
```crystal
describe "Regex::Syntax::Parser" do
  it "parses simple patterns" do
    hir = Regex::Syntax.parse("[a-z]+")
    hir.should be_a(Regex::Syntax::Hir::Hir)
  end

  it "handles alternation" do
    hir = Regex::Syntax.parse("a|b")
    # Test specific behavior
  end
end
```

## Porting Rust Tests

### Source Reference
- Rust tests: `vendor/regex-syntax/src/` and `vendor/regex-syntax/test/`
- Convert `#[test]` functions to Crystal `it` blocks
- Preserve test names and assertions

### Assertion Mapping
- Rust `assert!(expr)` → Crystal `expr.should be_true`
- Rust `assert_eq!(a, b)` → Crystal `a.should eq(b)`
- Rust `assert_ne!(a, b)` → Crystal `a.should_not eq(b)`

### Test Data
- Use same test patterns as Rust source
- Include edge cases and error conditions
- Test Unicode properties and character classes

## Running Tests

### Basic Testing
```bash
make test           # Run all tests
crystal spec        # Run all tests (alternative)
```

### Specific Tests
```bash
crystal spec spec/regex/syntax/parser_spec.cr
crystal spec --line 42 spec/regex/syntax/parser_spec.cr
```

### Test Coverage
```bash
crystal spec --release  # Faster execution
```

## Test Maintenance

### Adding New Tests
1. Identify corresponding Rust test
2. Port to Crystal with exact assertions
3. Update parity inventory status
4. Run all tests to ensure no regressions

### Test Updates
- When Rust source tests change, update Crystal tests accordingly
- Run parity checks to identify test drift
- Maintain test parity manifest in `plans/inventory/rust_test_parity.tsv`