# Development

## Setup

### Prerequisites
- Crystal 1.0+
- Git

### Installation
```bash
make install
```

## Workflow

### Code Quality Gates
Always run before committing:
```bash
make format
make lint
make test
```

### Testing
- Run all tests: `make test`
- Run specific test file: `crystal spec spec/path/to/file_spec.cr`
- Test with coverage: `crystal spec --release`

### Formatting
- Check formatting: `make format`
- Auto-format: `crystal tool format src spec`

### Linting
- Run ameba: `make lint`
- Auto-correct where possible: `ameba --fix src spec`

## Architecture Notes

### Design Approach
This implementation follows Rust's staged parse pipeline:

1. **AST parsing**: Regex string → AST nodes
2. **Semantic lowering**: AST → HIR translation
3. **Crystal integration**: Exception-based errors and Crystal-facing APIs

### Porting from Rust Reference
- Rust source: `vendor/regex-syntax/` (symlink to upstream for reference)
- Behavioral parity: Match Rust behavior, not necessarily implementation
- Test conversion: Adapt Rust tests to Crystal idioms while preserving semantics

### Parity Tracking
- Use cross-language parity scripts in `scripts/`
- Update `plans/inventory/rust_port_inventory.tsv` as features are implemented
- Run parity checks: `./scripts/check_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/regex-syntax rust`

### Temporary Files
All generated files go in `./temp/` directory:
```bash
mkdir -p temp
# Generated files go here
make clean  # Cleans temp directory
```
