# Mission Logs

Detailed session logs documenting exploratory work, design journeys, and
implementation adventures -- what happened, why decisions were made, and what
was learned. Written for future us: the goal is to allow yourself to forget,
then find it again.

Mission logs are our tracer bullets:

> "In the Captain's Log you will find a detailed description of what our
> product team is building and the intention behind our product decisions.
> The audience of the Captain's Log is future Captains."
> -- Steve SCHNEPP, [Mission Logs are our Tracer Bullets - Always Use Them](https://blog.pwkf.org/2023/02/15/mission-logs.html) (2023)

Three purposes:

1. **Show where your bullets land** -- document the current position, what
   was tested, and which assumptions need to change. In a PoC, the journey
   IS the result.
2. **Show where others' bullets land** -- so teammates avoid retrying your
   failures and can aim for different paths.
3. **Deter "this can't be done" critics** -- showing you're working silences
   most arguments about whether it should be tried.

Even failed experiments produce valuable knowledge when logged.

## Conventions

- One file per topic: `YYYY-MM-DD_topic.md` (short hyphenated slug).
- Multiple sessions on the same topic append as `## Session N: Title (date)`.
- Rules that emerge from a session may be promoted to `AGENTS.md` or project
  docs; reference them from the log.
- Significant architectural decisions may also get an ADR -- the log records
  the journey, the ADR records the decision.
