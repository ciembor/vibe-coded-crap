# Refactoring Plan

This plan is intentionally unchecked. Mark a stage only after that stage has actually been completed.

- [x] Stage 1: Establish a characterization test suite.
  Add public-contract tests around tickets, stores, CLI smoke paths, imports, workflows, API tokens, hooks, webhooks, plugins, notifications, and reporting before changing behavior.
- [x] Stage 2: Centralize JSON persistence.
  Move JSON loading, default payloads, directory creation, atomic writes, parser recovery, and ID allocation into one storage abstraction used by all stores.
- [x] Stage 3: Introduce owned record objects for stored hashes.
  Hide normalization and validation for hooks, webhooks, plugins, API tokens, users, templates, ticket child records, and log entries behind cohesive objects.
- [x] Stage 4: Split ticket policy from ticket state.
  Move workflow, SLA, escalation, reminder, duplicate detection, ticket-type validation, and transition permission rules out of `Ticket` into policy objects.
- [x] Stage 5: Deepen ticket persistence.
  Refactor `Helpdesk::Store` into a repository with focused services for merge/import, relationships, hierarchy, dependencies, bulk actions, and undo.
- [x] Stage 6: Replace the CLI dispatcher with a command registry.
  Preserve the command surface while replacing the large case statement with a command table, aliases, permissions, and handler objects.
- [x] Stage 7: Extract CLI command groups.
  Move ticket, search/filter, workflow, reporting, user/session, API/token, plugin/hook/webhook, and profile workflows into cohesive command modules.
- [x] Stage 8: Separate presentation from behavior.
  Move list rows, dashboards, reports, activity output, API JSON responses, and menu rendering into presenters.
- [x] Stage 9: Isolate integrations and side effects.
  Encapsulate shell execution, plugin command rendering, webhook delivery simulation, audit logging, email mock behavior, and debug output behind service interfaces.
- [x] Stage 10: Consolidate application configuration.
  Replace scattered profile/session/environment/data-directory setup with an application context object that owns initialization order and paths.
- [x] Stage 11: Broaden behavior coverage.
  Add tests for every command group and domain service, including import conflicts, workflow permissions, API rate limits, cache invalidation, notifications, plugins, hooks, and webhooks.
- [x] Stage 12: Final simplification pass.
  Remove dead code, shallow wrappers, duplicated parsing, inconsistent names, and comments that compensate for confusing interfaces.
- [x] Stage 13: Release-quality verification.
  Run the full test suite, syntax checks, and CLI smoke tests from a clean profile directory.
