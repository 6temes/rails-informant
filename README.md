<div align="center">

  <h1 style="margin-top: 10px;">Rails Informant</h1>

  <h2>Self-hosted error monitoring for Rails, built for AI agents</h2>

  <div align="center">
    <a href="https://github.com/6temes/rails-informant/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green"/></a>
    <a href="https://www.ruby-lang.org/"><img alt="Ruby" src="https://img.shields.io/badge/ruby-4.0+-red.svg"/></a>
    <a href="https://rubyonrails.org/"><img alt="Rails" src="https://img.shields.io/badge/rails-8.1+-red.svg"/></a>
  </div>

  <p>
    <a href="#quick-start">Quick Start</a>
    &#9670; <a href="#configuration">Configuration</a>
    &#9670; <a href="#noise-suppression">Noise Suppression</a>
    &#9670; <a href="#mcp-server">MCP Server</a>
    &#9670; <a href="#data-and-privacy">Data and Privacy</a>
  </p>
</div>

---

Captures exceptions, stores them in your app's database with rich context (backtraces, breadcrumbs, request data), sends notifications, and exposes error data via a bundled MCP server -- so AI agents can query, triage, and fix production errors directly.

No dashboard. The agent *is* the interface.

- **Agent-native** -- 14 MCP tools let AI agents list, inspect, resolve, and fix errors without a browser.
- **Self-hosted** -- Errors stay in your database. No external service, no data leaving your infrastructure.
- **Zero-config capture** -- Automatic via `Rails.error` subscriber and Rack middleware. Breadcrumbs from `ActiveSupport::Notifications` provide structured debugging context.
- **Lightweight** -- Two database tables, no Redis, no background workers beyond ActiveJob.

## Quick Start

Add to your Gemfile:

```ruby
gem "rails-informant"
```

Install:

```sh
bundle install
bin/rails generate rails_informant:install
bin/rails db:migrate
```

Set an authentication token:

```sh
bin/rails credentials:edit
```

```yaml
rails_informant:
  api_token: your-secret-token  # generate with: openssl rand -hex 32
```

Install Claude Code integration:

```sh
bin/rails generate rails_informant:skill
```

Errors are captured automatically. To capture manually:

```ruby
RailsInformant.capture(exception, context: { order_id: 42 })
```

## Configuration

```ruby
# config/initializers/rails_informant.rb
RailsInformant.configure do |config|
  config.capture_errors = !Rails.env.local?
  config.api_token = Rails.application.credentials.dig(:rails_informant, :api_token)
  config.slack_webhook_url = Rails.application.credentials.dig(:rails_informant, :slack_webhook_url)
  config.retention_days = 30
end
```

Every option can be set via an environment variable. The initializer takes precedence.

| Option | Env var | Default | Description |
|--------|---------|---------|-------------|
| `api_token` | `INFORMANT_API_TOKEN` | `nil` | Authentication token for API/MCP access |
| `capture_errors` | `INFORMANT_CAPTURE_ERRORS` | `true` | Enable/disable error capture |
| `capture_user_email` | _(none)_ | `false` | Capture email from detected user (PII -- opt-in) |
| `ignored_exceptions` | `INFORMANT_IGNORED_EXCEPTIONS` | `[]` | Exception classes to skip (walks cause chain) |
| `ignored_paths` | `INFORMANT_IGNORED_PATHS` | `[]` | Request paths to skip (exact or segment match) |
| `job_attempt_threshold` | `INFORMANT_JOB_ATTEMPT_THRESHOLD` | `nil` | Suppress job errors until Nth retry |
| `retention_days` | `INFORMANT_RETENTION_DAYS` | `nil` | Auto-purge resolved errors after N days |
| `slack_webhook_url` | `INFORMANT_SLACK_WEBHOOK_URL` | `nil` | Slack incoming webhook URL |
| `spike_protection` | _(none)_ | `nil` | Rate-limit per error group: `{ threshold: 50, window: 1.minute }` |
| `webhook_url` | `INFORMANT_WEBHOOK_URL` | `nil` | Generic webhook URL for notifications |

> **Connecting the tokens:** The `api_token` in your Rails credentials and `INFORMANT_PRODUCTION_TOKEN` must be the **same value**. The first authenticates incoming requests to your app; the second tells the MCP server what token to send.

## Noise Suppression

### Silenced Blocks

```ruby
RailsInformant.silence do
  risky_operation_you_dont_care_about
end
```

Thread-safe via `CurrentAttributes`. Nesting is supported.

### Before Record Callbacks

Hook into the recording pipeline to filter, modify fingerprints, or override severity:

```ruby
config.before_record do |event|
  event.halt! if event.message.include?("timeout")
  event.fingerprint = "stripe-errors" if event.error_class.start_with?("Stripe::")
  event.severity = "warning" if event.error_class == "Net::ReadTimeout"
end
```

The `event` exposes: `error`, `error_class`, `message`, `severity`, `controller_action`, `job_class`, `request_path`, `fingerprint`. Callbacks that raise are logged and skipped.

### Custom Exception Context

Exceptions implementing `to_informant_context` have their context merged into occurrences automatically:

```ruby
class PaymentError < StandardError
  def to_informant_context
    { payment_id:, gateway: }
  end
end
```

### Deploy Auto-Resolve

Notify Informant of a deploy to auto-resolve stale errors (not seen in the last hour):

```sh
curl -X POST https://myapp.com/informant/api/v1/deploy \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sha": "abc1234"}'
```

Resolved errors automatically reopen on regression. Also available as the `notify_deploy` MCP tool.

## MCP Server

The bundled `informant-mcp` executable connects Claude Code to your error data via [Model Context Protocol](https://modelcontextprotocol.io).

### Setup

The `rails_informant:skill` generator creates `.mcp.json` automatically. Set `INFORMANT_PRODUCTION_URL` and `INFORMANT_PRODUCTION_TOKEN` as environment variables (e.g., via `.envrc` + direnv).

For multi-environment setups, add env vars for each environment:

```bash
export INFORMANT_PRODUCTION_URL=https://myapp.com
export INFORMANT_PRODUCTION_TOKEN=<token>
export INFORMANT_STAGING_URL=https://staging.myapp.com
export INFORMANT_STAGING_TOKEN=<token>
```

### Tools

| Tool | Description |
|------|-------------|
| `annotate_error` | Add investigation notes |
| `delete_error` | Delete group and occurrences |
| `get_error` | Full error detail with recent occurrences |
| `get_informant_status` | Summary with counts and top errors |
| `ignore_error` | Mark as ignored |
| `list_environments` | List configured environments |
| `list_errors` | List error groups with filtering and pagination |
| `list_occurrences` | List occurrences with filtering |
| `mark_duplicate` | Mark as duplicate of another group |
| `mark_fix_pending` | Mark with fix SHA for auto-resolve on deploy |
| `notify_deploy` | Notify of a deploy to auto-resolve stale errors |
| `reopen_error` | Reopen a resolved/ignored error |
| `resolve_error` | Mark as resolved |
| `verify_pending_fixes` | Check deployed fixes and auto-resolve verified ones |

### Local Development

The MCP server enforces HTTPS by default. For local HTTP URLs, pass `--allow-insecure`:

```json
{
  "mcpServers": {
    "informant": {
      "command": "informant-mcp",
      "args": ["--allow-insecure"]
    }
  }
}
```

## Architecture

```text
Development Machine                    Remote Servers
+-----------------------+              +-----------------------+
|  Claude Code          |              |  Production           |
|        |              |              |  /informant           |
|        | stdio        |              +-----------------------+
|        v              |  HTTPS+Token
|  MCP Server           | -----------> +-----------------------+
|  (exe/informant-mcp)  |              |  Staging              |
|                       |              |  /informant           |
+-----------------------+              +-----------------------+
```

### Error Group Lifecycle

```text
unresolved --> fix_pending --> resolved (auto, on deploy)
unresolved --> resolved (manual)
unresolved --> ignored
unresolved --> duplicate
resolved    --> unresolved [REGRESSION]
```

## Data and Privacy

Occurrences store: user ID (always), email (opt-in via `capture_user_email`), IP address, and custom context. All context passes through `ActiveSupport::ParameterFilter` -- add keys to `filter_parameters` to suppress them.

```ruby
RailsInformant::Current.user_context = { id: current_user.id }
```

## Security

- Token authentication (`secure_compare`), HTTPS enforced by default
- All context filtered through `ActiveSupport::ParameterFilter`
- Security headers: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`
- Error capture never breaks the host application
- No built-in rate limiting -- use [Rack::Attack](https://github.com/rack/rack-attack) on `/informant/`

## License

MIT License -- see [LICENSE](LICENSE).

---

<div align="center">
  <sub>Made in Tokyo with &#10084;&#65039; and &#129302;</sub>
</div>
