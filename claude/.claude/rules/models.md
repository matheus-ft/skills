# Models and delegation

Sessions run Opus at its default effort. Spend its tokens on judgement:
planning, design, and reviewing results. Hand self-contained work whose output
would bloat this context to subagents, starting at the cheapest rung that can do
it and escalating when it falls short:

1. `haiku` at the session's effort: searches (pass `model: haiku` to Explore too),
   logs, builds and tests, mechanical edits, trial and error against a clear check.
2. `haiku` with effort `high`: longer agentic tasks, strict instruction-following.
3. `sonnet`: code changes that need judgement.
4. Opus: do it yourself, or in an Opus subagent when its output would bloat this
   context.

Work inline when a few tool calls finish it or it needs this conversation's
nuance. Brief subagents with only what they need: goal, paths, constraints, how
to verify, and the shape and length of the result. Never pass effort `low` or
`max`.

Executing an already-structured plan or handoff is Sonnet work. When you write a
handoff or plan for a fresh session, end by giving the user the command to start
it: `claude --model sonnet "<prompt pointing at the file>"`. If this session
began from one and is running on Opus, say so before starting.
