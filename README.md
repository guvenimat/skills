# orchestrate-opencode

A Claude Code skill that splits development between two models: Claude Code acts as the manager (writes prompts, reviews diffs, runs tests, pushes) and the opencode CLI (https://opencode.ai) acts as the worker that writes the code with a cheaper model. It is invoked only manually with `/orchestrate-opencode <task>` (`disable-model-invocation: true` in `SKILL.md`) and keeps that flow for the rest of the session.

## How it works

1. **Prepare:** Read the project's `CLAUDE.md` / `AGENTS.md` and progress notes, learn the test commands and pitfalls, and start from a clean tree on a feature branch.
2. **Research:** For medium/large tasks, fill `RESEARCH_PROMPT.md` and run it with `WORKER_AGENT=plan WORKER_TAIL=200` in a new session to get a fact sheet instead of scanning the code yourself.
3. **Write the prompt:** An English `<id>.md` in the scratchpad with numbered items: file/function names, the cause, expected behavior, the test to add and the exact verification commands.
4. **Run:** Start `worker.sh` in the background and get notified when the worker finishes.
5. **Review:** Check the risky-commands report, run a second-eye review with `REVIEW_PROMPT.md` in a new session, then read `git diff` line by line and send fix prompts if needed (no tests at this stage).
6. **Test:** Run the unit tests yourself, plus frontend lint/test/build and the related e2e tests; a failure caused by the code goes back to the same session.
7. **Push:** Push the branch and watch CI; merge into main only with the user's approval.
8. **Close:** Update progress notes and report commits, review rounds, test results and push/CI status.

- **Session management:** a new independent task gets a new session; fix rounds, plan to build and test failures continue the same `SESSION`; a long or confused session is replaced by a new one with a status summary.
- **Small tasks:** small scoped fixes are collected until there are 4-6 items (or the user says send), then handled in one prompt and one worker run with one commit per item; research and the second eye are skipped, review and tests are not.
- **Safety:** the worker's permissions live in `worker-opencode.json` (passed through `OPENCODE_CONFIG`); push, merge, rebase, branch switching, `gh`, stopping/removing containers, `rm -rf` and manual SQL `DELETE`/`UPDATE`/`TRUNCATE`/`DROP`/`ALTER` are denied. These are pattern matches, not a sandbox; the risky-commands report and the mandatory review stay in place.

## Requirements

- Claude Code.
- opencode CLI installed and logged in to a provider that serves the configured model.
- `git`.
- `bash`; on Windows use Git Bash, which ships with Git for Windows.
- Optional: `gh` CLI for watching CI.

Supported: Linux and Windows (Git Bash) are tested; macOS is expected to work (only POSIX tools are used) but untested.

## Installation

Copy (or symlink) the `skill/` folder to `~/.claude/skills/orchestrate-opencode/`:

```bash
git clone <repo-url> && mkdir -p ~/.claude/skills && cp -r orchestrate-opencode/skill ~/.claude/skills/orchestrate-opencode
```

Symlink alternative for Linux/macOS:

```bash
ln -s "$PWD/orchestrate-opencode/skill" ~/.claude/skills/orchestrate-opencode
```

Optionally copy `worker.local.env.example` to `worker.local.env` in the installed folder and edit it.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `WORKER_MODEL` | `opencode-go/deepseek-v4.1-flash` | opencode model |
| `WORKER_VARIANT` | `max` (empty = none) | model variant |
| `WORKER_AGENT` | `build` | `build` or `plan` (`plan` = read only, returns a plan or report) |
| `WORKER_LOG` | `<prompt-file>.log` | log file |
| `WORKER_TIMEOUT` | `5400` | hard limit in seconds |
| `WORKER_STALL` | `1200` | stop the worker when its log does not grow for this many seconds |
| `WORKER_TAIL` | `40` | log lines printed at the end; use `200` for review/research reports |
| `WORKER_BLOCK_FREE` | `0` | `1` = refuse model names containing "free" |

Values come from environment variables first, then from `KEY=VALUE` lines in `worker.local.env` next to `worker.sh` (the environment wins). `worker.local.env` is git-ignored.

`worker.sh` runs a watchdog: if the worker's log does not grow for `WORKER_STALL` seconds, or the run exceeds `WORKER_TIMEOUT` seconds, it stops the worker and its child processes, prints `STALL:` or `TIMEOUT:` and sets `OPENCODE_EXIT=124`.

## Usage

```text
/orchestrate-opencode Fix the off-by-one in the pagination of /api/orders and add a test
```

The script can also be run by hand from inside the target repository:

```bash
bash ~/.claude/skills/orchestrate-opencode/worker.sh prompt.md [session-id]
```

Pass a session id to continue an existing opencode session. The script appends `WORKER_RULES.md` to the prompt, applies `worker-opencode.json`, and prints the `MODEL=... VARIANT=... AGENT=... BRANCH=... HEAD=...` line, `OPENCODE_EXIT`, `SESSION`, the commits made, the diff stat, uncommitted files, risky commands to review, and the tail of the worker summary.

## Customizing

Your own rules belong in the target project's `CLAUDE.md` / `AGENTS.md` or in `~/.claude/CLAUDE.md`; the worker is told to read them (see `WORKER_RULES.md`). Edit `worker-opencode.json` to change which commands the worker may run.

## License

MIT, see `LICENSE`.
