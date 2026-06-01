# OverpermissionedAgent

**Summary**: Wiring an autonomous Claude session to your personal full-access credentials. One bad call (or one prompt-injected MCP tool result) and the agent can wipe production data, leak secrets, or post on your behalf.

**Sources**: https://www.youtube.com/watch?v=bCljOfCH8Ms

**Last updated**: 2026-05-24

---

## Observable symptoms

- Agent uses *your* personal API key, OAuth token, or DB password — same one your apps use in prod.
- Tokens granted with `*` / `admin` scope when the agent only needs `read` on three resources.
- API keys pasted directly into chat prompts ("just paste your Stripe key and I'll set up the integration").
- Same credential reused across builder, QA, reviewer subagents — no scope differentiation.
- Background subagent has write access to a database it should only read.

## Why it breaks

Two failure modes compound:

1. **Blast radius on hallucination** — agent runs `DELETE` instead of `SELECT`, drops a production table. With minimal-scope creds the worst case is "task fails"; with admin creds the worst case is "restore from backup". Practitioner advice: "create an account for your AIOS… restrict the ability of the AI to make sure you don't have a situation where an AI deleted a really big database" (source: https://www.youtube.com/watch?v=bCljOfCH8Ms).
2. **Secret exposure surface** — pasting a key into chat puts it in transcript files, session logs, fork copies, and any tool that ingests the conversation. "Don't do that. It's much more secure for you to paste in your API key into the ENV rather than… giving it in the chat history" (source: https://www.youtube.com/watch?v=bCljOfCH8Ms).

This is the credential analogue of [[ClaudeExperience/AntiPatterns/MCPPromptInjection]] — the model is treating attacker-controlled input as instructions; you want the credentials it has on hand to limit what those instructions can actually do.

## Fix — least privilege per role

- **Separate credentials per agent role**. Builder gets write to its working repo + the dev DB. QA gets read on the test DB. Reviewer gets read on the repo + comment-write on PRs. Nobody has prod.
- **Scope down OAuth grants**. `oauth.scopes` on MCP servers, GitHub fine-grained PATs, AWS IAM role per agent — whichever the platform supports. Default deny, allow specific actions.
- **Read-only by default**. If you don't have a reason for write, don't grant it.
- **No production credentials in autonomous loops**. Run the autonomous pipeline against a develop branch / staging DB / test environment. Human gates the prod promotion.

## Fix — secrets never enter the conversation

- Keep API keys in `.env` files; reference them by name (`OPENAI_API_KEY`) — never the value.
- Use settings.json `env` block or `--env` flags so the credential is in the process env, not the transcript.
- If you accidentally paste a key, rotate it. The transcript is already on disk and possibly synced.
- For temporary access, use short-lived tokens (`aws sts assume-role`, GitHub installation tokens) over long-lived PATs.

Same rule as Jerry's Telegram bot setup (Memory: 2026-05-21) — the whitelisted session is one gate; minimal-scope tools are the second gate. Defense in depth: assume any one layer can be bypassed.

## Related pages

- [[ClaudeExperience/AntiPatterns/MCPPromptInjection]]
- [[ClaudeExperience/Reference/PermissionModes]]
- [[ClaudeExperience/Reference/Settings]]
- [[ClaudeExperience/Workflows/AutonomousPipeline]]
