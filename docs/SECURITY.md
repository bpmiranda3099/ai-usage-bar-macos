# Security

The repo is public, so this records what the app touches, how it is locked down, and what
was reviewed.

## Reporting

Do not open a public issue. Report privately through the repository's GitHub security
advisories.

## What the app handles

- Provider API keys, read from OpenCode's local database (read-only) and held in memory
  for one request each. Never logged, stored, or put in a URL.
- A short-lived Google access token from `gcloud`, handled the same way.
- Output from local CLIs (`agy`, `claude`, `opencode`, `gcloud`) and from a few provider
  APIs. All of it is untrusted input to the parsers.

Trust boundaries: CLI stdout, provider JSON and headers, the OpenCode SQLite file,
`~/.config/ai-agents-usage-bar/settings.json`, and provider-supplied names shown in the UI.
Worst case if the app is fully compromised: it can read the provider keys OpenCode already
stores, so keep that database private and rotate keys if you suspect exposure.

## Controls

- **Network** (`HTTPClient`): https only, exact-host allowlist, redirects never followed
  (the Authorization header cannot reach another host), uncompressed responses requested,
  1 MB body cap, 10 s total deadline, non-200 treated as no data, control characters in
  keys and headers rejected.
- **Subprocesses** (`SubprocessRunner`, `Tool`): absolute paths only, fixed argument arrays,
  no shell, stdin and stderr closed, SIGTERM then SIGKILL on timeout, 8 MB output cap, run
  from an app-owned private directory, and the executable must belong to the user or root
  and not be group- or world-writable.
- **SQLite** (`SQLiteReader`): read-only connection, `query_only`, bound parameters only.
- **Parsers**: total (no force unwraps or `try!`), regex is a compile-time literal, numeric
  input from providers is range-checked so NaN, infinity or huge values cannot trap.
- **UI**: provider-supplied text is shown with `Text(verbatim:)` (no Markdown links or
  images).
- **Dependencies**: no third-party Swift packages, and nothing runs `node` or `npm` at
  runtime.

## Review

A BridgeSecurity audit of `Sources/` found no Critical, High or Medium issues. Findings and
what was done:

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | Low | NaN, infinity or huge provider numbers could trap in Int conversions | Fixed |
| 2 | Low | HTTP client had only an idle timeout | Fixed (total deadline, cancel on exit) |
| 3 | Low | Subprocess could hang on stderr or SIGTERM; output buffer race | Fixed |
| 4 | Low | Tool lookup had no ownership or permission check | Partly fixed (owner and mode checked; code-signature pinning not added) |
| 5 | Low | Tools ran with cwd `$HOME` (project config could run) | Fixed (private cwd); environment is still inherited |
| 6 | Info | Provider and model names are not length-capped or stripped of bidi characters | Not changed; low impact, text is verbatim |
| 7 | Info | Project id regex accepted a trailing newline; header values unchecked | Fixed |
| 8 | Info | `/usage` is passed as a prompt, which would reach the model if a CLI stopped recognizing it | Not changed; would only spend quota |
| 9 | Info | `deploy.sh` expects a local LaunchAgent plist and does not codesign | Not changed; local install script |
| 10 | Info | Regex with adjacent optional whitespace groups | Fixed |

Other checks: no secrets in source or history (git-secrets pattern scan), no logging calls,
no third-party code. BridgeSecurity's `scan.sh` does not cover Swift files, so Swift-specific
patterns (`try!`, force casts, `unsafeBitCast`, `Process`, `http://`) were checked by hand.
The one `unsafeBitCast` is SQLite's standard text-copy constant (`SQLITE_TRANSIENT`) and
lives in one place.

## If a key may have leaked

Rotate it at the provider first (OpenRouter, Groq, Ollama, Cloudflare, Google), then update
it in OpenCode. The app stores none of them.
