# Regex Syntax for Crystal

A regular expression parser for Crystal, faithfully ported from Rust's `regex-syntax` crate.

## Verified Commands

```bash
# Install dependencies
make install

# Update dependencies
make update

# Format code
make format

# Lint code
make lint

# Run tests
make test

# Clean temporary files
make clean
```

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/architecture.md](../../docs/architecture.md) | System architecture and design decisions |
| [docs/development.md](../../docs/development.md) | Development workflow and setup |
| [docs/coding-guidelines.md](../../docs/coding-guidelines.md) | Code style and conventions |
| [docs/testing.md](../../docs/testing.md) | Testing strategy and patterns |
| [docs/pr-workflow.md](../../docs/pr-workflow.md) | Pull request and review process |

## Core Principles

1. **Source fidelity**: Match Rust `regex-syntax` behavior exactly
2. **Crystal idioms**: Follow Crystal conventions while preserving Rust semantics
3. **Zero-copy parsing**: Maintain Rust's performance characteristics where possible
4. **Test parity**: Port Rust tests faithfully to ensure behavioral correctness
5. **Minimal dependencies**: Keep the library lightweight and self-contained

## Commit Message Convention

Follow conventional commits format:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc.)
- `refactor:` Code refactoring
- `test:` Test changes
- `chore:` Maintenance tasks

## Project Conventions

- **Source language**: Port from Rust (`vendor/regex-syntax/`)
- **Test porting**: Convert Rust tests to Crystal specs with exact assertions
- **Temporary files**: All generated files go in `./temp/` directory
- **Quality gates**: Always run `make lint`, `make format`, `make test` before committing
- **Issue tracking**: Use `bd` (beads) for all work management