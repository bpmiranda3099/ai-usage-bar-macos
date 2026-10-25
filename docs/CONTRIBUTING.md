# Contributing

## Branches

`type/short-name`, lowercase, words joined with hyphens.

| Type | Use for |
|---|---|
| `feat` | New behavior |
| `fix` | Bug fix |
| `refactor` | Restructure, no behavior change |
| `test` | Tests only |
| `docs` | Documentation only |
| `build` | Package, scripts, toolchain |
| `perf` | Faster or lighter, same behavior |
| `chore` | Housekeeping |
| `revert` | Undo a previous change |

Examples: `fix/groq-reset-header`, `refactor/shared-infrastructure`.

## Commits

`type: summary`, imperative, under 72 characters. Types are the same as for branches and
follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). Add a body only
when the reason is not obvious. No author trailers.

## Pull requests

- One change per PR, against `main` (or the previous PR's branch in a stacked series).
- Title is `type: summary`.
- Fill in the PR template and skip sections that do not apply.
- Include tests for logic with branches, parsing or security. Docs-only changes are exempt.

Before opening:

```sh
swift build -c release
swift test
git secrets --scan
```

## Secrets

The repo is public and history is permanent. Never commit keys, tokens, account ids or
emails, including in test fixtures.

```sh
git secrets --install
git secrets --register-aws
git secrets --add 'nvapi-[A-Za-z0-9_-]{20,}'
git secrets --add 'gsk_[A-Za-z0-9]{20,}'
git secrets --add 'sk-or-v1-[A-Za-z0-9]{20,}'
git secrets --add 'AIza[0-9A-Za-z_-]{35}'
```

If a secret is ever pushed, rotate it first, then clean history.

## Vulnerabilities

See [SECURITY.md](SECURITY.md).

## Versioning

Semantic versioning. No releases are tagged yet.
