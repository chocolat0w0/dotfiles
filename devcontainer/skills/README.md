# Generic agent skills

Keep only cross-project, publishable skills here. Repository-specific rules,
private review history, credentials, and customer or team information belong in
that repository's own private configuration instead.

Place each skill in a direct child directory containing `SKILL.md`.

```text
devcontainer/skills/
├── shared/<skill-name>/SKILL.md  # copied to both Codex and Claude
├── claude/<skill-name>/SKILL.md  # copied only to Claude
└── codex/<skill-name>/SKILL.md   # copied only to Codex
```

Use `claude/` for a workflow where Claude invokes Codex, and `codex/` for the
opposite direction. This keeps tool-specific instructions out of the other
agent's skill discovery path.

`../install-generic-agent-skills.sh` runs from `setup-devcontainer.sh` and
copies the skills to their applicable paths under `~/.claude/skills` and
`~/.codex/skills`.

The script only copies or updates skills; it does not remove a destination
skill when its source is deleted.
