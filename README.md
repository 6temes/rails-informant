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
    &#9670; <a href="#browser-errors">Browser Errors</a>
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

With [Rails Hyperdrive](https://github.com/rails-hyperdrive/rails-hyperdrive), the `/informant` skill arrives through `bin/rails hyperdrive:sync` instead, and the generator installs the rest (see [With Rails Hyperdrive](#with-rails-hyperdrive)).

Optionally, capture JavaScript errors from your pages too (see [Browser Errors](#browser-errors)):

```sh
bin/rails generate rails_informant:browser
bin/rails db:migrate
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
| `browser_new_group_limit` | `INFORMANT_BROWSER_NEW_GROUP_LIMIT` | `50` | Most new browser error groups created per hour; reports that would start another are dropped |
| `capture_browser_errors` | `INFORMANT_CAPTURE_BROWSER_ERRORS` | `false` | Accept JavaScript error reports from your pages |
| `capture_errors` | `INFORMANT_CAPTURE_ERRORS` | `true` | Enable/disable error capture |
| `capture_runner_errors` | `INFORMANT_CAPTURE_RUNNER_ERRORS` | `true` | Capture errors raised under `rails runner` |
| `capture_user_email` | _(none)_ | `false` | Capture email from detected user (PII -- opt-in) |
| `ignored_exceptions` | `INFORMANT_IGNORED_EXCEPTIONS` | `[]` | Exception classes to skip (walks cause chain) |
| `ignored_paths` | `INFORMANT_IGNORED_PATHS` | `[]` | Request paths to skip (exact or segment match) |
| `job_attempt_threshold` | `INFORMANT_JOB_ATTEMPT_THRESHOLD` | `nil` | Suppress job failures until the Nth attempt (handled reports are always recorded) |
| `retention_days` | `INFORMANT_RETENTION_DAYS` | `nil` | Auto-purge resolved errors after N days |
| `slack_webhook_url` | `INFORMANT_SLACK_WEBHOOK_URL` | `nil` | Slack incoming webhook URL |
| `spike_protection` | _(none)_ | `nil` | Rate-limit per error group: `{ threshold: 50, window: 1.minute }` |
| `webhook_url` | `INFORMANT_WEBHOOK_URL` | `nil` | Generic webhook URL for notifications |

> **Connecting the tokens:** The `api_token` in your Rails credentials and `INFORMANT_PRODUCTION_TOKEN` must be the **same value**. The first authenticates incoming requests to your app; the second tells the MCP server what token to send.

## Noise Suppression

### Default Ignored Exceptions

Informant ignores only exceptions that are noise in **every** context: `SignalException`
and `SystemExit` (process control), plus a few client/tamper errors
(`Rack::Utils::InvalidParameterError`, `Mime::Type::InvalidMimeType`,
`CGI::Session::CookieStore::TamperedWithCookie`).

It deliberately does **not** ignore Rails' HTTP client errors -- `RecordNotFound`,
`RoutingError`, `ParameterMissing`, and the rest of the 4xx family. On the request path
Rails already maps those to responses (404, 422, ...) and never reports them to
`Rails.error`, so suppressing them again here was redundant. Off the request path -- in a
**background job**, a rake task, or wrapped as the cause of another error -- those same
exceptions are real bugs, so Informant records them. A job that dies on an
`ActiveJob::DeserializationError` caused by a missing record now alerts instead of
vanishing silently.

Add your own classes with `config.ignored_exceptions`; it still walks the cause chain, so
ignoring a class also ignores exceptions that wrap it.

### Third-Party Browser Errors

Browser errors from extensions, in-app browsers and injected scripts are recorded as `ignored` groups, so they stay visible in `list_errors` but never post to Slack or a webhook. Their notes say why, starting with `Auto-ignored:`, which tells them apart from groups a person ignored. The rules are under [What is captured](#what-is-captured).

If one of them is your own bug, reopen it with `reopen_error` or `PATCH /informant/api/v1/errors/:id` with `{"status": "unresolved"}`. Later reports keep it open and notify as usual. A purged or deleted group comes back as `ignored` on its next report.

### Interactive Console

Informant never captures errors raised in an interactive `rails console` session -- nothing
is recorded and no notifications are sent. You see exceptions live at the prompt, so
recording and alerting on them would only be noise. This is always on and not configurable.
Errors from web requests, background jobs, and rake tasks are captured as normal.

### Rails Runner

`rails runner` is captured by default, because it is how many apps run cron and scheduled
tasks -- exactly the errors you want to hear about. If your app instead uses it by hand, for
one-off production data corrections, the operator already sees the exception on their own
terminal and recording it only pages the team:

```ruby
config.capture_runner_errors = false
```

That applies only to `rails runner`; requests, jobs and rake tasks are captured either way.

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

The `event` exposes: `error`, `error_class`, `message`, `severity`, `controller_action`, `job_class`, `request_path`, `source` (`"server"` or `"browser"`), `fingerprint`. Callbacks that raise are logged and skipped.

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

## Browser Errors

Informant can also record JavaScript errors from your pages, so the agent triages them with the same tools and lifecycle as server errors. It is off by default.

### What is captured

- Uncaught errors and unhandled promise rejections, including errors thrown in Stimulus controllers
- Turbo failures that point to an app defect, such as a frame response missing its matching frame. Network failures (offline, aborted requests) are not reported. An aborted fetch that still surfaces as an `AbortError` is recorded as an `ignored` group and never notifies.

Identical errors are reported once per short window, and each page view has a report budget that resets on every Turbo visit. The client drops cross-origin `Script error.`, the ResizeObserver loop warning, and reports whose top frame comes from another origin.

The server records every other report, but errors from browser extensions and injected scripts land as `ignored` groups that never notify (see [Third-Party Browser Errors](#third-party-browser-errors)):

- A report is third-party when none of its frames comes from your origin, or when its only same-origin frames are on line 1 of the page, where extensions and in-app browsers inject their scripts.
- A report with no frames is third-party when its stack has lines that are not frames, or when it is an uncaught error with no stack at all. Frameless promise rejections and Turbo failures stay loud, and so does a stack holding only the error's own header line, which is how Chrome reports a syntax error.
- `JS::AbortError` is always silenced.

Two limits come with this. An error on line 1 of the page is silenced even when it is yours: that covers pages whose HTML is minified onto one line, and your own inline scripts after a Turbo visit, because Turbo re-creates them and their line numbers then count from the start of the script. And silenced groups count toward `browser_new_group_limit`, so a flood of distinct third-party errors can fill the hourly cap.

Browser groups are named `JS::<Name>` (for example `JS::TypeError`) and tagged with `source: "browser"`. They are grouped by error name and the first frame in your own JavaScript (files under `app/javascript/`), so a new asset digest, host, line or column does not start a new group. The message is used only when the stack has no app frame. Frames name your source files, not digested asset URLs.

Browser reports go through the same `ignored_exceptions` (use the `JS::` name), `ignored_paths` (matched against the page path), `before_record` callbacks, spike protection and notifications as server errors.

A resolved browser group reopens only on a report from a page rendered after it was resolved. A report from an older open tab, or one with no verifiable render time, does not reopen it.

### Setup

```sh
bin/rails generate rails_informant:browser
bin/rails db:migrate
```

Then restart the app. The generator is safe to re-run. It:

- writes a migration adding the browser columns (skipped when they already exist)
- adds `pin "rails_informant"` to `config/importmap.rb`
- inserts `<%= informant_browser_tag %>` before `javascript_importmap_tags` in `app/views/layouts/application.html.erb`
- sets `config.capture_browser_errors = true` in the initializer

The tag renders nothing while capture is off, so it can stay in the layout.

### Requirements and caveats

- Supported setup: importmap and Propshaft, with your JavaScript served from the same origin as the app. Bundled or minified builds (jsbundling, esbuild, Vite) and frontends served from another origin are not supported.
- Content Security Policy: the tag's inline script carries the request's CSP nonce, and `connect-src 'self'` already covers the endpoint.
- The tag finds the endpoint through the engine's `rails_informant` route helper. Mounting the engine with a custom `as:` name renames that helper and breaks the tag.
- Mounting the engine inside an authentication constraint blocks reports from signed-out pages.
- Until the migration has run, the endpoint answers 503 and logs which generator to run.
- Keep `informant_browser_tag` out of cached output (HTTP or CDN page caching, or a cached layout fragment). The tag carries the signed-in user for the request that rendered it, so a cached copy attributes every visitor's errors to that user for up to 24 hours.
- On PostgreSQL with a very large `informant_occurrences` table, the migration's index builds block error recording while they run. Run it in a quiet window, or change the generated migration to add the indexes with `algorithm: :concurrently` (and `disable_ddl_transaction!`).

### The endpoint

The client posts to `POST <mount path>/browser_reports` (for example `/informant/browser_reports`). The route exists only while `capture_browser_errors` is on. It takes no token: it accepts only same-origin requests, checked with `Sec-Fetch-Site` and, when a browser does not send that header, `Origin`.

Each request is bounded:

- 30 requests per minute per IP, via Rails `rate_limit` on your app's `Rails.cache`. Under `:null_store` the limit does nothing. Behind a proxy or CDN that Rails does not trust (see `config.action_dispatch.trusted_proxies`), every visitor has the same IP and shares one limit.
- 64 KB request body and 10 reports per request
- `browser_new_group_limit` new browser groups per hour. Once the cap is full, Informant records a `RailsInformant::BrowserGroupLimitReached` warning group, which alerts like any other error, so a flood of noise cannot silently hide a new bug. Silenced third-party groups count toward the cap too.

### What the client sends

- Error name, message and stack
- The page URL, without its fragment
- The last 20 breadcrumbs: Turbo visits, clicks, and failing requests with their status and `X-Request-Id`. A click is recorded by element identity (tag, `id`, `data-controller`, `data-action`) and never by its text.
- The request ID of the last failing request
- An encrypted context the server wrote into the page when it rendered it: the user, the rendering request's ID, the app revision and the render time. The page cannot read or change it.

The user on a browser occurrence always comes from that server-written context. Nothing in a report can set it.

### Following a browser error to the server

A browser occurrence records `request_id` (the request that rendered the page) and `failing_request_id` (the last request that failed). The `list_occurrences` MCP tool takes a `request_id` filter that matches either, so the agent can find the server occurrence for the same request. A miss is normal: the request may have raised nothing on the server, and cooldown and trimming drop repeat server occurrences. `list_errors` takes a `source` filter (`browser` or `server`) and lists both by default.

## MCP Server

The bundled `informant-mcp` executable connects Claude Code to your error data via [Model Context Protocol](https://modelcontextprotocol.io).

### Setup

The `rails_informant:skill` generator creates `.mcp.json` automatically. Set `INFORMANT_PRODUCTION_URL` and `INFORMANT_PRODUCTION_TOKEN` as environment variables (e.g., via `.envrc` + direnv).

`informant-mcp` reads these variables when it starts, so a Claude Code session started without them loaded crashes the server on boot. To load `.envrc` on every start, launch the server through direnv. The generator and `informant:doctor` both accept this entry:

```json
"informant": { "command": "direnv", "args": ["exec", ".", "informant-mcp"] }
```

For multi-environment setups, add env vars for each environment:

```bash
export INFORMANT_PRODUCTION_URL=https://myapp.com
export INFORMANT_PRODUCTION_TOKEN=<token>
export INFORMANT_STAGING_URL=https://staging.myapp.com
export INFORMANT_STAGING_TOKEN=<token>
```

### Keeping it in sync

The generator's output (`.claude/`, `.mcp.json`) is committed to your app, so a gem update leaves those files untouched. After `bundle update rails-informant`, re-run the generator and commit the result to pick up template changes:

```sh
bin/rails generate rails_informant:skill
```

Re-running migrates any prior hook registration in place, so there are no duplicates. The gem also flags drift when the committed files fall behind the installed version — via a warning on dev boot, an in-session Claude Code nudge, and an on-demand check:

```sh
bin/rails informant:doctor   # reports current / stale / not installed; exits nonzero when stale
```

Apps that use the gem only for error capture (no Claude Code integration) are never affected.

#### With Rails Hyperdrive

rails-informant is a Hyperdrive companion gem. Once an app has `.hyperdrive/config.yml`, Hyperdrive owns the skill (`.claude/skills/informant/SKILL.md`) and updates it on `bin/rails hyperdrive:sync`, keeping your local edits safe. The generator still owns the hook script, its `.claude/settings.json` entry and `.mcp.json`, and no longer writes the skill. The drift checks ignore the skill in these apps.

If the generator installed the skill before Hyperdrive arrived, hand it over once:

```sh
rm -f .claude/skills/informant/SKILL.md .claude/skills/informant/SKILL.md.new
bin/rails hyperdrive:sync
```

Hyperdrive treats a file it did not install as a local edit and never overwrites it, so the old copy has to go first. Avoid `hyperdrive:sync --overwrite` for this: it rewrites every locally edited Hyperdrive file, from every companion gem. `bin/rails informant:doctor` prints these steps while the handover is pending.

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
(new)       --> ignored (third-party browser report)
unresolved --> duplicate
resolved    --> unresolved [REGRESSION]
```

## Data and Privacy

Occurrences store: user ID (always), email (opt-in via `capture_user_email`), IP address, and custom context. All context passes through `ActiveSupport::ParameterFilter` -- add keys to `filter_parameters` to suppress them.

```ruby
RailsInformant::Current.user_context = { id: current_user.id }
```

Browser occurrences store the same user context, taken from the page's encrypted render-time context rather than from the report. Their page URL, breadcrumbs and context pass through `filter_parameters` like server request data, and click breadcrumbs never include visible text.

## Security

- Token authentication (`secure_compare`), HTTPS enforced by default
- All context filtered through `ActiveSupport::ParameterFilter`
- Security headers: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`
- Error capture never breaks the host application
- The browser endpoint (`/informant/browser_reports`, only while `capture_browser_errors` is on) is unauthenticated: it accepts same-origin requests only and is rate limited per IP with Rails `rate_limit`. A scripted client can forge those headers, so every report is size-bounded and new browser groups are capped per hour.
- Text in browser groups (message, frames, breadcrumbs, URLs) is written by anonymous visitors. The MCP instructions and skill tell the agent to treat it as data, never as instructions, and the MCP instructions have the agent ask you before it edits files, commits, opens a PR or runs commands beyond read-only git and your tests for work that started from a browser group.
- The API has no built-in rate limiting -- use [Rack::Attack](https://github.com/rack/rack-attack) on `/informant/api/`

## Development

```sh
bin/test                                  # Ruby suite
node --test 'test/javascript/*.test.js'   # browser client
```

The JavaScript tests use Node's built-in runner with no npm dependencies, and need Node 22.12 or later. Pass the quoted glob: Node 24 does not run a bare directory argument.

## License

MIT License -- see [LICENSE](LICENSE).

---

<div align="center">
  <sub>Made in Tokyo with &#10084;&#65039; and &#129302;</sub>
</div>
