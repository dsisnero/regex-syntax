# Pull Request Workflow

## Branch Strategy

### Feature Branches
- Create branch from `main`: `git checkout -b feat/feature-name`
- Use descriptive branch names:
  - `feat/` for new features
  - `fix/` for bug fixes
  - `docs/` for documentation
  - `refactor/` for code refactoring
  - `test/` for test changes

### Commit Messages
Follow conventional commits format:
- `feat: add unicode property support`
- `fix: handle edge case in parser`
- `docs: update API documentation`
- `style: format code with crystal tool`
- `refactor: simplify HIR construction`
- `test: add spec for character classes`
- `chore: update dependencies`

## PR Creation

### Before Creating PR
1. Run quality gates:
   ```bash
   make format
   make lint
   make test
   ```
2. Ensure all tests pass
3. Update parity inventory if porting work
4. Add/update documentation as needed

### PR Description
Include:
- **Summary**: Brief description of changes
- **Related Issue**: Link to issue or upstream reference
- **Testing**: How changes were tested
- **Parity Impact**: Effect on Rust porting status
- **Checklist**: Quality gates completed

## Code Review

### Review Checklist
- [ ] Code follows Crystal conventions
- [ ] Tests pass and cover changes
- [ ] Documentation updated
- [ ] No regression in parity
- [ ] Performance considerations addressed
- [ ] Error handling appropriate

### Review Process
1. Request review from maintainers
2. Address review comments
3. Update PR with fixes
4. Re-run quality gates after changes
5. Squash commits if requested

## Merging

### Merge Criteria
- All checks pass (CI, tests, linting)
- Approved by at least one maintainer
- No unresolved discussions
- Parity inventory updated if applicable

### Post-Merge
- Delete feature branch
- Update changelog if needed
- Verify deployment/package updates