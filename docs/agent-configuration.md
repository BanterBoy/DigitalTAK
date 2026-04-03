---
layout: page
title: Agent Configuration
nav_title: Agent Configuration
---

# Agent Configuration
{: .no_toc }

How to use the Paperclip AI agents to manage and extend the DigitalTAK project.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

DigitalTAK uses [Paperclip](https://paperclip.ing) to coordinate AI agents that assist with development, deployment, and documentation tasks. Agents run as autonomous workers that pick up tasks, do real work in the repository, and report back — without requiring manual intervention for routine operations.

There are two separate but related agent systems in this repo:

| System | Location | Purpose |
|--------|----------|---------|
| **Paperclip agents** | Managed via Paperclip control plane | Project management, development, documentation |
| **VS Code / GitHub agents** | `.github/agents/` | Scoped code-editing tasks within VS Code |

---

## Paperclip Agents

Three agents are active on this project:

### CEO
- **Role:** Company governance, task creation, agent hiring
- **What it does:** Creates high-level goals and tasks, reviews output, approves significant changes

### Founding Engineer
- **Role:** Full-stack technical implementation
- **What it does:** Writes and maintains PowerShell modules (TAKServerPS, TAKInstall, TAKDeploy), Bash scripts, CI pipelines, integration tests, and deployment runbooks
- **Success criteria:** A single PowerShell command deploys a fully operational CivTAK instance with no manual steps

### Technical Author *(this agent)*
- **Role:** Documentation
- **What it does:** Reviews the codebase, writes and maintains this documentation site, keeps docs in sync with implementation changes

---

## How Agents Work

Each agent runs in **heartbeats** — short execution windows triggered by Paperclip. Each heartbeat, an agent:

1. Checks its inbox for assigned tasks
2. Picks up the highest-priority open task
3. Does real work (reads/writes code, runs tests, makes commits)
4. Posts a comment on the task with what was done
5. Marks the task done or blocked, then exits

Agents only work on tasks assigned to them. They do not pick up unassigned work.

---

## Using Agents for Deployment Configuration

### Changing Deployment Defaults

If you want the Founding Engineer to modify default deployment parameters (e.g., change the default VM name, adjust resource sizes, or update the default ISO path), create a task and assign it to the Founding Engineer:

1. Open [Paperclip](https://paperclip.ing) and navigate to the DigitalTAK project
2. Create a new task with a clear description of the change (e.g., *"Change default VHDSizeBytes to 120GB in Deploy-TAKServer.ps1"*)
3. Assign it to the **Founding Engineer** agent
4. The agent will pick it up, make the change, commit to `prod`, and mark the task done

### Adding a New TAK Server Feature

Example workflow for adding a new TAKServerPS cmdlet:

1. Create a task: *"Add Get-TAKFederation cmdlet to TAKServerPS"*
2. Assign to **Founding Engineer**
3. The agent writes the cmdlet, adds Pester tests, updates the module manifest, and commits

### Requesting Documentation Updates

1. Create a task: *"Document the new Get-TAKFederation cmdlet"*
2. Assign to **Technical Author**
3. The agent reviews the new code and updates this documentation site

---

## VS Code / GitHub Agents

These agents are defined in `.github/agents/` and are invoked directly within VS Code using the `@agent` tool. They are scoped to specific areas of the codebase:

| Agent | File | Scope |
|-------|------|-------|
| **Orchestrator** | `ORCHESTRATOR.agent.md` | Spawns sub-agents, coordinates cross-area work |
| **TAK Install** | `tak-install.agent.md` | `RL9_tak5.7r8_install.sh`, `tak-uninstall.sh` |
| **TAK Certs** | `tak-certs.agent.md` | Certificate creation, `CoreConfig.xml` patching |
| **Let's Encrypt** | `tak-letsencrypt.agent.md` | Certbot issuance and renewal scripts |
| **Openfire** | `tak-openfire.agent.md` | XMPP server installation and configuration |

### Using VS Code Agents

In VS Code with the GitHub Copilot extension:

```
@ORCHESTRATOR Update the Openfire installation script to use the latest upstream package
```

The orchestrator will analyse the request, decide which sub-agents to invoke, and coordinate the edits across the relevant files.

Each sub-agent has a strict scope — it will only touch files it owns and will not make changes outside that scope, even if asked.

---

## Agent Instructions Files

Each Paperclip agent has an `AGENTS.md` file defining its role, responsibilities, and working style. These are stored in the Paperclip instance directory and are loaded at the start of every heartbeat.

Agent instructions are managed through the Paperclip control plane. Contact the **CEO** agent if you need to update an agent's role or responsibilities.

---

## Skill System

Paperclip agents can be extended with skills — pre-built capability packages that give agents new tools or domain knowledge. The `.agents/skills/` directory contains the skills available on this project.

Available skills include:

| Skill | Purpose |
|-------|---------|
| `documentation-writer` | Technical writing assistance |
| `gh-cli` | GitHub CLI operations |
| `git-commit` | Structured commit message generation |
| `github-issues` | Issue management via GitHub API |
| `security-review` | Security analysis of scripts and configs |
| `microsoft-docs` | Fetch and parse Microsoft documentation |
| `mcp-integration` | MCP server integration helpers |

Skills are assigned to agents via the Paperclip control plane. To request a skill be added to an agent, create a task and assign it to the **CEO**.

---

## Monitoring Agent Activity

Agent runs are visible in the Paperclip UI under each agent's **Runs** tab. Each run links to the task it worked on and shows the full action log including:

- Files read and written
- Git commits made
- API calls made
- Comments posted

This provides a complete audit trail of what each agent did and why.
