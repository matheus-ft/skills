# Documentation

Docs have two readers:

- **Humans** need to know how to use and navigate the code, why a design was
  chosen, and where things come from.
- **Agents** need only what the code cannot say.

The code, with its comments, explains itself; docs never restate it.

- Comments say why, not what.
- Each fact has one home. Docs point at code by path rather than repeating its
  values or steps.
- Docs hold:
  - rationale and rejected alternatives, and only if relevant;
  - contracts with things outside the code (formats others read, behaviour of
    external services);
  - steps done outside the code;
  - navigation over the codebase.
- A spec written before its code is pruned to the above once the code exists.
- A change to code updates or deletes the docs that mention it, in the same
  change.
