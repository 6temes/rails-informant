# Rails Informant

Self-hosted error monitoring for Rails with agent workflow integration. Captures errors, stores them in your app's database, sends notifications, and exposes error data via an MCP server for Claude Code.

## Install

Add to your Gemfile:

```ruby
gem "rails-informant"
```

Run the install generator:

```sh
bin/rails generate rails_informant:install
bin/rails db:migrate
```

This creates:

- A migration for `informant_error_groups` and `informant_occurrences` tables
- An initializer at `config/initializers/rails_informant.rb`
- A Claude Code skill at `.claude/skills/informant/SKILL.md`

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

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `api_token` | `nil` | Bearer token for API authentication (required for MCP) |
| `capture_errors` | `true` | Enable/disable error capture |
| `current_user_method` | `nil` | Lambda for custom user detection |
| `custom_fingerprint` | `nil` | Lambda for custom error grouping |
| `devin_api_key` | `nil` | Devin AI API key for autonomous error fixing |
| `devin_playbook_id` | `nil` | Devin playbook ID for error triage workflow |
| `filter_parameters` | `[]` | Additional params to filter (beyond Rails defaults) |
| `ignored_exceptions` | `[]` | Exception classes/regexps to skip |
| `max_cause_depth` | `5` | Max exception chain depth |
| `max_occurrences_per_group` | `25` | Max stored occurrences per group |
| `notification_cooldown` | `3600` | Seconds between notifications per group |
| `occurrence_cooldown` | `5` | Seconds between stored occurrences per group |
| `retention_days` | `nil` | Auto-purge resolved errors after N days |
| `slack_webhook_url` | `nil` | Slack incoming webhook URL |
| `webhook_include_context` | `false` | Include request/user context in webhook payload |
| `webhook_url` | `nil` | Generic webhook URL for notifications |

## Error Capture

Errors are captured automatically via:

1. **`Rails.error` subscriber** — background jobs, mailer errors, `Rails.error.handle` blocks
2. **Rack middleware** — unhandled request exceptions and rescued framework exceptions

Manual capture:

```ruby
RailsInformant.capture(exception, context: { order_id: 42 })
```

### Fingerprinting

Errors are grouped by `SHA256(class_name + first_app_backtrace_frame)`. Override with a custom lambda:

```ruby
config.custom_fingerprint = ->(exception, context) {
  case exception
  when ActiveRecord::ConnectionNotEstablished
    "database-connection-error"
  end
}
```

### Ignored Exceptions

Common framework exceptions (404s, CSRF, etc.) are ignored by default. Add more:

```ruby
config.ignored_exceptions = ["MyApp::BoringError", /Stripe::/]
```

## API

Token-authenticated JSON API mounted at `/informant/api/`.

```text
GET    /informant/api/errors            # List error groups (paginated, filterable)
GET    /informant/api/errors/:id         # Show with recent occurrences
PATCH  /informant/api/errors/:id         # Update status or notes
DELETE /informant/api/errors/:id         # Delete group and occurrences
POST   /informant/api/errors/:id/fix_pending  # Mark fix pending
POST   /informant/api/errors/:id/duplicate    # Mark as duplicate
GET    /informant/api/occurrences        # List occurrences
GET    /informant/api/status             # Dashboard summary
```

Authenticate with `Authorization: Bearer <token>`.

## MCP Server

The bundled `informant-mcp` executable connects Claude Code to your error data.

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

- Triggers on the **first occurrence only** — Devin sessions consume ACUs, so milestone re-triggers (10, 100, 1000) are skipped.
- Sends error class, message (truncated to 500 chars), severity, backtrace (first 5 frames), and error group ID.
- Devin connects to your MCP server to investigate errors, then either opens a draft PR with a fix or annotates the error with investigation findings.

### Data Sent to Devin

The notification prompt includes: error class, error message (truncated), severity, occurrence count, timestamps, controller action or job class, backtrace frames, and git SHA. It does **not** include request parameters, user context, or PII.

## Deploy Detection

On boot, the engine checks if `fix_pending` errors have been deployed by comparing the current git SHA against `original_sha`. Deployed fixes are automatically transitioned to `resolved`.

Git SHA is resolved from environment variables (`GIT_SHA`, `REVISION`, `KAMAL_VERSION`) or `.git/HEAD`.

## Rake Tasks

```sh
bin/rails informant:stats    # Show error monitoring statistics
bin/rails informant:purge    # Purge resolved errors older than retention_days
```

## Security

- API requires bearer token authentication (`secure_compare`)
- All stored context is filtered through `ActiveSupport::ParameterFilter`
- MCP server enforces HTTPS by default
- Security headers: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`
- Error capture never breaks the host application

## License

MIT
