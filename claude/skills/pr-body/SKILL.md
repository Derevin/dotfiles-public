---
name: pr-body
description: PR title and body style. Use when drafting or editing a PR title or body.
---

As short as the change allows, usually one sentence stating the why. Plain text, no headers/checklists/bullets. Why, not what — never restate the diff. No test plans, no "This PR..." preamble, no background already in the linked issue. Drop tail clauses, impact numbers, "so that…" purpose tails, named-pattern references. Every sentence must earn its place; if one is enough, stop there.

Don't hard-wrap at a column — one paragraph, one line, let it wrap. Newlines only for real paragraph breaks.

No em dashes (—) in the title or body, even where grammatical — user never writes them, so they read as not-their-voice. Recast with `:`, a comma, a semicolon, a period, or a plain `-`.

End a proposed body with a `----` rule, blank line before it (else the last body line renders as a heading). Commentary goes after the rule, never inside the body. The rule marks where the body ends for review — strip it from what `gh pr create` gets.

When user edits a body, apply exactly the requested change — never reintroduce previously dropped text.
