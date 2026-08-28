---
name: skill-standard
description: Reference for the official Agent Skills open standard (agentskills/agentskills, Apache-2.0). Use when creating a new skill, modifying an existing skill, or validating that a skill folder conforms to the standard — checking SKILL.md frontmatter rules (name/description/license/compatibility/metadata/allowed-tools), directory layout (SKILL.md + optional scripts/references/assets), progressive disclosure limits, and file-reference conventions. The full specification lives in references/agent-skills-spec.md; consult it before authoring or reviewing any skill.
---

# Skill Standard (Agent Skills Open Standard)

This skill packages the official Agent Skills open standard — the format specification maintained at [agentskills/agentskills](https://github.com/agentskills/agentskills) (Apache-2.0) and published at <https://agentskills.io/specification>. It is the authoritative reference for how a skill folder and its `SKILL.md` must be structured.

## When to use

- Creating a new skill from scratch.
- Editing or restructuring an existing skill so it stays spec-compliant.
- Validating a skill folder (`SKILL.md` frontmatter, naming, directory layout).
- Answering questions about the Agent Skills format itself (fields, constraints, progressive disclosure).

## Quick reference (core rules)

### Directory layout

```
skill-name/
├── SKILL.md          # Required: metadata + instructions
├── scripts/          # Optional: executable code
├── references/       # Optional: documentation (loaded on demand)
├── assets/           # Optional: templates, resources
└── ...               # Any additional files or directories
```

### SKILL.md frontmatter

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | ≤ 64 chars; lowercase letters, numbers, hyphens only; no leading/trailing/consecutive hyphens; must match the parent directory name |
| `description` | Yes | ≤ 1024 chars; non-empty; describe both what the skill does and when to use it |
| `license` | No | License name or reference to a bundled license file |
| `compatibility` | No | ≤ 500 chars; environment requirements |
| `metadata` | No | Map of string keys to string values |
| `allowed-tools` | No | Space-separated pre-approved tools (experimental) |

### Body content

- Markdown after the frontmatter; no format restrictions.
- Keep `SKILL.md` under ~500 lines / < 5000 tokens; move detail into `references/` files.
- Reference files with relative paths from the skill root, ideally one level deep.

### Progressive disclosure

1. **Metadata** (~100 tokens): name + description loaded at startup for all skills.
2. **Instructions** (< 5000 tokens): full `SKILL.md` body loaded when the skill activates.
3. **Resources** (on demand): `scripts/`, `references/`, `assets/` files loaded only when required.

## Validation

Use the reference validator from the standard repo (Python, Apache-2.0):

```bash
pip install -e ./skills-ref        # from the agentskills repo
skills-ref validate ./my-skill
skills-ref read-properties ./my-skill   # JSON: name, description, ...
```

The full specification with examples of valid/invalid `name` values, good vs. poor `description` text, and each optional field is in [references/agent-skills-spec.md](references/agent-skills-spec.md).
