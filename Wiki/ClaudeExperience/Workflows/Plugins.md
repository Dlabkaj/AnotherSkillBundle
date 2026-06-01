# Workflow: Plugins

**Summary**: Plugins extend Claude Code with new skills, MCP servers, hooks, slash commands, or even alternate model backends. The marketplace is the easiest install path; the harder question is what to install and what to skip.

**Sources**: https://www.youtube.com/watch?v=sBF3UumkL4Y (austin.marchese, "9 Claude Code Plugins to Build 10x Faster")

**Last updated**: 2026-05-24

---

## What a plugin is

A bundle of any combination of: skills, MCP server definitions, slash commands, hooks, even an alternate model backend (see "Multi-model via plugin" below). Installed once, available across sessions.

A single plugin can introduce all four extensibility surfaces at once, which means the security and context-cost considerations of [[ClaudeExperience/Workflows/MCP|MCP]], [[ClaudeExperience/Workflows/Skills|Skills]], and [[ClaudeExperience/Workflows/Hooks|Hooks]] all apply transitively.

## Multi-model via plugin

OpenAI ships a `codex` plugin that runs Codex *inside* a Claude Code session. The session, files, and context belong to Claude Code; the inference call routes to OpenAI. Invocation: `/codex:rescue` and similar slash commands. (source: https://www.youtube.com/watch?v=sBF3UumkL4Y)

Two reasons this matters:

1. **Models have different jaggedness** (see [[ClaudeExperience/Reference/ModelJaggedness]]). When one model is stuck on a problem, a second-opinion call to a different model often unblocks faster than reprompting the same model.
2. **Price-subsidy hedge.** A Claude Max $200/mo subscription bills out closer to ~$1,800/mo in raw token cost — current pricing is VC-subsidized. Staying portable across providers keeps options open when subsidies end. (source: https://www.youtube.com/watch?v=sBF3UumkL4Y)

## Plugin vs. subagent — keep them separate

Plugins **extend tool access** (new MCP servers, new skills, new slash commands). Subagents **extend reasoning capability** (isolated context for delegated work). Conflating them — "I'll wrap this subagent in a plugin so it's reusable" — produces brittle architectures where you can't tell whether a failure is a tool problem or a reasoning problem. (source: https://boringbot.substack.com/p/claude-code-skills-subagents-hooks)

See the [[ClaudeExperience/Workflows/Subagents#The-isolation-spectrum|isolation spectrum]] for choosing the right primitive.

## Selection criteria

- **Maintainer matters.** Anthropic-built plugins (`skill-creator`, `legal`, `front-end-design`, `security-guidance`) will be kept current; volunteer plugins may rot. Bias toward maintained ones for anything load-bearing. (source: https://www.youtube.com/watch?v=sBF3UumkL4Y)
- **Don't build what Anthropic might ship.** If your plugin would be obsoleted by an official one, the moat is one release away from gone.
- **Context cost is non-zero.** Every plugin's skill descriptions and MCP tool defs eat from your context budget on every turn — see [[ClaudeExperience/AntiPatterns/BloatedSkillBody]] and Tool Search in [[ClaudeExperience/Workflows/MCP]]. Installing nine plugins because a YouTube video said so is a real cost.

## Web-research stack pattern

Native WebFetch is keyword-matched and lossy (see [[ClaudeExperience/AntiPatterns/WebFetchAsRaw]]). Practitioners pair Claude's native search with two plugins for deeper research:

- **Exa** — semantic search over the web; surfaces results that match meaning, not just keywords.
- **Firecrawl** — content extraction that strips chrome (header/footer/buttons) and handles JS-rendered pages and embedded resources.

Stack: native search for known URLs and quick lookups → Exa to discover the *right* sources for a vague query → Firecrawl to pull clean content from those sources. (source: https://www.youtube.com/watch?v=sBF3UumkL4Y)

## Notable bundled / official plugins

| Plugin               | Origin    | Use                                              |
| -------------------- | --------- | ------------------------------------------------ |
| `skill-creator`      | Anthropic | Audits and improves project skills               |
| `front-end-design`   | Anthropic | `/front-end-design make N variants ...` for UI   |
| `security-guidance`  | Anthropic | Pre-launch security audit                        |
| `codex`              | OpenAI    | Run Codex model inside Claude Code session       |
| `caveman`            | community | Forces terse, low-fluff output (token saver)     |

(source: https://www.youtube.com/watch?v=sBF3UumkL4Y)

## Related pages

- [[ClaudeExperience/Workflows/MCP]]
- [[ClaudeExperience/Workflows/Skills]]
- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/AntiPatterns/BloatedSkillBody]]
- [[ClaudeExperience/AntiPatterns/WebFetchAsRaw]]
- [[ClaudeExperience/Reference/ModelJaggedness]]
