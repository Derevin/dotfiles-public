Number each question and give your recommended answer. Start at Q1 and count up across the session so a number in my replies names exactly one question.

Format each question like so:

```
❓ **Q<n>** <question as a clause> → **<recommendation>**, <why>

<body: the lettered options, if any; what backs the recommendation — facts found, costs, rejected options' downsides; omit when the headline carries everything>
```

The headline is the **quickfire**: assume I read only the headlines, so each must be answerable without its body.

- Name the concrete thing, not shorthand only the body explains.
- Lettered options go in the body, never the headline. The headline names the pick by letter and meaning, so it still reads alone: `❓ **Q3** Fold cancel/stale into move? → **(a) delete both**, move is already the primitive`
- The why is mandatory: the reason, not the recommendation reworded.

A later message that changes a question or its recommendation restates that question's headline.

### Decision tiers

- **Asked** decisions get numbered questions. Ask when a choice changes observable behaviour or scope, is costly to reverse, or has no confident pick. Fine UX details like hint text, markers, and key bindings count as observable behaviour, as do product and tool names.
- **Defaulted** decisions fall below that bar and are worth showing me so I can object.
- **Never raised** decisions belong to the implementer. Leave them out of the session and plan.

These examples are starting points; the asked bar overrides them, except that observable behaviour alone doesn't make error handling asked.

- Leave automated test design and fixtures to the implementer.
- Default manual tests and other steps I'd have to do by hand. Say what I'd have to do.
- Default error and failure handling, internal code structure, and internal names.
- Side work (follow-up tasks, Asana posts, drive-by doc fixes): when you'd recommend it, default to "no task" and name the work; otherwise don't mention it.
- Leave PR and commit shape to the implementer when one PR is obvious. If a split is worth considering, default to "one PR" and name the split.

Post any defaults in one block after the questions, headed **Defaults, unless you object**, one per line as `**D<n>** <pick>, <why>`, counted from D1 up across the session, separately from Q numbers. The asked decisions are mine. Wait for my reply to every round, including a round with only the defaults block. A default settles when I reply to its round without objecting to it, but only if that reply answers all of the round's questions or all but one. Otherwise treat it as unseen, not accepted, and repost it next round under the same D number. If I object, retire its D number permanently and ask it as a full question next round under the next Q number. A decision that depends on an open question or an unsettled default waits for a later round.

Finding *facts* is your job, never mine. When a decision needs a fact from the environment, dispatch a subagent to find it rather than asking me something you could look up: `recon` for anything in the code or the repo, `general-purpose` for what recon's tools can't reach (the web, running something). Never a fork — it copies this whole conversation onto the session's model. When you dispatch an exploration, wait until every running subagent has finished before posting the round — a round posted while agents are still landing gets mangled by their output and I have to reask.
