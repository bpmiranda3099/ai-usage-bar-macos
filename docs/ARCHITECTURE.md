# Architecture

A macOS menu bar app that shows Antigravity, Claude Code and OpenCode usage as meters.

## Layout

```
Package.swift
Sources/
  AIAgentsUsageBar/        Entry point and AppDelegate (status item, panel placement)
  UsageBarCore/            Everything else, as a library so it can be tested
    Domain/                UsageSection > UsageRow > Meter, Tint, UsageProvider protocol
    Providers/             One folder per source (Antigravity, ClaudeCode, OpenCode)
    Services/              UsageStore (fetches providers, keeps results)
    Infrastructure/        HTTPClient, SubprocessRunner, SQLiteReader, Tool, OpenCodePaths
    Support/               Percent, Formatting, Concurrency
    UI/                    Theme, Components, Screens, Panel
    Resources/             Provider glyph PNGs
Tests/UsageBarCoreTests/   Swift Testing suites
docs/                      This file, SECURITY, CONTRIBUTING, PR template
deploy.sh                  Build and install as a LaunchAgent
```

## How data flows

1. `UsageStore` asks every provider in `ProviderRegistry.all` for its sections, all at once,
   and keeps them in registry order.
2. A provider runs its tool or API, parses the result into rows and meters, and returns
   `[UsageSection]`. If it has nothing to show it returns `[]`; it never throws.
3. `ContentView` loops over the sections and renders each with `ProviderSectionView`.
   Nothing in the UI knows about a specific provider.
4. Rows with a `liveMeter` closure (the NVIDIA per-minute meter) are recomputed every few
   seconds while the panel is open, from local data only.

## Domain model

| Type | Meaning |
|---|---|
| `UsageSection` | A collapsible group: id, title, tint, rows. The id is also the key for the saved expanded state. |
| `UsageRow` | A label, tooltip lines, and either meters or a text line. |
| `Meter` | A window label ("5h", "wk", "1d"), percent left, and a `Reset`. |
| `Reset` | `.countdown` (clock and time left) or `.calendar` (day and time). |

A row has at most two meters in fixed columns (short window, long window) so bars line up
across rows.

## Add a provider

1. Create a type conforming to `UsageProvider` under `Providers/<Name>/`. Keep parsing in a
   pure function that takes text or JSON and a `now` date, so it can be tested without I/O.
2. Return a `UsageSection` (or `[]`).
3. Add it to `ProviderRegistry.all`.
4. Add a glyph `<tint>-glyph.png` to `Resources/` if it needs its own icon, and a case to
   `Tint`.
5. Write tests for the parser and for the section it produces.

## Add an OpenCode quota source

OpenCode providers get meters from `ProviderUsageAPI` (direct provider APIs) or
`GoogleFreeTier`. Add a reader that returns an `OpenCodeUsageFetcher.Quota`, call it from
`ProviderUsageAPI.fetch`, and add the host to `HTTPClient.defaultAllowedHosts`.

## Conventions

- Time-dependent code takes a `now:` parameter instead of reading the clock.
- External tools run through `Tool` (absolute paths, fixed arguments, no shell).
- Network calls go through `HTTPClient` only; SQLite reads through `SQLiteReader` only.
- Text from providers is shown with `Text(verbatim:)`.

## Tests

`swift test` runs the suites in `Tests/UsageBarCoreTests`: parsers, section building, the
store, the HTTP client rules, the subprocess runner, and the SQLite reader. Network and
subprocess behavior is tested with stubs and temp files; nothing in the suite talks to the
real services. The panel itself is checked by hand with `./deploy.sh`.
