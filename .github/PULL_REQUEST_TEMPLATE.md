## Description

Brief summary of changes made in this pull request.

### What problem does this solve?

Why is this change needed? What issue does it address?

### Related Issues

- Fixes #123
- Relates to #456
- Closes #789

## Type of Change

Please check all that apply:

- [ ] **Bug fix** (non-breaking change that fixes an issue)
- [ ] **New feature** (non-breaking change that adds functionality)
- [ ] **Breaking change** (fix or feature that would cause existing functionality to not work as expected)
- [ ] **Performance improvement** (optimization that improves speed, memory usage, etc.)
- [ ] **Documentation update** (documentation changes only)
- [ ] **Security fix** (vulnerability or security improvement)
- [ ] **Refactoring** (code cleanup without functional changes)
- [ ] **CI/CD changes** (build, test, deployment pipeline changes)
- [ ] **Tests** (adding or improving tests)

## Changes Made

### Code Changes

- **File:** `src/module/file.mojo` - Description of changes
- **File:** `rust-modules/src/file.rs` - Description of changes
- **File:** `config/file.toml` - Description of changes

### New Dependencies

- [ ] Added Python dependency: `package-name` (version)
- [ ] Added Rust dependency: `crate-name` (version)
- [ ] Added Mojo dependency: `module-name`

### Configuration Changes

- **New config section:** `[new_section]` in `trading.toml`
- **Updated config values:** Modified existing parameters
- **Environment variables:** Added new `ENV_VAR` requirements

### Database Changes

- [ ] New tables created
- [ ] Schema modifications
- [ ] Migration required

## Testing

### Test Coverage

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Load tests added/updated (if performance-critical)
- [ ] Manual testing performed
- [ ] End-to-end testing completed

### Test Results

**Coverage Information:**
- **Coverage before:** X%
- **Coverage after:** Y%
- **New tests added:** X
- **Tests modified:** X

**Automated Tests:**
```bash
# Commands to run tests
make test-all
```

**Manual Testing:**
- [ ] Paper trading test completed
- [ ] Configuration validation
- [ ] Error handling verified
- [ ] Performance validated

### Test Environment

- **Environment:** (development/staging/production)
- **Configuration:** (special config used for testing)
- **Data:** (test data or mock data used)

## Performance Impact

### Benchmark Results

**Before Changes:**
- Metric 1: X
- Metric 2: Y
- Memory usage: Z MB

**After Changes:**
- Metric 1: X (+Y% improvement)
- Metric 2: Y (+Z% improvement)
- Memory usage: Z MB (+A% change)

**Benchmarks Run:**
```bash
# Benchmark commands
make bench-ffi
cd rust-modules && cargo bench
```

### Performance Characteristics

- [ ] **Improved performance** (faster execution)
- [ ] **Reduced memory usage**
- [ ] **Increased memory usage** (acceptable)
- [ ] **Slower performance** (acceptable trade-off)
- [ ] **No significant performance change**

### Resource Impact

- **CPU Usage:** (increase/decrease/none)
- **Memory Usage:** (increase/decrease/none)
- **Network I/O:** (increase/decrease/none)
- **Disk I/O:** (increase/decrease/none)

## Security Considerations

### Security Review

- [ ] No hardcoded secrets: `make validate-secrets` passed
- [ ] Security scan passed: CI security job green
- [ ] No new vulnerabilities introduced
- [ ] Input validation implemented
- [ ] Error handling doesn't leak sensitive information

### Security Changes

**New Security Features:**
- Feature 1: Description
- Feature 2: Description

**Security Improvements:**
- Improvement 1: Description
- Improvement 2: Description

**Security Risks:**
- [ ] New attack surface introduced
- [ ] Increased complexity in security-critical areas
- [ ] Changes to authentication/authorization

### Sensitive Changes

If this PR touches security-sensitive areas:

- [ ] **Wallet operations** - Changes to private key handling, wallet management
- [ ] **API authentication** - Changes to API keys, authentication mechanisms
- [ ] **Network communication** - Changes to external API calls, data transmission
- [ ] **Data encryption** - Changes to encryption, data protection
- [ ] **Access control** - Changes to permissions, access controls

**Security Impact Assessment:**
- Risk Level: (Low/Medium/High/Critical)
- Mitigation: Description of mitigations implemented
- Review Required: (Yes/No - specify who should review)

## Documentation

### Documentation Updates

- [ ] **README.md** updated (if user-facing changes)
- [ ] **CHANGELOG.md** updated (for notable changes)
- [ ] **API documentation** updated (if applicable)
- [ ] **Configuration examples** updated
- [ ] **User guides** updated (in `docs/` directory)
- [ ] **Code comments** added for complex logic

### Documentation Created

**New Documentation:**
- `docs/new-guide.md` - Description
- `examples/new-example.mojo` - Description

**Updated Documentation:**
- `docs/existing-guide.md` - Updated sections
- `README.md` - Updated configuration/usage sections

### User-Facing Changes

**New Configuration Options:**
```toml
[new_section]
option1 = "value"
option2 = 123
```

**New API Endpoints:**
```
GET /api/new-endpoint
POST /api/another-endpoint
```

**New CLI Commands:**
```bash
make new-command
```

## Screenshots/Videos

### UI Changes

If this PR includes UI changes (Grafana dashboards, web interfaces, etc.):

**Before:**
[Add screenshot or description]

**After:**
[Add screenshot or description]

### Configuration Changes

**New Configuration Screenshots:**
[Add screenshots of new configuration options]

### Monitoring Changes

**New Grafana Dashboards:**
[Add screenshots of new monitoring panels]

## Deployment Notes

### Migration Steps

**Required Migration Steps:**
1. Step 1: Description
2. Step 2: Description
3. Step 3: Description

**Migration Commands:**
```bash
# Migration commands
make migrate-config
```

### Configuration Changes

**Required Configuration Updates:**
- Add new section to `trading.toml`
- Update existing configuration values
- Set new environment variables

**Breaking Changes:**
- [ ] Configuration format changed
- [ ] API endpoints changed
- [ ] Database schema changed
- [ ] Environment variables renamed

### Rollback Procedure

**Rollback Steps:**
1. Step 1: Description
2. Step 2: Description
3. Step 3: Description

**Rollback Commands:**
```bash
# Rollback commands
git revert <commit-hash>
make rollback
```

## Quality Assurance

### Code Quality

- [ ] **Code follows project style** (`make lint` passed)
- [ ] **Self-review completed** - I have reviewed my own code
- [ ] **Complex code documented** - Added comments for complex logic
- [ ] **No debugging code left** - Removed console.log, print statements, etc.
- [ ] **Error handling implemented** - Proper error handling for all paths

### Testing Quality

- [ ] **Tests added for new functionality** - Comprehensive test coverage
- [ ] **Edge cases considered** - Tested error conditions and edge cases
- [ ] **Performance tested** - Benchmarks run for performance-critical code
- [ ] **Integration tested** - Tested with other components
- [ ] **Manual testing completed** - Human verification of functionality

### Security Quality

- [ ] **No secrets committed** - Validated with `make validate-secrets`
- [ ] **Security review passed** - No security vulnerabilities introduced
- [ ] **Input validation** - All external inputs validated
- [ ] **Error message security** - No sensitive information leaked in errors

## Checklist

### Required for All PRs

- [ ] My code follows the project's code style guidelines
- [ ] I have performed a self-review of my code
- [ ] I have commented complex code sections
- [ ] I have updated documentation as required
- [ ] I have added tests that prove my fix/feature works
- [ ] New and existing tests pass locally: `make test`
- [ ] I have run linters: `make lint`
- [ ] I have run security checks: `make validate-secrets`
- [ ] I have updated CHANGELOG.md (for notable changes)
- [ ] My changes generate no new warnings
- [ ] I have checked for merge conflicts

### Additional Requirements

**For Trading Logic Changes:**
- [ ] Tested in paper trading mode for at least 24 hours
- [ ] Backtesting results included (if applicable)
- [ ] Risk implications documented and tested
- [ ] Edge cases considered (extreme volatility, low liquidity)
- [ ] Circuit breakers tested and verified

**For Performance Changes:**
- [ ] Benchmarks included with before/after results
- [ ] Performance impact assessed and documented
- [ ] Memory usage analyzed and documented
- [ ] No performance regressions >10% (CI will fail)

**For Security-Sensitive Changes:**
- [ ] Security impact assessment completed
- [ ] Reviewed by security team (if required)
- [ ] No credentials or keys in code
- [ ] Follows security best practices
- [ ] Security tests added

**For Breaking Changes:**
- [ ] Breaking changes documented in CHANGELOG.md
- [ ] Migration guide provided
- [ ] Backward compatibility considered
- [ ] Community communication plan in place

**For Documentation Changes:**
- [ ] Links verified and working
- [ ] Examples tested and working
- [ ] Screenshots included (if applicable)
- [ ] Spelling and grammar checked

## Reviewer Guidance

### Focus Areas

**Please pay special attention to:**
- [ ] Code quality and maintainability
- [ ] Test coverage and test quality
- [ ] Security implications
- [ ] Performance impact
- [ ] Documentation completeness
- [ ] Backward compatibility

### Specific Concerns

**Areas where I'd like specific feedback:**
- Area 1: Question or concern about implementation
- Area 2: Design decision that needs review
- Area 3: Potential improvement or alternative approach

### Testing Instructions

**How to Test This PR:**
1. Setup step 1
2. Setup step 2
3. Test scenario 1
4. Test scenario 2
5. Verify expected outcome

**Test Configuration:**
```bash
# Special configuration for testing
export TEST_MODE=true
make test-specific
```

## Additional Notes

### Implementation Challenges

**Challenges encountered:**
- Challenge 1: Description and solution
- Challenge 2: Description and solution

**Design Decisions:**
- Decision 1: Rationale for chosen approach
- Decision 2: Alternative approaches considered

### Future Improvements

**Known limitations or future work:**
- Limitation 1: Description and plan for improvement
- Limitation 2: Description and plan for improvement

### Dependencies

**Blocked by:**
- #123 - Description of blocking issue
- #456 - Description of blocking issue

**Blocks:**
- #789 - Description of blocked issue
- #012 - Description of blocked issue

---

**Thank you for your contribution! 🚀**

We appreciate your time and effort in improving the MojoRust Trading Bot. Please ensure all automated checks pass before requesting a review.