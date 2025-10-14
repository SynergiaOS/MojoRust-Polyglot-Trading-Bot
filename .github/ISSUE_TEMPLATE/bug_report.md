---
name: Bug Report
about: Report a bug or unexpected behavior
title: '[BUG] '
labels: bug, needs-triage
assignees: ''

---

## Bug Description

A clear and concise description of what the bug is.

### What Happened vs Expected

- **Expected:** What should have happened
- **Actual:** What actually happened

## Steps to Reproduce

Please provide detailed steps to reproduce the issue:

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

### Minimal Reproducible Example

If applicable, provide a minimal example that reproduces the issue:

```bash
# Commands to reproduce
# Or code snippet
```

## Expected Behavior

Clear and concise description of what you expected to happen.

## Actual Behavior

Clear and concise description of what actually happened.

### Error Messages

Include any error messages, stack traces, or logs:

```
Paste error messages here
```

## Environment

**Please complete the following information:**

- **OS:** (e.g., Ubuntu 22.04, macOS 13.0, Windows 11)
- **Mojo Version:** (output of `mojo --version`)
- **Rust Version:** (output of `rustc --version`)
- **Bot Version:** (from CHANGELOG.md or git tag)
- **Deployment Mode:** (paper/live)
- **Configuration:** (relevant settings from trading.toml)
- **Python Version:** (if applicable, output of `python --version`)

### Installation Method

- [ ] Built from source
- [ ] Docker deployment
- [ ] VPS deployment script
- [ ] Other (please specify)

## Configuration

**Please provide relevant configuration (remove sensitive information):**

```toml
# Relevant sections from trading.toml
```

**Environment Variables:**
```bash
# Relevant environment variables (remove API keys and secrets)
```

## Logs

**Please provide relevant log excerpts:**

**Application Logs:** (from `logs/trading-bot-*.log`)
```
Paste relevant log lines here
```

**Error Logs:** (if separate)
```
Paste error logs here
```

**System Logs:** (if relevant)
```
Paste system logs here
```

## Screenshots

If applicable, add screenshots to help explain your problem.

**Screenshots should show:**
- Error messages
- Configuration issues
- Dashboard problems
- Trading interface issues

## Additional Context

**Additional Information:**
- When did this issue start occurring?
- Does it happen consistently or intermittently?
- Any recent changes that might be related?
- Workarounds you've tried
- Other relevant information

### Related Issues

- Linked to any related issues: #XXX
- Duplicates any existing issues: #XXX

### Impact Assessment

- **Severity:** (Low/Medium/High/Critical)
- **Frequency:** (Always/Sometimes/Rarely)
- **Impact on Trading:** (None/Minor/Major/Critical)

## Security Consideration

**Is this a security vulnerability?**

- [ ] Yes - This is a security vulnerability (Please report via [Security Policy](../../SECURITY.md) instead)
- [ ] No - This is not a security vulnerability

**If this involves security, please:**
1. Do not provide details in this public issue
2. Report privately via GitHub Security Advisories
3. See [SECURITY.md](../../SECURITY.md) for proper reporting procedure

## Checklist

**Before submitting, please confirm:**

- [ ] I have searched existing issues for duplicates
- [ ] I have read the relevant documentation
- [ ] I have included logs and error messages
- [ ] I have removed sensitive information (API keys, private keys, passwords)
- [ ] I have provided sufficient detail to reproduce the issue
- [ ] I have included environment information
- [ ] This is not a security vulnerability (use SECURITY.md for those)

## Additional Help

**Need help with this issue?**

- **Documentation:** Check the [docs/](../../docs/) directory
- **Community:** Ask in [GitHub Discussions](https://github.com/SynergiaOS/MojoRust/discussions)
- **Troubleshooting:** See [DEPLOYMENT.md](../../DEPLOYMENT.md#troubleshooting)

---

**Thank you for reporting this bug! 🐛**

Your bug reports help us improve the MojoRust Trading Bot for everyone.