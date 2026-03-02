---
disable-model-invocation: true
allowed-tools:
  - mcp__informant__*
  - Bash(git *)
  - Bash(gh *)
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Bash(bin/test *)
  - Bash(bundle exec *)
---

# /informant [environment]

You investigate and resolve production errors using the Informant MCP tools.

## Quick Start

1. Run `get_informant_status` to understand the current error landscape
2. Run `list_errors(status: "unresolved")` to see what needs attention
3. Pick an error (or ask the user which to tackle if multiple exist)
4. Investigate with `get_error` for full context

## Assessment Criteria

When triaging errors, consider:
- **Frequency**: How often? Is it accelerating?
- **Impact**: Does it affect critical paths (checkout, auth, payments)?
- **Recency**: When did it first appear? Tied to a recent deploy?
- **Duplicates**: Does the backtrace overlap with another group?

## Resolution Strategies

Depending on the error, you might:
- Write a failing test + fix for clear bugs
- Mark as `ignored` for known/acceptable edge cases
- Mark as `duplicate` if backtrace overlaps with another group
- Add error handling for external service failures
- Flag data-dependent issues for human review
- Annotate with investigation findings for future reference

Use your judgment. Not every error needs a PR.

## Fix Workflow

When implementing a fix:
1. Create a feature branch
2. Check out the deployed commit (git SHA from occurrence) to analyze code as it was
3. Write a failing test reproducing the error
4. Implement the fix
5. Verify test passes
6. Commit + open draft PR
7. Call `mark_fix_pending` with fix_sha, original_sha, and fix_pr_url
   (The server auto-resolves when the fix is deployed)

## Pagination

List tools return paginated results (20 per page by default, max 100).
The response ends with a line like: `Page 1, per_page: 20, has_more: true`

When `has_more` is true, request the next page: `list_errors(page: 2)`
Always paginate through all results when counting or searching exhaustively.

## Date Filtering

Use `since` and `until` (ISO 8601) to scope searches:
- `list_errors(since: "2026-03-01T00:00:00Z")` — errors seen after this date
- `list_errors(until: "2026-03-01T00:00:00Z")` — errors seen before this date
- `list_occurrences(since: "2026-03-01T00:00:00Z")` — occurrences after this date

## Important Notes

- Error occurrences include the git SHA of the deploy. Use this to understand
  the code as it was when the error occurred.
- Always ask the user before opening GitHub issues or creating PRs.
- If you cannot reproduce an error (data-dependent, timing-dependent),
  generate a diagnosis and ask the user how to proceed.
