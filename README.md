<div align="center">

  <h1 style="margin-top: 10px;">Rails Informant</h1>

  <h2>Self-hosted error monitoring for Rails, built for AI agents</h2>

  <div align="center">
    <a href="https://github.com/6temes/rails-informant/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green"/></a>
    <a href="https://www.ruby-lang.org/"><img alt="Ruby" src="https://img.shields.io/badge/ruby-4.0+-red.svg"/></a>
    <a href="https://rubyonrails.org/"><img alt="Rails" src="https://img.shields.io/badge/rails-8.1+-red.svg"/></a>
  </div>

  <p>
    <a href="#why-rails-informant">Why Rails Informant?</a>
    &#9670; <a href="#quick-start">Quick Start</a>
    &#9670; <a href="#configuration">Configuration</a>
    &#9670; <a href="#mcp-server">MCP Server</a>
    &#9670; <a href="#architecture">Architecture</a>
    &#9670; <a href="#data--privacy">Data & Privacy</a>
    &#9670; <a href="#security">Security</a>
  </p>
</div>

---

Captures exceptions, stores them in your app's database with rich context (backtraces, breadcrumbs, request data), sends notifications, and exposes error data via a bundled MCP server -- so Claude Code and Devin AI can query, triage, and fix production errors directly.

No dashboard. The agent *is* the interface.

## Why Rails Informant?

- **Agent-native** -- 12 MCP tools let AI agents list, inspect, resolve, and fix errors without a browser. The `/informant` Claude Code skill provides a complete triage-to-fix workflow.
- **Self-hosted** -- Errors stay in your database. No external service, no data leaving your infrastructure (unless you configure Slack, webhook, or Devin notifications).
- **Zero-config capture** -- Errors captured automatically via `Rails.error` subscriber and Rack middleware. Breadcrumbs from `ActiveSupport::Notifications` provide structured debugging context.
- **Autonomous fixing** -- Devin AI integration triggers investigation sessions on new errors, writes fixes with tests, and opens draft PRs. Humans retain the merge button.
- **Lightweight** -- Two database tables, no Redis, no background workers beyond ActiveJob. Runtime dependencies: Rails 8.1+ only.

## Quick Start

Add to your Gemfile:

```ruby
gem "rails-informant"
```

Run the install generator:

```sh
bin/rails generate rails_informant:install
bin/rails db:migrate
```

This creates a migration for `informant_error_groups` and `informant_occurrences` tables, an initializer at `config/initializers/rails_informant.rb`, and mounts the engine at `/informant`.

Optional generators for AI agent integration:

```sh
bin/rails generate rails_informant:skill   # Claude Code skill at .claude/skills/informant/SKILL.md
bin/rails generate rails_informant:devin   # Devin playbook at .devin/error-triage.devin.md
```

Errors are captured automatically in non-local environments. To capture errors manually:

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

Every option can be set via an environment variable. The initializer takes precedence over env vars.

| Option | Env var | Default | Description |
|--------|---------|---------|-------------|
| `api_token` | `INFORMANT_API_TOKEN` | `nil` | Bearer token for API authentication (required for MCP) |
| `capture_errors` | `INFORMANT_CAPTURE_ERRORS` | `true` | Enable/disable error capture (set to `"false"` to disable) |
| `devin_api_key` | `INFORMANT_DEVIN_API_KEY` | `nil` | Devin AI API key for autonomous error fixing |
| `devin_playbook_id` | `INFORMANT_DEVIN_PLAYBOOK_ID` | `nil` | Devin playbook ID for error triage workflow |
| `ignored_exceptions` | `INFORMANT_IGNORED_EXCEPTIONS` | `[]` | Exception classes to skip (comma-separated in env var) |
| `retention_days` | `INFORMANT_RETENTION_DAYS` | `nil` | Auto-purge resolved errors after N days |
| `slack_webhook_url` | `INFORMANT_SLACK_WEBHOOK_URL` | `nil` | Slack incoming webhook URL |
| `capture_user_email` | _(none)_ | `false` | Capture email from detected user (PII -- opt-in) |
| `webhook_url` | `INFORMANT_WEBHOOK_URL` | `nil` | Generic webhook URL for notifications |

## Error Capture

Errors are captured automatically via:

1. **`Rails.error` subscriber** -- background jobs, mailer errors, `Rails.error.handle` blocks
2. **Rack middleware** -- unhandled request exceptions and rescued framework exceptions

### Fingerprinting

Errors are grouped by `SHA256(class_name:first_app_backtrace_frame)`. Line numbers are normalized so the same error at different lines groups together.

### Ignored Exceptions

Common framework exceptions (404s, CSRF, etc.) are ignored by default. Add more:

```ruby
config.ignored_exceptions = ["MyApp::BoringError", /Stripe::/]
```

### Breadcrumbs

Structured events from `ActiveSupport::Notifications` are captured automatically as breadcrumbs -- SQL query names, cache hits, template renders, HTTP calls, job executions. Stored per-occurrence for rich debugging context without raw log lines.

## API

Token-authenticated JSON API mounted at `/informant/api/v1/`.

```text
GET    /informant/api/v1/errors            # List error groups (paginated, filterable)
GET    /informant/api/v1/errors/:id         # Show with recent occurrences
PATCH  /informant/api/v1/errors/:id         # Update status or notes
DELETE /informant/api/v1/errors/:id         # Delete group and occurrences
PATCH  /informant/api/v1/errors/:id/fix_pending  # Mark fix pending
PATCH  /informant/api/v1/errors/:id/duplicate    # Mark as duplicate
GET    /informant/api/v1/occurrences        # List occurrences
GET    /informant/api/v1/status             # Error monitoring summary
```

Authenticate with `Authorization: Bearer <token>`.

## MCP Server

The bundled `informant-mcp` executable connects Claude Code to your error data via [Model Context Protocol (MCP)](https://modelcontextprotocol.io).

The MCP server requires the `mcp` gem, which is not a runtime dependency. Add it to your Gemfile:

```ruby
gem "mcp", ">= 0.7", "< 2"
```

### Setup

Add to your Claude Code MCP config:

```json
{
  "mcpServers": {
    "informant": {
      "command": "informant-mcp",
      "env": {
        "INFORMANT_PRODUCTION_URL": "https://myapp.com",
        "INFORMANT_PRODUCTION_TOKEN": "your-api-token"
      }
    }
  }
}
```

Or create `~/.config/informant-mcp.yml` for multi-environment setups:

```yaml
environments:
  production:
    url: https://myapp.com
    token: ${INFORMANT_PRODUCTION_TOKEN}
  staging:
    url: https://staging.myapp.com
    token: ${INFORMANT_STAGING_TOKEN}
```

### Tools

| Tool | Description |
|------|-------------|
| `list_environments` | List configured environments |
| `list_errors` | List error groups with filtering and pagination |
| `get_error` | Full error detail with recent occurrences |
| `resolve_error` | Mark as resolved |
| `ignore_error` | Mark as ignored |
| `reopen_error` | Reopen a resolved/ignored error |
| `mark_fix_pending` | Mark with fix SHA for auto-resolve on deploy |
| `mark_duplicate` | Mark as duplicate of another group |
| `delete_error` | Delete group and occurrences |
| `annotate_error` | Add investigation notes |
| `get_informant_status` | Summary with counts and top errors |
| `list_occurrences` | List occurrences with filtering |

## Claude Code Skill

Use `/informant` in Claude Code to triage and fix errors interactively. The skill:

1. Checks error status with `get_informant_status`
2. Lists unresolved errors
3. Investigates with full occurrence data
4. Implements fixes with test-first workflow
5. Marks `fix_pending` for auto-resolution on deploy

## Devin AI

Automate error investigation and fixing with [Devin AI](https://devin.ai). When a new error is captured, Rails Informant creates a Devin session that investigates via MCP tools, writes a fix with tests, and opens a draft PR.

### Setup

1. Add the `informant-mcp` server to Devin's [MCP Marketplace](https://docs.devin.ai/work-with-devin/mcp) with your API URL and token.

2. Upload the playbook installed at `.devin/error-triage.devin.md` to Devin and note the playbook ID. See [Creating Playbooks](https://docs.devin.ai/product-guides/creating-playbooks).

3. Configure Rails Informant:

```ruby
RailsInformant.configure do |config|
  config.devin_api_key = Rails.application.credentials.dig(:rails_informant, :devin_api_key)
  config.devin_playbook_id = "your-playbook-id"
end
```

### How It Works

- Triggers on the **first occurrence only** -- repeated occurrences of the same error do not create additional Devin sessions.
- Sends error class, message (truncated to 500 chars), severity, backtrace (first 5 frames), and error group ID.
- Devin connects to your MCP server to investigate errors, then either opens a draft PR with a fix or annotates the error with investigation findings.

### Data Sent to Devin

The notification prompt includes: error class, error message (truncated), severity, occurrence count, timestamps, controller action or job class, backtrace frames, and git SHA. It does **not** include request parameters, user context, or PII.

## Architecture

```text
Development Machine                    Remote Servers
+-----------------------+              +-----------------------+
|  Claude Code          |              |  Production           |
|        |              |              |  /informant/api/v1    |
|        | stdio        |              +-----------------------+
|        v              |  HTTPS+Token
|  MCP Server           | -----------> +-----------------------+
|  (exe/informant-mcp)  |              |  Staging              |
|                       |              |  /informant/api/v1    |
+-----------------------+              +-----------------------+

Inside the Rails app:
+-------------------------------------------------+
|  Rails.error subscriber (primary capture)       |
|  Rack Middleware (safety net)                    |
|    - ErrorCapture (before ShowExceptions)        |
|    - RescuedExceptionInterceptor (after Debug)   |
|  |                                              |
|  v                                              |
|  Fingerprint + Upsert (atomic counter)          |
|  |                                              |
|  v                                              |
|  Occurrence.create (with breadcrumbs, context)  |
|  |                                              |
|  v                                              |
|  NotifyJob.perform_later (async dispatch)       |
|    - Slack (Block Kit, Net::HTTP)               |
|    - Webhook (PII stripped by default)          |
|    - Devin AI (creates investigation session)   |
+-------------------------------------------------+
```

### Error Group Lifecycle

```text
unresolved --> fix_pending --> resolved (auto, on deploy)
unresolved --> resolved (manual)
unresolved --> ignored
unresolved --> duplicate
resolved    --> unresolved [REGRESSION]
fix_pending --> unresolved (reopen)
ignored     --> unresolved (reopen)
duplicate   --> unresolved (reopen)
```

## Deploy Detection

On boot, the engine checks if `fix_pending` errors have been deployed by comparing the current git SHA against `original_sha`. Deployed fixes are automatically transitioned to `resolved`.

Git SHA is resolved from environment variables (`GIT_SHA`, `REVISION`, `KAMAL_VERSION`) or `.git/HEAD`.

## Rake Tasks

```sh
bin/rails informant:stats    # Show error monitoring statistics
bin/rails informant:purge    # Purge resolved errors older than retention_days
```

## Data & Privacy

Each occurrence stores the following PII:

- **User email** -- only captured when `config.capture_user_email = true` and the user model responds to `#email`
- **IP address** -- from `request.remote_ip`
- **Custom user context** -- anything set via `RailsInformant::Current.user_context`

For GDPR compliance, only include identifiers needed for debugging (e.g., user ID) rather than personal data. You can override automatic user detection by setting user context explicitly:

```ruby
# In a before_action or around_action
RailsInformant::Current.user_context = { id: current_user.id }
```

All stored context passes through `ActiveSupport::ParameterFilter`, so adding keys to `filter_parameters` suppresses them:

```ruby
# config/application.rb
config.filter_parameters += [:email]
```

This replaces email values with `[FILTERED]` in occurrence data. IP addresses can be suppressed the same way by adding `:ip`.

## Security

- API requires bearer token authentication (`secure_compare`)
- All stored context is filtered through `ActiveSupport::ParameterFilter`
- MCP server enforces HTTPS by default
- Security headers: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`
- Error capture never breaks the host application
- Webhook payloads strip PII by default
- **Rate limiting** -- the API does not include built-in rate limiting. Add rate limiting on the `/informant/api/` prefix in production, for example with [Rack::Attack](https://github.com/rack/rack-attack):

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("informant/api", limit: 60, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/informant/api/")
end
```

## License

This project is licensed under the **MIT License** -- see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <sub>Made in Tokyo with &#10084;&#65039; and &#129302;</sub>
</div>
