# Non-Interactive Mode (`claude -p`)

**Summary**: `claude -p "prompt"` runs Claude without an interactive session. Used in CI, pre-commit hooks, scripts, batch fan-out, and any unattended workflow.

**Sources**: https://code.claude.com/docs/en/best-practices

**Last updated**: 2026-05-23

---

## Basic forms

```
claude -p "Explain what this project does"
claude -p "List all API endpoints" --output-format json
claude -p "Analyze this log file" --output-format stream-json
```

`--output-format stream-json` emits streaming JSON for real-time processing.

## Fan-out across files

```
for file in $(cat files.txt); do
  claude -p "Migrate $file from React to Vue. Return OK or FAIL." \
    --allowedTools "Edit,Bash(git commit *)"
done
```

Pattern: generate a task list, loop, scope permissions with `--allowedTools`. Test on 2-3 files first, refine the prompt based on what goes wrong, then run at scale.

## With auto mode

```
claude --permission-mode auto -p "fix all lint errors"
```

A classifier model reviews commands before they run, blocking scope escalation, unknown infrastructure, and hostile-content-driven actions. For `-p` runs, auto mode aborts if the classifier repeatedly blocks — no user to fall back to.

## Related pages

- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Reference/PermissionModes]]
