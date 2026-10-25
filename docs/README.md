# AI Usage Bar

A macOS menu bar app that shows remaining usage limits for Antigravity, Claude Code and OpenCode.

## Usage

Click the menu bar icon to open the panel. Hover a row label to see the models it covers. Click a section header to collapse it. Data refreshes every 5 minutes. A section is hidden if its tool is missing or fails.

| Section | Tool | Shows |
|---|---|---|
| Antigravity | `agy` | 5 hour and weekly limits per model group |
| Claude | `claude` | Session and weekly limits, and per-model weekly limits where the plan has them |
| OpenCode | `opencode` | Free models of the connected providers |

### OpenCode providers

Only free models are listed. Providers with a readable limit get a meter. All others share one "Other providers" row.

| Provider | Meter | Source |
|---|---|---|
| OpenRouter | Free-model requests per day | Key info endpoint |
| Groq | Requests per day | Rate-limit response headers |
| Ollama Cloud | Included credits per month | Balance endpoint |
| Cloudflare | Free neurons per day | GraphQL analytics |
| Google AI Studio | Requests per day | Project quota limits, usage from OpenCode history |
| NVIDIA | Requests per minute | OpenCode history against a 40 per minute estimate |

Google and NVIDIA usage only counts requests made through OpenCode on this Mac.

## Requirements

- macOS 26 or later
- Xcode 26 or a Swift 6.2 toolchain
- One or more of `agy`, `claude`, `opencode`, `gcloud`, installed and signed in

## Build and run

```sh
git clone https://github.com/bpmiranda3099/ai-usage-bar-macos.git
cd ai-usage-bar-macos
swift build -c release
swift run -c release AIAgentsUsageBar
```

## Run at login

`deploy.sh` builds the app, copies it to `~/Library/Application Support/AIAgentsUsageBar` and restarts a LaunchAgent. Create the agent first at `~/Library/LaunchAgents/com.bpmiranda3099.aiagentsusagebar.plist`, replacing `YOU` with your user name, or change the label in `deploy.sh`.

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

## Configuration

Google AI Studio: run `gcloud auth login`, then set the project id in `~/.config/ai-agents-usage-bar/settings.json`:

```json
{ "googleProjectId": "your-project-id" }
```

Cloudflare: the API token OpenCode uses needs the Account Analytics Read permission.

## Data and keys

API keys are read from OpenCode's local database, used for one request each, and not stored or logged. Each key is sent only to its own provider.

## Development

```sh
swift test
```

See [ARCHITECTURE.md](ARCHITECTURE.md) and [CONTRIBUTING.md](CONTRIBUTING.md). To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

[MIT](../LICENSE)

## Notices

Product names and logos belong to their owners. They are used only to identify the services shown, are not covered by the MIT license, and the owners are not affiliated with this project. No third-party code is bundled.

## References

- Cloudflare: [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/), [GraphQL analytics tokens](https://developers.cloudflare.com/analytics/graphql-api/getting-started/authentication/api-token-auth/)
- OpenRouter: [limits](https://openrouter.ai/docs/api/reference/limits)
- Groq: [rate limits](https://console.groq.com/docs/rate-limits)
- Google: [consumerQuotaMetrics](https://docs.cloud.google.com/service-usage/docs/reference/rest/v1beta1/services.consumerQuotaMetrics)
- NVIDIA: the 40 per minute figure is user-reported, for example in this [forum thread](https://forums.developer.nvidia.com/t/request-for-nvidia-nim-api-rate-limit-increase-40-200-rpm/378915). NVIDIA does not publish it.
- Ollama: the balance endpoint is undocumented. See the [opencode-quota provider notes](https://github.com/slkiser/opencode-quota/blob/main/docs/readme/providers.md).
- OpenCode model list and prices: [models.dev](https://models.dev)
