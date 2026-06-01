# Hook Exit Code Confusion

**Summary**: Hook returns `exit 1` expecting it to block, or emits JSON on a non-zero exit, or hangs Claude with a slow `UserPromptSubmit`. All three silently break the policy the hook was supposed to enforce.

**Sources**: https://code.claude.com/docs/en/hooks, https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/

**Last updated**: 2026-05-24

---

## Symptom

- A `PreToolUse` hook prints "Blocked!" and `exit 1`, but the tool runs anyway.
- A hook emits a JSON decision object and a non-zero exit code — the decision is ignored, stderr is shown as a plain error.
- `UserPromptSubmit` makes the prompt feel laggy or aborts at 30s.
- A hook command works in your shell but fails inside Claude Code because `~/.bashrc` echoes a banner that corrupts the JSON on stdout.
- A `PermissionRequest` auto-approve hook is added for `ExitPlanMode` with an empty or `".*"` matcher — every write, every shell command, every MCP call is now silently approved.
- A `Stop` hook returns `block` forever and Claude appears stuck; after 8 blocks Claude Code overrides it anyway, ending the turn with a warning.
- A `PermissionRequest` hook is wired into a project that's run with `claude -p` (non-interactive) — the hook never fires because permission dialogs only exist in interactive mode. Tool runs unguarded.
- Settings file edited mid-session; new hook entries don't take effect because `/hooks` menu and hook registry are read at session startup only.

## Why it happens

Exit-code semantics are non-obvious:

| Exit code | Meaning              | JSON processing                         |
| --------- | -------------------- | --------------------------------------- |
| `0`       | Success              | Parse stdout JSON if valid              |
| `2`       | **Blocking error**   | Ignore stdout/JSON, show stderr as error |
| other     | Non-blocking error   | Log stderr, **continue**                 |

(source: https://code.claude.com/docs/en/hooks)

`PostToolUse` cannot block — the tool already ran. To block, hook on `PreToolUse` instead. (source: https://code.claude.com/docs/en/hooks)

Path placeholders like `${CLAUDE_PROJECT_DIR}` are not substituted inside unquoted shell-form commands; either quote them or use exec form with `args`. (source: https://code.claude.com/docs/en/hooks)

Default `UserPromptSubmit` timeout is 30s. Slow hooks gate every prompt. (source: https://code.claude.com/docs/en/hooks)

## Corrective

- To block: `exit 2` from stderr, OR `exit 0` with `{"hookSpecificOutput": {"permissionDecision": "deny", ...}}` on stdout. Pick one, never both.
- Use `PreToolUse` for policy, never `PostToolUse` — the tool already ran. (source: https://code.claude.com/docs/en/hooks-guide)
- Use exec form: `"command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/script.sh"]`. Path expansion is reliable.
- Make `UserPromptSubmit` hooks fast (<<30s) or set `"async": true` so the prompt is not blocked.
- Suppress shell profile banners in non-interactive mode (`[[ $- == *i* ]]` guard) so stdout JSON stays clean.
- `PermissionRequest` auto-approve: keep matchers narrow (`ExitPlanMode`, never `""`/`.*`).
- `Stop` hooks must check `stop_hook_active` from stdin and exit 0 when true, or raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. (source: https://code.claude.com/docs/en/hooks-guide)
- When multiple `PreToolUse` hooks set `updatedInput`, the **last one to finish wins** (parallel race). Don't have two hooks rewrite the same tool's input. (source: https://code.claude.com/docs/en/hooks-guide)
- In non-interactive mode (`claude -p`), `PermissionRequest` does not fire — use `PreToolUse` for policy enforcement instead. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)
- Restart the session after editing `settings.json` — the `/hooks` menu reads config at startup, mid-session edits are silently ignored. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)
- If `jq` isn't installed, the hook silently errors — install it system-wide or parse JSON with Python/Node inside the hook script. (source: https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)

## Related pages

- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/Reference/HookEvents]]
- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/Reference/PermissionModes]]
