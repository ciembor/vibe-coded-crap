# Refactoring Plan

1. [x] Consolidate JSON persistence into a shared file-store abstraction and migrate every JSON-backed store onto it.
2. [x] Extract CLI command routing out of the monolithic loop into small command handlers with a shared execution interface.
3. [ ] Split the ticket domain rules out of `Store` and `Ticket` into focused services for relationships, hierarchy, dependencies, workflow, SLA, escalation, and import/export.
4. [ ] Reduce model-level normalization duplication by moving reusable validation and coercion helpers into shared domain modules.
5. [ ] Add automated coverage for persistence, domain rules, workflow validation, CLI dispatch, and import/export behavior.
6. [ ] Remove dead code, tighten require boundaries, and finish with a minimal public surface and documented command flow.
