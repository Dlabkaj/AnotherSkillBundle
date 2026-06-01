# Anti-pattern: Treating WebFetch Output as the Raw Page

**Summary**: WebFetch is lossy by design — a small/fast model summarizes the page against your extraction prompt before Claude ever sees it. Treating the result as the raw page leads to "the page doesn't say X" conclusions that are wrong.

**Sources**: https://code.claude.com/docs/en/tools-reference (https://code.claude.com/docs/en/tools-reference)

**Last updated**: 2026-05-24

---

## Symptom

- Claude says a page "doesn't mention" something that's actually on the page.
- Decisions get made on a summary that quietly dropped the load-bearing detail.
- Re-fetching with the same prompt returns the same wrong answer (15-minute cache).

## Root cause

WebFetch pipeline (source: https://code.claude.com/docs/en/tools-reference):

1. Fetch URL (HTTP auto-upgrades to HTTPS).
2. Convert HTML → Markdown — **not configurable**.
3. Truncate to a fixed character limit if large.
4. Run the supplied **extraction prompt** through a **small, fast model** over the Markdown.
5. Return that model's answer to Claude.

Claude does not see the raw page. It sees what the small model decided was relevant. The extraction prompt is the bottleneck — if the prompt doesn't ask about X, X is gone.

## Corrective behaviors

- **Be specific in the extraction prompt.** "Extract the section on cache invalidation rules verbatim" beats "summarize the page".
- **Re-fetch with a narrower prompt** when something feels missing. Different prompt → different extraction.
- **Bypass for full fidelity**: use `curl` via Bash for the unprocessed page when the page is small enough that you actually want the raw markup.
- **Stack research-grade extractors for harder queries.** Native WebFetch is keyword-matched against SEO content. For "find me sources about X" type queries, use Exa (semantic discovery) → Firecrawl (clean content extraction with JS rendering and chrome stripping). Documented as a [[ClaudeExperience/Workflows/Plugins|plugin stack]]. (source: https://www.youtube.com/watch?v=sBF3UumkL4Y)
- **Account for the 15-min cache** — the same URL fetched twice within 15 minutes returns the cached extraction. Refetching with a different prompt after a code change may give stale content.
- **Redirects are not auto-followed across hosts.** Cross-host redirect returns a text notice naming the target; Claude must fetch the new URL explicitly.

## Permission interaction

In `default` / `acceptEdits` modes, first reach to a new domain prompts. Pre-allow with `WebFetch(domain:example.com)`. `auto` and `bypassPermissions` skip the prompt entirely — which makes the lossy-extraction problem easier to miss because the fetch happens silently.

## Related pages

- [[ClaudeExperience/Reference/ToolsCatalogue]]
- [[ClaudeExperience/AntiPatterns/MCPPromptInjection]]
- [[ClaudeExperience/Reference/PermissionModes]]
