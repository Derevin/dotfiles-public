---
description: Deep-review the branch in a fork — the diff and the reviewer reports die there, only the judgment calls come back
context: fork
background: false
agent: general-purpose
---

Run the deep review in isolation. You inherit the whole conversation — the task file, the context store, the plan and the steers behind it — and the diff you fetch, the reports you collect, and the fixes you apply all die with this fork. Only what you return survives.

**Fan out.** The review is a multi-perspective fan-out; dispatching those reviewers is the work you were given, not a way of passing it on. Run them.

**You cannot ask.** The user isn't reachable from here. What needs their call comes back in your return, not as a question.

1. **Review.** Invoke `/review-branch-medium`. If a converge loop ran before you, treat it as unrelated: you are the independent backstop, and what it dropped is deliberately not yours to know. Don't skip a perspective because something upstream already called the diff clean.

2. **Gate.** Sort every finding on cost of being wrong, not on how weighty the idea sounds. A cheap, locally revertible change is cheaper to make than to return a question about — the user inspects the working tree either way.

   - **Apply** if any holds: it's a defect (wrong behaviour, missing guard, dead code); it violates a documented rule (CLAUDE.md, CONTEXT.md, an ADR); or it's cheap, local, revertible in one hunk *and* the pattern it proposes already exists elsewhere in the repo.
   - **Drop** if any holds: no defect, no documented rule, and no in-repo precedent — taste with nothing behind it; it targets pre-existing code the diff merely touched rather than introduced; or it adds an abstraction, parameter, or hook with no second call site in the diff.
   - **Ask** only what survives both: wide blast radius *and* a real argument behind it.

   The in-repo precedent test carries the most weight — "the codebase already does this" is what separates consistency from novelty. Check it, don't assume it.

3. **Apply that bucket.** Edit directly, in place. Don't commit — leave the changes in the working tree for the user to inspect.

4. **Return.** The **Ask** bucket as a numbered list, each item `file:line — one-line description — proposed fix — strongest case against`. If the against-case is plainly stronger, the item was a **Drop** — resolve it there rather than returning it. Then one line for how many findings you applied and how many you dropped. Nothing else: no walk through the diff, no recap of the review.
