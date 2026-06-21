# Vibekube Progress

This file tracks implementation status across all phases. Keep this updated whenever a meaningful implementation checkpoint lands.

## Phase Status

| Phase | Plan | Status | Current Checkpoint |
| --- | --- | --- | --- |
| 0 | [Project Foundation](PHASE0.md) | Review checkpoint | Native shell foundation builds; focused non-UI tests pass with preview fixtures |
| 1 | [Kubeconfig Discovery](PHASE1.md) | Review checkpoint | App loads kubeconfig contexts, including exec/Teleport metadata; parser and model tests pass |
| 2 | [Kubernetes API Connectivity](PHASE2.md) | Review checkpoint | Native client connects, runs exec auth with signing-in progress, discovers API resources, loads namespaces, and has focused API-client transport tests |
| 3 | [Main App Shell](PHASE3.md) | Review checkpoint | NavigationSplitView shell has persisted top-level route state, grouped nav, searchable namespace switching, route-aware commands, detail/YAML shortcuts, and basic keyboard navigation |
| 4 | [Dashboard And Cluster Stats](PHASE4.md) | Complete for read-only release | Dashboard is intentionally limited to fast nodes/pods/discovery/metrics overview; richer workload/event/storage dashboard expansion is canceled |
| 5 | [Resource Browsing](PHASE5.md) | Review checkpoint | Generic resource list APIs and native read-only tables are available for common built-ins |
| 6 | [Resource Detail And YAML](PHASE6.md) | Review checkpoint | Bottom detail inspector has Overview, Events, Containers, expanded Environment, searchable/copyable/saveable YAML, Metadata, Conditions, masked Secret env reveal, owner jumps, selector-based related Pod navigation, and version-aware refresh |
| 7 | [Logs](PHASE7.md) | Review checkpoint | Pod detail inspector has rich logs: tail/since controls, live streaming with smart follow, timestamps, safe JSONL formatting, search, grep, copy, save, download-all, fullscreen, and previous-container logs |
| 8 | [Watches And Real-Time Updates](PHASE8.md) | Review checkpoint | Active watchable resource lists have watch merging, durable reconnect/backoff, live/stale/failure status, burst coalescing, version-aware detail refresh, narrow selected-resource detail watches, interaction-stable table ordering, subtle updated-row feedback, and manual validation |
| 9 | [Workload Debugging Basics](PHASE9.md) | Complete | Workload Overview includes event-aware debug summaries, visible `kubectl`-backed port-forward sessions, container-aware external-terminal Pod exec actions, and pod-local exec launch history |
| 10 | [Safe Mutations](PHASE10.md) | Complete | Safe mutations are implemented and visually QA'd: scale, rollout restart, typed-confirm delete, apply YAML from editor/file with server-side dry-run preview, structured Namespace/ConfigMap/Secret creation, RBAC/discovery-aware disabled states, and local action history |
| 11 | [Preferences, Security, Packaging](PHASE11.md) | Complete for read-only release | Release script, versioning, About version display, signing/notarization docs, diagnostics settings/export, kubeconfig path, appearance, table density, external terminal, log buffer, default namespace, resource watch, Secret reveal settings, reset preferences, privacy docs, secret-surface audit, clean-machine validation, sandbox/credential-storage decisions, no-automatic-crash-reporting policy, no pre-Phase-12 AI placeholder decision, and real Teleport/TLS validation exist |
| 12 | [AI Foundations](PHASE12.md) | In progress | Provider settings, Keychain secret storage, model discovery, redacted resource context, resource-scoped AI explain chat, and manual AI evaluation checklist are in place |
| 13 | [Advanced AI Operations](PHASE13.md) | Not started | Waiting for AI foundation |

## Current Execution Track

The implementation is intentionally allowed to take small cross-phase slices when user-visible gaps are found. That is why logs, release packaging, Teleport/TLS hardening, namespace search, and Env rendering landed before every item in Phases 4-6 was complete.

Vibekube 0.5.0 is released as a fast, read-only, distributable Kubernetes cockpit for real clusters. Phase 10 safe mutations are complete after visual QA on the demo cluster.

Recommended next focus:

1. Continue Phase 12 by completing visual QA and Linear sync once the external tools are available.
2. Keep Dashboard small and fast unless the product direction explicitly changes.
3. Treat Phase 10 as done, with any new mutation UX issues tracked as follow-up bugs instead of reopening the phase.

Current stop rule: after any visible UI slice, stop for manual review before moving to the next feature family.

## Global Progress

- [x] Create high-level roadmap.
- [x] Create detailed phase implementation plans.
- [x] Keep existing scaffold and demo cluster untouched while planning.
- [x] Replace scaffold UI with Vibekube app shell.
- [x] Parse kubeconfig and show contexts.
- [x] Recognize exec/Teleport kubeconfig auth as a supported planned path.
- [x] Connect to demo cluster.
- [x] Discover Kubernetes API groups/resources.
- [x] Load namespaces and expose namespace scope.
- [x] Search/filter namespaces from the toolbar selector.
- [x] Browse resources.
- [x] Inspect, copy, and save YAML.
- [x] Show dashboard health summaries from live cluster resources.
- [x] Stream logs.
- [x] Search, grep, tail/since filtering, smart live follow, safe JSONL formatting, copy, save, download, fullscreen, and previous-container Pod logs.
- [x] Inspect Pod container state, restarts, probes, volume mounts, and resource requests/limits.
- [x] See event-aware workload debug summaries with scheduling/QoS context for common unhealthy signals.
- [x] Start and stop visible `kubectl`-backed port-forward sessions from resource detail.
- [x] Open container-aware external-terminal `kubectl exec` shells from Pod context menus, Pod overview, and container detail.
- [x] Choose the preferred external terminal app for exec shells.
- [x] Keep Pod exec launch history visible in Pod detail.
- [x] Stop active port-forward sessions on app quit.
- [x] Connect to real Teleport-backed corporate clusters through kubeconfig exec auth.
- [x] Package signed/notarized DMG builds through `scripts/release`.
- [x] Expand Pod `envFrom` ConfigMap and Secret keys in the Env inspector.
- [x] Add first real-time Pods list watch updates.
- [x] Add local diagnostics/log export with secret redaction.
- [x] Follow Kubernetes list pagination for large clusters.
- [x] Show cancellable resource-list loading progress for slow large-cluster lists.
- [x] Add watch reconnect/status UI for the active Pods list.
- [x] Refresh open resource details when the watched list row resourceVersion changes.
- [x] Add broader active-resource list watches.
- [x] Add true selected-resource detail watches.
- [x] Preserve visible table order while inspecting watched resources.
- [x] Keep active watches recovering after idle/background transport timeouts.
- [x] Show subtle updated-row feedback for watched resource changes.
- [x] Add clean-machine release checklist and privacy note.
- [x] Complete the read-only secret-surface audit across kubeconfig parsing, API/client errors, diagnostics, Secret YAML, and Secret reveal logging.
- [x] Validate daily use on a non-development work Mac since version 0.3.0.
- [x] Decide credential storage and sandbox strategy for the current direct-distribution release.
- [x] Decide crash reporting and AI settings placeholder policy for the current direct-distribution release.
- [x] Release Vibekube 0.5.0 and complete post-release smoke validation.
- [x] Clear Swift concurrency warnings before starting mutation/write paths.
- [x] Add mutation API foundation with dry-run request support and Kubernetes Status error handling.
- [x] Add non-UI mutation preview foundation with YAML validation, server dry-run, diff output, and conflict mapping.
- [x] Add visible highlighted YAML draft editing with server-side dry-run diff preview, rendered-YAML parser coverage, and validation/error surfacing, without apply.
- [x] Add confirmation-gated apply for existing-resource YAML edits with draft search, split/expanded diff preview, post-apply refresh, and focused apply tests.
- [x] Add safe mutations.
- [x] Add AI provider settings, secure key/header storage, provider model discovery, and availability testing.
- [x] Add redacted selected-resource AI explain chat.
- [x] Add AI explain/summarize flows.

## Checkpoint Rules

- Stop for user feedback after each phase slice that changes visible app behavior.
- Stop before introducing a new major dependency.
- Stop before changing persistence strategy or deployment target.
- Stop before implementing write operations against a cluster.
- Stop before enabling any AI request path that can send cluster data outside the machine.
