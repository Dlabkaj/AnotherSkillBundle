# Claude Code in Large Codebases — Best Practices

Anthropic blog post covering patterns observed across successful Claude Code deployments at enterprise scale (multi-million-line monorepos, legacy systems, dozens of microservices). Part of a series called "Claude Code at scale". Every atom is sourced from the single Anthropic blog post cited below (subject's own authority).

Source: [How Claude Code works in large codebases (Anthropic blog, May 14 2026)](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start)

## How Claude Code navigates a codebase

- Claude Code navigates the way a software engineer would: traverses the file system, reads files, greps for what it needs, and follows references across the codebase
- Operates locally on the developer's machine; does not require a codebase index to be built, maintained, or uploaded to a server
- Contrast with RAG-powered coding tools: embedding pipelines can't keep up with active engineering teams, so retrieval can return functions renamed weeks ago or reference modules already deleted, with no signal that they are stale
- Agentic search tradeoff: works best when Claude has enough starting context to know where to look; a vague query over a billion-line codebase can hit context-window limits before any work begins
- Codebases running C, C++, C#, Java, PHP — languages teams don't always associate with AI coding tools — are called out as areas where Claude Code performs better than most teams expect, particularly as of recent model releases

## The harness matters as much as the model

Anthropic frames Claude Code's ecosystem — the "harness" — as more determinative of performance than model choice alone. The harness is built from five extension points, plus two additional capabilities:

- **CLAUDE.md files** — context files Claude reads automatically at the start of every session. Root file for the big picture; subdirectory files for local conventions. Loaded every session regardless of task, so keep them focused on what applies broadly
- **Hooks** — most teams treat them as guardrails, but their more valuable use is continuous improvement. A stop hook can reflect on a session and propose CLAUDE.md updates while context is fresh; a start hook can load team-specific context dynamically. For linting/formatting, hooks enforce rules deterministically instead of relying on Claude to remember
- **Skills** — progressive disclosure of specialized workflows and domain knowledge, loaded only when the task calls for them. Can be scoped to specific paths (e.g., a payments team's deploy skill only auto-loads inside their service directory)
- **Plugins** — bundle skills, hooks, and MCP configs into a single installable package so a new engineer gets the same context and capabilities on day one. Updates can be distributed across an organization through managed marketplaces
- **MCP servers** — how Claude reaches internal tools, data sources, and APIs it can't otherwise access. The most sophisticated teams built MCP servers exposing structured search as a callable tool
- **Language Server Protocol (LSP) integrations** — give Claude the same navigation a developer has in their IDE ("go to definition", "find all references"), providing symbol-level precision rather than text pattern-matching. Called out as one of the highest-value investments for multi-language codebases
- **Subagents** — isolated Claude instances with their own context windows that take a task, do the work, and return only the final result. Pattern: a read-only subagent maps a subsystem and writes findings to a file, then the main agent edits with the full picture

Note from the source: LSP is accessed through the plugin layer; subagents are a delegation capability rather than a configured extension point.

## Extension components — at-a-glance table (from source)

| Component | What it is | When it loads | Best for | Common confusion |
|---|---|---|---|---|
| CLAUDE.md | Context file Claude reads automatically | Every session | Project-specific conventions, codebase knowledge | Using it for reusable expertise that belongs in a skill |
| Hooks | Scripts that run at key moments | Triggered by events | Automating consistent behavior, capturing session learnings | Using prompts for things that should run automatically |
| Skills | Packaged instructions for specific task types | On demand, when relevant | Reusable expertise across sessions and projects | Loading everything into CLAUDE.md instead |
| Plugins | Bundled skills, hooks, MCP configs | Always available once configured | Distributing a working setup across the org | Letting good setups stay tribal |
| LSP | Real-time code intelligence via language-specific servers | Always available once configured | Symbol-level navigation and automatic error detection in typed languages | Assuming that it's automatic |
| MCP servers | Connections to external tools and data | Always available once configured | Giving Claude access to internal tools it can't otherwise reach | Building MCP connections before the basics are working |
| Subagents | Separate Claude instances for specific tasks | When invoked | Splitting exploration from editing, parallel work | Running exploration and editing in the same session |

*(reproduced from the article's own table)*

## Pattern 1 — Making the codebase navigable at scale

- Keep CLAUDE.md files lean and layered — root file for the big picture, subdirectory files for local conventions. Root file should be pointers and critical gotchas only; everything else drifts into noise
- Initialize Claude in subdirectories, not at the repo root — Claude automatically walks up the directory tree and loads every CLAUDE.md it finds, so root-level context is never lost
- Scope test and lint commands per subdirectory — running the full suite for a one-service change causes timeouts and wastes context on irrelevant output. Works well for service-oriented codebases; harder in compiled-language monorepos with deep cross-directory dependencies
- Use `.ignore` files to exclude generated files, build artifacts, and third-party code. Committing `permissions.deny` rules in `.claude/settings.json` version-controls the exclusions so every developer gets the same noise reduction; developers working on code generators can override in local settings
- Build a lightweight markdown "codebase map" at the repo root when directory structure alone isn't legible — a one-line description per top-level folder acts as a table of contents. For codebases with hundreds of top-level folders, layer it: root file describes the highest level; subdirectory CLAUDE.md files provide the next level, loading on demand
- @-mentioning specific files or directories can substitute for a codebase map in simpler cases
- Run LSP servers so Claude searches by symbol, not by string — grep for a common name returns thousands of matches; LSP returns only references to the same symbol. Requires installing a code-intelligence plugin for the language plus the corresponding language-server binary; Claude Code documentation covers available plugins and troubleshooting
- Caveat named by the article: even hierarchical CLAUDE.md breaks down in codebases with hundreds of thousands of folders and millions of files, or legacy systems on non-git version control — to be addressed in future installments of the series

## Pattern 2 — Actively maintain CLAUDE.md as model intelligence evolves

- Instructions written for the current model can work against a future one. Example given: a CLAUDE.md rule telling Claude to break every refactor into single-file changes may have helped an earlier model stay on track but would prevent a newer one from making coordinated cross-file edits it now handles well
- Skills and hooks built to compensate for specific model limitations become overhead once those limitations no longer exist. Example given: a hook intercepting file writes to enforce `p4 edit` in a Perforce codebase became redundant once Claude Code added native Perforce mode
- Recommended cadence: a meaningful configuration review every three to six months, and additionally whenever performance feels like it's plateaued after major model releases

## Pattern 3 — Assign ownership for Claude Code management and adoption

- The rollouts that spread fastest had a dedicated infrastructure investment *before* broad access — a small team (sometimes one person) wired up the tooling so Claude already fit developer workflows on first contact
- Ownership typically sits under developer experience or developer productivity — the function that normally onboards engineers and builds developer tooling
- Emerging role in several organizations: **agent manager** — a hybrid PM/engineer function dedicated to managing the Claude Code ecosystem
- Minimum viable version for organizations without a dedicated team: a DRI with ownership over Claude Code configuration and authority over settings, permissions policy, the plugin marketplace, and CLAUDE.md conventions
- Bottoms-up adoption generates enthusiasm but fragments without a central curator; without a standardized CLAUDE.md hierarchy or curated set of skills/plugins, knowledge stays tribal and adoption plateaus
- For regulated industries, the article recommends starting with a defined set of approved skills, required code-review processes, and limited initial access, expanding as confidence builds; cross-functional working groups combining engineering, information security, and governance are named as producing the smoothest deployments

## Scope caveat from the source

- Claude Code is described as designed around conventional software-engineering environments: engineers as the primary contributors, Git as the version control, standard directory structures
- Non-traditional setups named as requiring additional configuration work: game engines with large binary assets, environments with unconventional version control, non-engineers contributing to the codebase
- Anthropic's Applied AI team is named as the group that works directly with engineering teams to translate the patterns into an organization's specific requirements
