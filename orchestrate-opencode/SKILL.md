---
name: orchestrate-opencode
description: Claude as manager, opencode as worker. opencode writes the code; Claude writes the prompts, reviews the diff, runs the tests and pushes. Only when the user invokes /orchestrate-opencode; after that, every code task in that session follows this flow.
disable-model-invocation: true
---

# Orchestration: Claude manages, opencode works

Task: $ARGUMENTS

You do not write code. Planning, prompts, review, tests and push are yours; code is opencode's.
The worker is assumed to be much cheaper than you: give it everything it can do (code, tests, docs/README, scripts, research/code reading, progress-note drafts). What stays with you: prompts, review, final tests, push/merge, talking to the user, and the worker's own setup (these skill files).
This mode lasts until the end of the session: unless the user says otherwise, later code tasks in this session follow the same flow.
If the task above is empty, ask the user what to work on (offer candidates from the project's progress notes if there are any).

Script: `bash ~/.claude/skills/orchestrate-opencode/worker.sh <prompt-file> [session-id]`
It runs in the repository root on the current branch, appends `WORKER_RULES.md` to the prompt, and applies the permissions in `worker-opencode.json`. Model, variant and limits come from environment variables or `worker.local.env` (see the header of `worker.sh`); do not change them unless the user asks.

## Flow

1. **Prepare:** Read the project's `CLAUDE.md` / `AGENTS.md` and its progress notes if any; learn the test commands and pitfalls there. Be on a feature branch that matches the user's git rules (create one from the main branch if needed). The working tree must be clean.
2. **Research (medium/large tasks):** Do not scan the code yourself. Fill `{{GOAL}}` in `RESEARCH_PROMPT.md`, write it to the scratchpad, run it with `WORKER_AGENT=plan WORKER_TAIL=200` in a new session, and read the fact sheet it returns (file:line, current behavior, tests, pitfalls, open questions). Open only the places that look suspicious yourself. Decide the open questions yourself.
3. **Write the prompt:** An English `<id>.md` in the scratchpad: branch, numbered items; for each item the file/function names, the cause of the problem, the expected behavior and the test to add; at the end the verification steps: the project's unit/frontend test commands and **the e2e/integration tests related to this task** (if needed the worker rebuilds the changed services, runs the tests itself and fixes the code until they pass; it cannot stop containers). Take the commands from the project docs and copy them into the prompt verbatim.
   - The worker is a weaker model than you: leave nothing to inference. For every item give the full file path, function/class name, current behavior and why it is wrong, the wanted behavior (signature, SQL fragment, example input → output if useful), what must not be touched, the test name and what it asserts. Copy the project's and the environment's (OS, shell) pitfalls that concern the item into the item; do not rely on the worker reading them. Make every open decision yourself.
   - **Large task** (new phase, architectural debt, multi-file design): first run with `WORKER_AGENT=plan`; the worker returns a plan without writing code. Review it, then send the corrected plan to the same session with "implement this plan" and `WORKER_AGENT=build`.
4. **Run:** Start the script in the background (`run_in_background`); you are notified when it finishes. Do not poll. Give the user a short status.
5. **Review (without running tests):**
   - Check the **risky commands** section of the script output: if a command changed data, deleted files or wrote outside the repository, confirm from the log what it did and tell the user.
   - **Second-eye review:** fill `REVIEW_PROMPT.md` with `{{TASK}}` = the prompt you sent and `{{BASE}}` = the `HEAD` the script printed; run it with `WORKER_AGENT=plan WORKER_TAIL=200` in a **new** session. Verify every finding yourself and discard false alarms.
   - Then read `git diff <HEAD>..HEAD` line by line yourself and apply the checklist below.
   - Checklist: missing or different items; edge cases (null/empty, numeric vs. string types, dates and time zones); concurrency (is every statement in the transaction, check-then-act races, half-finished operations); idempotency of repeated jobs (same day / same key written twice); docs and UI text match the code (e.g. "daily" but runs hourly); performance (a query per keystroke/request, unbounded loops); would the tests pass with a broken implementation; security; out-of-scope changes; project rules (comments, language, migrations, framework pitfalls); uncommitted files.
   - If there are problems: write a fix prompt, run the script with the developer's `SESSION`, review again (including the second eye). Do not run tests at this stage.
   - If it is not fixed after three rounds, stop and ask the user; do not write the code yourself.
6. **Test (after the review passes):**
   - Run the unit tests yourself (with the command from the project docs).
   - If the frontend changed: lint, test, build.
   - Rebuild the changed services and run the related e2e tests in order; respect the project's test pitfalls (order, rate limits, waits); start services that are down.
   - A test that fails because of the code → turn the finding into a prompt, send it to the same session, go back to step 5.
7. **Push:** If everything passes, push the branch and watch CI (e.g. `gh run watch`). Merge into the main branch only with the user's approval and following the user's git rules.
8. **Close:** Update the project's progress notes if it has them. Report to the user: commits, what you sent back during review, test results (with numbers), what you did not run and why, push/CI status.

## Session management (your decision, do not ask the user)

- New, independent task → new session (run the script without a session id).
- Fix round of the same task, plan → build, test failure → same `SESSION`.
- Session too long (many rounds, big diff, worker confused or repeating the same error, locked onto a wrong approach) → new session; put a short status summary, the remaining items and the existing commits into the prompt.
- Sessions are cheap: do not avoid a new session when a clean context gives a better result.
- In the report, say which task was done in which session.

## Small tasks

- Do not send small, clearly scoped fixes (a few lines) right away: collect them in a list for the session (show the list to the user). When the list reaches 4-6 items or the user says "send", do them in one prompt, one worker run, one commit per item.
- Urgent small task (breaks CI/tests, blocks work) → a one-item worker run.
- For small tasks skip research (step 2) and the second eye; never skip your own diff review and the tests. The prompt may be short but the detail rule still applies (file, line, expected behavior).
- Do not write the code yourself; small tasks also go to the worker.

## Rules

- The worker's permissions are in `worker-opencode.json` (the script passes it via `OPENCODE_CONFIG`): push/merge/rebase/branch switching, `gh`, stopping/removing containers, `rm -rf`, and manual SQL DELETE/UPDATE/TRUNCATE/DROP/ALTER are denied. These are pattern matches, not a sandbox; the review step is still required. Never let the worker edit this file.
- Before changing the skill files, tell the user what will change and why, and get approval.
- Do not set time limits per run (`WORKER_TIMEOUT` / `WORKER_STALL` only if the user asks): the script stops the worker when its log has not grown for 20 minutes (`STALL`) and after 90 minutes in total (`TIMEOUT`). Do not check on the worker periodically; you are notified when it finishes.
- On `STALL` / `TIMEOUT` read the end of the log: if it hung on one command, continue the same session; if it is confused or repeating itself, open a new session.
- Do not read the whole worker log; the summary, commit list and stat are enough. Read the full diff only during review.
- Do not change the model or variant unless the user explicitly asks.
- One worker at a time per repository (branch and local services are shared).
