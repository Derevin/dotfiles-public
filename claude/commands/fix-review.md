---
allowed-tools: Read,Edit,Write,Bash
description: Address review findings — fix clear items, ask about judgment calls
---

Follow-up to `/review-branch`, `/review-branch-medium`, or `/review-branch-max`. Act on the findings already in the conversation.

## Steps

1. **Categorize each finding** into:
   - **Fix now** — clear-cut: typos, dead code, obvious bugs, small consistency/naming fixes, missing null guards, simple renames, docstring/comment corrections.
   - **Ask** — judgment calls, architectural shifts, refactors, anything where intent matters or a single change affects many files.

2. **Fix the "Fix now" items.** Edit directly. Don't commit — leave changes in the working tree for the user to inspect.

3. **Ask about the leftovers.** List each deferred item as a short bullet:
   - `file:line` — one-sentence description
   - proposed fix (one line)

   Then stop and wait for the user's call.
