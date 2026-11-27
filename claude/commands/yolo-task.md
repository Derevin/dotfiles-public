---
allowed-tools: Bash(taskania *),Read(~/repos/tasks/**)
description: Plan a todo task unattended in a subagent, taking every recommendation as your answer, then implement it through to the handoff
disable-model-invocation: true
---

Take a task from `todo/` to an `/implement-task` handoff in one run: a planner subagent grills the task alone, its every recommendation taken as the user's answer, then this session implements the plan. The user enters the loop at the handoff, where the decisions made for them are listed for reopening.

1. **Pick.** An id in the arguments (`039`, `039-some-slug`, or the filename `N039-some-slug`) names the task: resolve it to the filename in `todo/`. Otherwise run `taskania list --status todo` and take the first. If it has `Depends:` and any of those IDs is missing from `done/`, stop and report which.

2. **Claim.** Run `taskania claim <filename>` — moves it to `planning/`, commits, outputs the task content.

3. **Frame.** The body is the spec: go straight to step 4, no recap. A **reminder-only task** (just `# Title`, no real body) is the one stop: ask the user what it's about and wait. Their answer is the framing.

4. **Plan.** Spawn one `general-purpose` subagent with `model: "fable"` and `effort: "medium"`, `/plan-task`'s lab settings — `model: "opus"` instead when `fable-usage.sh` prints more than 95. Prompt it: *Invoke `/yolo-plan` and follow it.*, then the task filename, `--claude` if this command's arguments carry it, and the user's step-3 framing if there was one. It returns a park — the decided-unasked Q headlines and any doc proposals — or a bail. On a bail, show the user its reason and stop; the task stays in `planning/`.

5. **Implement.** Invoke `/implement-task <filename>`, passing on `--claude` if this command's arguments carry it, and follow it through. At its **Hand off**, between the counts line and the review's numbered list, list the planner's Q headlines under **Decided for you** — their `Q<n>` labels keep a reply's reference apart from the review's numbers — then its doc proposals as yes/no items. In **Revise**, a reopened Q is feedback like any other; write accepted docs via `context-commit.sh`.
