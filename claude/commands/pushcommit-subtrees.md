---
description: Commit pending changes, push, and push all subtree mirrors
disable-model-invocation: true
context: fork
agent: general-purpose
model: haiku
---

Commit pending changes following the commit conventions in CLAUDE.md, then `git push`. Then invoke `subtrees-push.sh` directly (it's on PATH) — do not wrap with `bash`.
