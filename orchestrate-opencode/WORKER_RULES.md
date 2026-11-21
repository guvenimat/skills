Worker rules:

- Read the project's `CLAUDE.md` / `AGENTS.md` and the user's `~/.claude/CLAUDE.md` (if present) first and follow them strictly. Their rules on code style, comments, language and migrations win over your own habits.
- Work only on the current branch. Do NOT push, merge, rebase, switch or create branches, and do not touch the main branch.
- Do only what this prompt asks; no unrelated refactors, renames or formatting changes.
- Do not delete or weaken existing tests to make them pass.
- Do not add packages unless the prompt asks. Do not edit `.env` files or commit secrets. Do not commit untracked files you did not create.
- Never change or delete data in a database by hand (SQL DELETE/UPDATE/TRUNCATE/DROP through a client or `docker exec`); those commands are blocked. If a test fails because of leftover or existing data, stop and report it with `BLOCKED:` instead of cleaning data.
- Do not stop, restart or remove Docker containers (these commands are blocked). You may rebuild and start services the way the prompt or project docs say (e.g. `docker compose up -d --build <service>`) and run the tests the prompt lists; fix the code until they pass.
- One commit per fix, short imperative commit message in the language the project uses; keep the configured git author.
- Before finishing run the unit tests and, if you touched the frontend, lint/test/build, using the commands the prompt or the project docs give.
- If something is unclear, do not guess: stop and end your answer with `BLOCKED: <reason>`.
- Finish with a short report: commits (hash + message), test results with numbers, anything you could not do.
