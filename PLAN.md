# Refactoring Plan

This plan treats reduced complexity as the success metric. Each stage should leave the application easier to understand, change, and verify than it was before the stage started. A checked box means the stage was completed and committed.

- [x] Stage 1: Establish a safety net and explicit refactoring path.
  Add characterization tests for the core ticket model, ticket persistence, and external dispatch stores; document the full staged refactor so later changes are checked against stable behavior.
- [x] Stage 2: Centralize JSON file persistence.
  Replace repeated `load_data`, `save!`, directory creation, and `next_id` code with one deep persistence module that owns JSON parsing, default payloads, atomic writes, sorting, and ID allocation.
- [x] Stage 3: Move external records into owned value objects.
  Extract event subscription, hook, webhook, plugin, and API token normalization so stores expose semantic operations without owning wildcard matching, command rendering, token creation, or rate-window mutation details.
- [x] Stage 4: Move ticket child records and type validation into owned objects.
  Move comments, internal notes, attachments, and ticket-type required-field rules behind cohesive objects so `Ticket` no longer owns nested row shapes or type-specific validation tables.
- [ ] Stage 5: Split operational ticket policy from ticket state.
  Move workflow, SLA, escalation, reminder, and duplicate rules behind cohesive policy objects so `Ticket` is responsible for ticket state and small domain mutations only.
- [ ] Stage 6: Deepen `Helpdesk::Store`.
  Turn ticket persistence into a repository with a small public contract, then move merge/import, relationship management, bulk actions, and dependency closure checks into focused domain services that hide row indexing and raw hash mutation.
- [ ] Stage 7: Replace the CLI command switch with a command registry.
  Introduce a command table that maps command names and aliases to command handlers, preserving the existing command surface while removing the central 100-branch dispatcher.
- [ ] Stage 8: Extract CLI command groups around user workflows.
  Move ticket, search/filter, workflow, reporting, user/session, API/token, plugin/hook/webhook, and profile commands into cohesive command modules with shared prompting and permission contracts.
- [ ] Stage 9: Isolate presentation from behavior.
  Move row formatting, reports, dashboards, activity rendering, API JSON rendering, and interactive menu output behind presenters so command handlers orchestrate use cases instead of building strings inline.
- [ ] Stage 10: Isolate integrations and side effects.
  Hide shell execution, webhook delivery simulation, plugin command rendering, audit logging, email notification mock behavior, and debug output behind service interfaces that are easy to stub and verify.
- [ ] Stage 11: Make configuration explicit and low-friction.
  Consolidate profile, session, environment, and data-directory setup into one application context object so ordinary callers do not need to know initialization order or storage paths.
- [ ] Stage 12: Expand behavior coverage through public contracts.
  Add tests for every command group and domain service, including import conflict resolution, workflow permissions, API authentication/rate limiting/cache invalidation, hooks/webhooks, plugins, and notification suppression.
- [ ] Stage 13: Final simplification pass.
  Remove dead code, shallow wrappers, duplicated option parsing, unused public methods, and inconsistent names; update comments only where they explain contracts, invariants, or hidden decisions.
- [ ] Stage 14: Release-quality verification.
  Run the complete test suite, syntax checks, and CLI smoke tests from a clean profile directory; ensure `PLAN.md` is fully checked and every completed stage has its own commit.
