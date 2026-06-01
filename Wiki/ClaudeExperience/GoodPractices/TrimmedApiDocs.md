# TrimmedApiDocs

**Summary**: For integrations where you only call a handful of endpoints, ship a small markdown reference file listing just those endpoints — instead of (or alongside) connecting a full MCP server that exposes the whole API surface.

**Sources**: https://www.youtube.com/watch?v=bCljOfCH8Ms

**Last updated**: 2026-05-24

---

## When this beats an MCP server

MCP servers expose every tool the server publishes. Many APIs publish dozens; you typically use 3–5. Each tool definition pays tokens every turn ([[ClaudeExperience/Reference/PromptCaching]] doesn't help here because tool defs live above the cache breakpoint).

Practitioner take: "MCP servers loaded into your project actually eats more tokens… set up a reference guide, a markdown file inside of this project that has all of the endpoints stored so that later if you need to use a different one, you don't have to go do research again" (source: https://www.youtube.com/watch?v=bCljOfCH8Ms).

Use a trimmed doc when:

- You call < 10 endpoints from the API.
- You're scripting / batching, not interactively exploring the API surface.
- Token budget matters (autonomous loops, long sessions, many parallel agents).
- The API is stable — endpoint signatures don't change weekly.

Use an MCP server when:

- You don't know which endpoints you'll need in advance (interactive exploration).
- The MCP server adds real value beyond a thin REST wrapper (auth handling, schema fetching, pagination).
- Tool Search is on and the server uses `serverInstructions` well — see [[ClaudeExperience/Workflows/MCP]].

## Shape of a trimmed doc

Per-tool markdown file under `docs/integrations/<tool>.md`:

```markdown
# ClickUp API

Auth: env var `CLICKUP_TOKEN`, header `Authorization: <token>`.

## Endpoints we use

### Create task
POST https://api.clickup.com/api/v2/list/{list_id}/task
Body: { name, description, status, assignees: [user_id] }
Returns: { id, url, ... }

### Update task status
PUT https://api.clickup.com/api/v2/task/{task_id}
Body: { status }

### List tasks in list
GET https://api.clickup.com/api/v2/list/{list_id}/task?archived=false

## Common errors
- 401 → token revoked, see auth refresh in `auth.md`
- 429 → backoff 60s, retry
```

Reference it from the relevant skill: `See @docs/integrations/clickup.md for endpoints`.

## Self-improving doc loop

On API call failure, instruct the agent to update the doc rather than swallow the error: "every time that it fails, it learns and it can update something… update the API doc so that next time you do this, it never happens again" (source: https://www.youtube.com/watch?v=bCljOfCH8Ms).

Concrete rule in the skill:

> If an API call fails with an unexpected response shape or undocumented error, after fixing the immediate problem, append a "Gotchas" entry to `docs/integrations/<tool>.md`.

The doc grows tighter against the API's real behavior over time. Same idea as [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]] — let observed reality earn its way into the persistent context.

## Caveat

This is one practitioner's preference, not Anthropic guidance. If your project already has a working MCP setup and Tool Search keeps token cost bounded, the migration cost may not be worth it. The pattern is most useful for new integrations where you're choosing between "drop in MCP" and "write a thin client".

## Related pages

- [[ClaudeExperience/Workflows/MCP]]
- [[ClaudeExperience/AntiPatterns/CacheChurn]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
