# sf-workflows

## Shared agent skills

This repository uses [Tessl](https://tessl.io/) to install and keep shared GitHub Actions and shell-linting skills in sync for Codex, Claude Code, and Cursor. The installed skills cover GitHub Actions generation and validation, Bash in `run:` steps, and ShellCheck/actionlint linting.

Only [tessl.json](tessl.json) is committed. Tessl downloads the pinned skills and creates local, agent-specific configuration and skill links. Those generated files are intentionally ignored.

## Get started

1. Install Tessl and sign in:

   ```bash
   curl -fsSL https://get.tessl.io | sh
   ```

2. From the repository root, configure all supported agents and install this repository's pinned skills:

   ```bash
   tessl init --agent codex --agent claude-code --agent cursor
   tessl install
   ```

   You only need to have the agents you use installed. Tessl writes each agent's configuration only on your machine.

3. Confirm installation, then restart any agent that was already open:

   ```bash
   tessl list
   ```

Once installed, skills activate automatically for matching tasks. For example:

- “Create a secure GitHub Actions workflow for Terraform validation.”
- “Validate this workflow and its Bash `run` steps.”
- “Lint the changed shell scripts and GitHub Actions workflows.”

## Maintaining skills

Use `tessl outdated` to check for updates. When updating a shared skill, review its quality and security information in the Tessl Registry, run `tessl install <source>`, and commit the resulting [tessl.json](tessl.json) version change. Do not commit `.tessl/`, `.agents/`, `.claude/`, `.codex/`, or `.cursor/`.

Useful references: [Tessl CLI installation](https://docs.tessl.io/introduction-to-tessl/installation), [using skills](https://docs.tessl.io/use/enhance-your-workflow-with-skills), [GitHub Actions toolkit](https://tessl.io/registry/pantheon-ai/github-actions-toolkit), and [lint skill](https://tessl.io/registry/skills/github/aaddrick/claude-desktop-debian/lint).
