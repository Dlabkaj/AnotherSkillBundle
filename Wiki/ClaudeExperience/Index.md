# Claude Experience

**Summary**: Symptom-driven knowledge base on how to be effective with Claude Code. AntiPatterns/ pages drive the always-active advice skill.

**Sources**: `MemoryVault/Raw/claude-effectiveness/raw/*.txt`

**Last updated**: 2026-05-27 (review pass: citations URL-ized, Settings linked)

---

## Anti-patterns (observable bad behaviors)

The advice skill scans for these and surfaces a nudge when detected.

- [[ClaudeExperience/AntiPatterns/KitchenSinkSession]] — mixing unrelated tasks in one context
- [[ClaudeExperience/AntiPatterns/RepeatedCorrections]] — correcting the same issue twice without resetting context
- [[ClaudeExperience/AntiPatterns/OverSpecifiedClaudeMd]] — bloated CLAUDE.md causes rules to be ignored
- [[ClaudeExperience/AntiPatterns/TrustThenVerifyGap]] — accepting plausible output without verification
- [[ClaudeExperience/AntiPatterns/InfiniteExploration]] — unscoped investigation fills main context
- [[ClaudeExperience/AntiPatterns/VaguePrompts]] — under-specified asks waste tokens on corrections
- [[ClaudeExperience/AntiPatterns/SkipPlanMode]] — jumping to code on complex multi-file tasks
- [[ClaudeExperience/AntiPatterns/SuppressErrorRoot]] — patching symptoms instead of root cause
- [[ClaudeExperience/AntiPatterns/HumanAsBottleneck]] — staying interactively in the loop when work could be fanned out / auto-looped
- [[ClaudeExperience/AntiPatterns/BloatedSkillBody]] — skill SKILL.md is too long/narrative; pays tokens every turn and crowds compaction
- [[ClaudeExperience/AntiPatterns/HookExitCodeConfusion]] — hook returns wrong exit code (or both code+JSON), so the policy it was meant to enforce silently no-ops
- [[ClaudeExperience/AntiPatterns/CacheChurn]] — mid-task actions (model switch, /compact, MCP flap, bare-tool deny rule) invalidate the prompt cache and tank cost/latency
- [[ClaudeExperience/AntiPatterns/MCPPromptInjection]] — MCP tool output is untrusted input; a malicious server or attacker-controlled issue body can hijack the session
- [[ClaudeExperience/AntiPatterns/WebFetchAsRaw]] — WebFetch is lossy by design; "page doesn't mention X" may just mean the extraction prompt didn't ask
- [[ClaudeExperience/AntiPatterns/AutonomousDispatchVagueAC]] — dispatching headless agents on tickets without crisp acceptance criteria; they can't ask back, so they hallucinate
- [[ClaudeExperience/AntiPatterns/OverpermissionedAgent]] — autonomous agent runs with your full-access prod credentials; one hallucination = max blast radius

## Good practices (paired correctives)

- [[ClaudeExperience/GoodPractices/ProvideVerification]]
- [[ClaudeExperience/GoodPractices/PlanThenImplement]]
- [[ClaudeExperience/GoodPractices/SpecificContext]]
- [[ClaudeExperience/GoodPractices/ManageContext]]
- [[ClaudeExperience/GoodPractices/EffectiveClaudeMd]]
- [[ClaudeExperience/GoodPractices/UseSubagents]]
- [[ClaudeExperience/GoodPractices/UseCheckpoints]]
- [[ClaudeExperience/GoodPractices/MaximizeTokenThroughput]]
- [[ClaudeExperience/GoodPractices/SkillsForProcedures]]
- [[ClaudeExperience/GoodPractices/TrimmedApiDocs]]

## Workflows

- [[ClaudeExperience/Workflows/PlanMode]]
- [[ClaudeExperience/Workflows/NonInteractiveMode]]
- [[ClaudeExperience/Workflows/CheckpointsRewind]]
- [[ClaudeExperience/Workflows/MultipleSessionsFanout]]
- [[ClaudeExperience/Workflows/ScheduledRuns]]
- [[ClaudeExperience/Workflows/Skills]]
- [[ClaudeExperience/Workflows/Subagents]]
- [[ClaudeExperience/Workflows/Hooks]]
- [[ClaudeExperience/Workflows/MCP]]
- [[ClaudeExperience/Workflows/AutonomousPipeline]]
- [[ClaudeExperience/Workflows/Plugins]]

## Reference

- [[ClaudeExperience/Reference/ClaudeMdLocations]]
- [[ClaudeExperience/Reference/PermissionModes]]
- [[ClaudeExperience/Reference/ModelJaggedness]]
- [[ClaudeExperience/Reference/AutoMemory]]
- [[ClaudeExperience/Reference/ProjectRules]]
- [[ClaudeExperience/Reference/SkillFrontmatter]]
- [[ClaudeExperience/Reference/SubagentFrontmatter]]
- [[ClaudeExperience/Reference/HookEvents]]
- [[ClaudeExperience/Reference/PromptCaching]]
- [[ClaudeExperience/Reference/ContextWindow]]
- [[ClaudeExperience/Reference/MCPConfig]]
- [[ClaudeExperience/Reference/ModelConfig]]
- [[ClaudeExperience/Reference/Settings]]
- [[ClaudeExperience/Reference/ToolsCatalogue]]

## Log

- [[ClaudeExperience/Log]]
