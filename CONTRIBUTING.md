# Contributing to Homie

Thank you for your interest in contributing to Homie! This document provides guidelines for contributing to the project.

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## Getting Started

1. Fork the repository
2. Follow the setup instructions in the [README](README.md)
3. Create a feature branch from `main`

## PR Workflow

### 1. Create a Branch

Use descriptive branch names:

```
<type>/<scope>-<short-description>
```

Examples:
- `fix/desktop-audio-crash`
- `feat/website-dark-mode`
- `docs/readme-update`

### 2. Make Your Changes

- Keep diffs minimal and targeted
- Test your changes locally
- Follow the code style in [AGENTS.md](AGENTS.md)

### 3. Commit with Conventional Commits

Use this format for commits and PR titles:

```
<type>(<scope>): <description>
```

**Types:**
| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, dependencies, or tooling |

**Scopes:**
| Scope | Description |
|-------|-------------|
| `desktop` | macOS app (homie/) |
| `website` | Web app (homie_website/) |
| `backend` | Supabase functions |
| `ci` | GitHub Actions, build scripts |

**Examples:**
- `fix(desktop): resolve audio input crash on M1`
- `feat(website): add user settings page`
- `docs(backend): update edge function examples`
- `chore(ci): update Xcode version in workflow`

### 4. Open a Pull Request

1. Push your branch to your fork
2. Open a PR against `main`
3. Use the same conventional commit format for the PR title
4. Describe what your PR does and why
5. Link related issues (e.g., `Closes #123`)
6. Enable "Allow maintainer edits"

### 5. Review Process

- A maintainer will review your PR
- Address any feedback
- Once approved, a maintainer will merge

## Project Structure

```
homie_project/
├── homie/           # macOS app (Swift/SwiftUI)
├── homie_website/   # Web app (Next.js)
└── supabase/        # Backend (Edge Functions)
```

## Questions?

Open an issue for questions or discussion.
