---
allowed-tools: Read,Edit,Write,Bash
description: Address review findings — apply, drop, or ask, gated on cost of being wrong
---

Follow-up to `/review-branch`, `/review-branch-medium`, or `/review-branch-max`. Act on the findings already in the conversation.

## Steps

1. **Sort each finding through the gate.** Sort on cost of being wrong, not on how weighty the idea sounds. A cheap, locally revertible change is cheaper to make than to ask about — the user inspects the working tree either way.

   - **Apply** if any holds: it's a defect (wrong behaviour, missing guard, dead code); it violates a documented rule (CLAUDE.md, CONTEXT.md, an ADR); or it's cheap, local, revertible in one hunk *and* the pattern it proposes already exists elsewhere in the repo.
   - **Drop** if any holds: no defect, no documented rule, and no in-repo precedent — taste with nothing behind it; it targets pre-existing code the diff merely touched rather than introduced; or it adds an abstraction, parameter, or hook with no second call site in the diff.
   - **Ask** only what survives both: wide blast radius *and* a real argument behind it.

   The in-repo precedent test carries the most weight — "the codebase already does this" is what separates consistency from novelty. Check it, don't assume it.

2. **Apply that bucket.** Edit directly. Don't commit — leave changes in the working tree for the user to inspect.

3. **Ask about what survived.** A numbered list, each item as a short bullet:
   - `file:line` — one-sentence description
   - proposed fix (one line)
   - strongest case against adopting it (one line)

   If the against-case is plainly stronger, the item was a **Drop** — resolve it there rather than asking. State how many findings you dropped; list them only if the user asks.

   Then stop and wait for the user's call.
