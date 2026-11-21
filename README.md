# skills

Skills for [Claude Code](https://docs.claude.com/en/docs/claude-code). Each folder is one self-contained skill with its own README.

| Skill | What it does |
| --- | --- |
| [`orchestrate-opencode`](orchestrate-opencode/) | Claude Code plans, reviews, tests and pushes; the opencode CLI writes the code with a cheaper model. Invoked manually with `/orchestrate-opencode <task>`. |

## Installation

Copy (or symlink) a skill folder into `~/.claude/skills/`:

```bash
git clone https://github.com/guvenimat/skills.git
mkdir -p ~/.claude/skills
cp -r skills/orchestrate-opencode ~/.claude/skills/
```

Each skill's README lists its requirements and settings. Files named `*.local.env` hold local settings and are git-ignored.

## License

MIT, see [`LICENSE`](LICENSE).
