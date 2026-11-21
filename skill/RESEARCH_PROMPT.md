You are preparing a fact sheet for another developer. Do NOT change any file, do NOT commit. Only read code and docs (CLAUDE.md / AGENTS.md first).

Goal to research:
<<<GOAL
{{GOAL}}
GOAL>>>

Produce a fact sheet with exactly these sections:
1. RELEVANT FILES: path — one line on its role.
2. CURRENT BEHAVIOR: for each function/endpoint/table involved: `path:line` + signature + what it does today (quote the key lines of SQL or code, max 15 lines each).
3. CALLERS AND DEPENDENTS: who calls the functions above; other features that would be affected by a change.
4. DATA: tables/columns/JSON shapes involved, with types, from the migrations.
5. TESTS: existing unit and e2e tests that cover this area (file + test name/section) and how to run them (exact commands from the project docs).
6. PITFALLS: project rules and framework pitfalls from the docs that apply to this change.
7. OPEN QUESTIONS: decisions a developer would have to make; list options, do not decide.

Be precise and factual; cite `path:line`. Do not propose an implementation beyond the open questions.
