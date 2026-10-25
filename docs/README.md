# AI Usage Bar

A macOS menu bar app that shows how much of your Antigravity, Claude Code and OpenCode free-tier limits you have left.

Click the menu bar icon to open a panel with one section per tool. Each meter shows the percent left and when it resets. Hover a row label to see which models it covers. Click a section header to collapse it; the choice is remembered.

## What it shows

| Section | Source | Meters |
|---|---|---|
| Antigravity | `agy` | 5 hour and weekly limits per model group |
| Claude | `claude` | Session and weekly limits, plus per-model weekly limits if your plan has them |
| OpenCode | `opencode` | Free models of the providers you connected, see below |

Data refreshes every 5 minutes, or press the refresh button. A section only appears when its tool works on your Mac.

### OpenCode providers

Only free models are listed. Providers that expose a usable limit get a meter. The rest share one "Other providers" row, with their models in the tooltip.

| Provider | Meter | How it is read |
|---|---|---|
| OpenRouter | Free-model requests per day | Your key's usage endpoint |
| Groq | Requests per day | Rate-limit headers from a one-token request, at most every 30 minutes |
| Ollama Cloud | Included credits this month | Account balance endpoint |
| Cloudflare | Free neurons per day | GraphQL analytics, against the published 10,000 per day allowance |
| Google AI Studio | Requests per day | Limits from your Google project, usage counted from OpenCode history |
| NVIDIA | Requests per minute | Counted from OpenCode history against a 40 per minute estimate |

Usage for Google and NVIDIA only counts requests made through OpenCode on this Mac.

## Requirements

- macOS 26 or later
- Xcode 26 or a Swift 6.2 toolchain, to build
- At least one of `agy`, `claude`, `opencode` or `gcloud`, installed and signed in

## Build and run

```sh
git clone https://github.com/bpmiranda3099/ai-usage-bar-macos.git
cd ai-usage-bar-macos
swift build -c release
swift run -c release AIAgentsUsageBar
```

### Run at login

`deploy.sh` builds the app, copies it to `~/Library/Application Support/AIAgentsUsageBar` and restarts a LaunchAgent. Create the agent first, at `~/Library/LaunchAgents/com.bpmiranda3099.aiagentsusagebar.plist`, replacing `YOU` with your user name (or change the label in `deploy.sh`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.bpmiranda3099.aiagentsusagebar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOU/Library/Application Support/AIAgentsUsageBar/AIAgentsUsageBar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

Then run `./deploy.sh`.

## Configuration

Most meters need nothing. Two need a one-time setup:

- **Google AI Studio:** run `gcloud auth login`, then save your project id in `~/.config/ai-agents-usage-bar/settings.json`:

  ```json
  { "googleProjectId": "your-project-id" }
  ```

- **Cloudflare:** the API token OpenCode uses needs the Account Analytics Read permission. See the [Cloudflare token guide](https://developers.cloudflare.com/analytics/graphql-api/getting-started/authentication/api-token-auth/).

## Privacy

- API keys are read from OpenCode's local database (read-only), used in memory for one request, and never stored or logged.
- Each key is sent only to its own provider's host. There is no telemetry and the app opens no ports.
- Details and the security review are in [SECURITY.md](SECURITY.md).

## Development

```sh
swift test
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the layout and how to add a provider, and [CONTRIBUTING.md](CONTRIBUTING.md) for branch, commit and pull request rules.

## License

[MIT](../LICENSE)

## Notices and sources

Claude, Antigravity, Google, OpenCode, NVIDIA, Groq, Cloudflare, OpenRouter, Ollama, DeepSeek and the other names and logos shown belong to their owners. They are used only to identify the services being measured, are not covered by the MIT license, and this project is not affiliated with or endorsed by any of them.

The app bundles no third-party code. Numbers and endpoints come from these references:

- Cloudflare: [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) (10,000 neurons per day) and [GraphQL analytics tokens](https://developers.cloudflare.com/analytics/graphql-api/getting-started/authentication/api-token-auth/)
- OpenRouter: [limits](https://openrouter.ai/docs/api/reference/limits)
- Groq: [rate limits](https://console.groq.com/docs/rate-limits)
- Google: [Service Usage API, consumerQuotaMetrics](https://docs.cloud.google.com/service-usage/docs/reference/rest/v1beta1/services.consumerQuotaMetrics)
- NVIDIA: the 40 requests per minute figure is reported by users, for example in this [developer forum thread](https://forums.developer.nvidia.com/t/request-for-nvidia-nim-api-rate-limit-increase-40-200-rpm/378915). NVIDIA does not publish it.
- Ollama: the balance endpoint is not publicly documented. It is described in the [opencode-quota provider notes](https://github.com/slkiser/opencode-quota/blob/main/docs/readme/providers.md).
- OpenCode's model list and prices come from the local catalog it downloads from [models.dev](https://models.dev).
