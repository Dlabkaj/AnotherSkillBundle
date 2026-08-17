# Claude Code Installation

Install methods currently listed on the official `anthropics/claude-code` GitHub repo landing page. This page rests end-to-end on the project's own reference (subject's-own-authority exception applied in REVIEW).

Source: [anthropics/claude-code repo README](https://github.com/anthropics/claude-code)

## Recommended install commands

- macOS/Linux (recommended): `curl -fsSL https://claude.ai/install.sh | bash`
- Homebrew (macOS/Linux): `brew install --cask claude-code`
- Windows (recommended): `irm https://claude.ai/install.ps1 | iex`
- WinGet (Windows): `winget install Anthropic.ClaudeCode`

## Deprecated

- npm install (`npm install -g @anthropic-ai/claude-code`) is deprecated; the README directs users to one of the recommended methods above

## Getting started

- After install, `cd` to a project directory and run `claude`
- Further install options, uninstall steps, and troubleshooting live in the setup documentation linked from the README

## Repo contents pointed at from the landing page

- The repo bundles several first-party Claude Code plugins that extend functionality with custom commands and agents; details live in the `plugins/` directory of the repo
- `CHANGELOG.md` is present at the repo root (listed among top-level files in the README)

## In-product feedback

- The `/bug` command reports issues directly from within Claude Code; GitHub issues are the alternative
- A Claude Developers Discord is linked from the README for community help and discussion

## Data and privacy notes on the landing page

- Anthropic collects usage data (e.g., code acceptance/rejection), associated conversation data, and `/bug` feedback when Claude Code is used
- README states retention limits on sensitive info, restricted access to session data, and a policy against using feedback for model training
- Governing documents named: Commercial Terms of Service and Privacy Policy
