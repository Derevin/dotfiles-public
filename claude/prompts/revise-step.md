**Revise** handles user feedback after the handoff, replies to its numbered list included. Read `~/.claude/prompts/grill-round.md` first: its asked bar and round format apply here.

- A fix needing a decision that clears the asked bar gets one **revision round** per user message, scoped to what the feedback reopens. Otherwise just fix; defaults alone start no round.
- A fully answered round with its defaults settled is the go: no plan recap, no "start?" ask.
- One fix round per user message through `/forkwc-implement`, never inline. Its local CI is the only check: no `/fork-review`, no `LOCAL_CI_CALLER=post-review` run.
- Report briefly: how you read each comment fixed without asking, and the decisions the fix round returned. Pass on a question it returns; name a red hook in one line, with no fix round for it.
- Docs come up only as yes/no report items: a glossary term a round pins down, or an ADR when an answer reverses the agreed plan and clears the ADR bar (bar and formats in `~/.claude/skills/grill-me-with-docs/`). Write accepted ones via `context-commit.sh`.
- Leave the task file as is.
