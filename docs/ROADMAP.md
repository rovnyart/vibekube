# Vibekube Implementation Roadmap

Vibekube is a native macOS Kubernetes client focused on speed, clarity, and local-first workflows. The first milestone is to reach the basic day-to-day capability of tools like Aptakube or OpenLens: discover kubeconfig contexts, connect to clusters, browse resources, inspect YAML, view logs, and understand cluster health. Later milestones add write operations, richer debugging workflows, and AI-assisted operations.

This roadmap assumes the current app is a fresh SwiftUI/Xcode scaffold and that `dev/k8s` provides a disposable kind cluster for development.

## Progress Tracking

- Overall progress: [PROGRESS.md](PROGRESS.md)
- Phase implementation plans:
  - [Phase 0: Project Foundation](PHASE0.md)
  - [Phase 1: Kubeconfig Discovery And Cluster Selection](PHASE1.md)
  - [Phase 2: Kubernetes API Connectivity And Discovery](PHASE2.md)
  - [Phase 3: Main App Shell And Navigation](PHASE3.md)
  - [Phase 4: Dashboard And Cluster Stats](PHASE4.md)
  - [Phase 5: Resource Browsing](PHASE5.md)
  - [Phase 6: Resource Detail, YAML, Events, And Relationships](PHASE6.md)
  - [Phase 7: Logs](PHASE7.md)
  - [Phase 8: Watches And Real-Time Updates](PHASE8.md)
  - [Phase 9: Workload Debugging Basics](PHASE9.md)
  - [Phase 10: Safe Mutations](PHASE10.md)
  - [Phase 11: Preferences, Security, And Packaging](PHASE11.md)
  - [Phase 12: AI Foundations](PHASE12.md)
  - [Phase 13: Advanced AI Operations](PHASE13.md)

## Product Principles

- Native first: SwiftUI, AppKit interop only where it materially improves a macOS workflow.
- Fast startup: parse kubeconfig and show available clusters immediately, even before any cluster calls finish.
- Safe by default: read-only browsing comes before mutating actions; destructive operations require confirmation and clear context.
- Dense but calm: Kubernetes has a lot of information, so screens should favor scannable tables, stable sidebars, compact inspectors, and keyboard-friendly navigation.
- Progressive power: basic users can browse and inspect; advanced users can filter, diff, edit, exec, port-forward, and automate.
- AI as a copilot, not a hidden operator: AI features should explain, summarize, suggest, and prepare actions before they execute anything.

## Design Direction

Vibekube should feel like a modern macOS professional tool rather than a web dashboard inside a window.

- Use SwiftUI scene structure with a native window toolbar, sidebar, split views, command menus, keyboard shortcuts, search, settings, and system color/material behavior.
- Adopt current macOS visual language, including Liquid Glass-aware controls and materials where appropriate, while protecting readability in resource-heavy tables and YAML/log views.
- Keep navigation and controls translucent or material-backed only when they do not reduce contrast. Dense data surfaces should use solid or subtle grouped backgrounds.
- Use SF Symbols for resource types, status, actions, and toolbar controls.
- Support light mode, dark mode, high contrast, reduced transparency, dynamic type where practical, and keyboard-only workflows.
- Prefer native table/list controls for large collections, with column sorting, resizing, selection, context menus, and quick look-style inspectors.
- Build a design system early: typography scale, status colors, resource icons, row density, spacing, empty states, error states, loading states, and destructive-action confirmation patterns.

Reference design inputs:

- Apple Developer: Liquid Glass overview, materials, macOS updates, and current Human Interface Guidelines.
- Aptakube/OpenLens: feature coverage and workflow expectations, not visual imitation.
- kubectl: mental model, terminology, and command parity for common read/debug tasks.

## Target Architecture

### App Layers

- `App`: scenes, commands, window management, menu actions, settings entry points.
- `Presentation`: SwiftUI views, view models, navigation state, user-facing formatting.
- `Domain`: cluster models, resource identity, watch state, health summaries, permissions, diagnostics.
- `KubernetesClient`: kubeconfig parsing, authentication, REST discovery, resource queries, watches, logs, exec, port-forward.
- `Persistence`: user preferences, recent clusters, pinned resources, saved filters, layout state, optional cache metadata.
- `Infrastructure`: process helpers, networking, certificate handling, file watching, logging, telemetry hooks if ever added.

### Technology Choices To Decide Early

- Kubernetes API implementation:
  - Prefer a native Swift client layer built around Kubernetes REST APIs, OpenAPI/discovery, async/await, and URLSession.
  - Use `kubectl` as a temporary adapter only if it accelerates early UI validation. If used, isolate it behind protocols so it can be replaced.
- Persistence:
  - Use SwiftData if the deployment target and project constraints allow.
  - Keep Core Data if the existing scaffold remains useful or if migration risk is lower.
- YAML:
  - Use a robust YAML parser/emitter rather than string manipulation.
  - Preserve formatting where possible for read-only views; structured editing can come later.
- Logging:
  - Use `OSLog` for app internals.
  - Implement Kubernetes pod/container logs as streaming async sequences.

## Phase 0: Project Foundation

Goal: turn the scaffold into a maintainable macOS app foundation without building product features yet.

### Deliverables

- Establish minimum macOS target and Swift version.
- Rename scaffold artifacts and remove sample `Item` UI/model code.
- Create module/folder structure for app, features, domain, Kubernetes client, persistence, and shared UI.
- Add dependency management strategy with Swift Package Manager.
- Add app icon placeholder and bundle metadata.
- Add basic CI-friendly build/test commands in documentation.
- Add developer setup notes for the kind demo cluster.
- Add local configuration for code formatting and linting if desired.

### Engineering Tasks

- Replace `NavigationView` scaffold with a modern macOS shell:
  - `NavigationSplitView` or equivalent sidebar/detail layout.
  - Toolbar with cluster picker, refresh, search, and connection status.
  - Placeholder views for cluster list, dashboard, resources, logs, and settings.
- Define app-wide environment objects/services:
  - `ClusterRegistry`
  - `ConnectionManager`
  - `ResourceStore`
  - `UserPreferences`
- Add unit test targets for pure domain logic.
- Add UI smoke test that launches the app and verifies the main shell renders.

### Exit Criteria

- App launches into a native macOS shell.
- Sample Core Data list is gone.
- Demo cluster docs are discoverable.
- Tests/build run cleanly from command line.

## Phase 1: Kubeconfig Discovery And Cluster Selection

Goal: automatically parse `~/.kube/config`, show contexts on startup, and let the user choose a cluster.

### Deliverables

- Kubeconfig parser for:
  - clusters
  - contexts
  - users
  - current context
  - namespaces
  - certificate authority data/path
  - client certificate/key data/path
  - bearer tokens
  - exec credential plugin metadata
  - legacy auth-provider visibility
- Startup cluster browser showing contexts grouped by kubeconfig source.
- Current-context preselection.
- Manual refresh and file watching for kubeconfig changes.
- Connection state model:
  - disconnected
  - connecting
  - connected
  - unauthorized
  - unavailable
  - certificate error
  - unsupported auth
- Clear onboarding/empty state when kubeconfig is missing.

### Engineering Tasks

- Create `KubeconfigLoader` with support for `KUBECONFIG` path lists and default `~/.kube/config`.
- Build typed models:
  - `KubeCluster`
  - `KubeContext`
  - `KubeUser`
  - `KubeNamespacePreference`
  - `KubeAuthMethod`
- Validate paths, decode base64 certificate data, and normalize server URLs.
- Implement secure handling for tokens and client keys; avoid logging secrets.
- Add a sidebar cluster/context list with search/filter.
- Persist recently selected context and namespace.

### UX Notes

- Show all contexts immediately after parse, before any network health checks complete.
- Use status badges for connection health.
- Treat Kubernetes `exec` credential plugins as supported planned auth, including Teleport `tsh` contexts.
- Keep truly unsupported auth visible with a useful explanation instead of hiding the context.

### Tests

- Unit tests for kubeconfig parsing, merged kubeconfig precedence, missing fields, malformed YAML, and secret redaction.
- Fixtures for the local kind context and representative cloud-provider kubeconfigs.

### Exit Criteria

- Starting the app shows available kubeconfig contexts.
- Selecting `kind-vibekube-dev` attempts a connection.
- Unsupported or invalid contexts fail gracefully.

## Phase 2: Kubernetes API Connectivity And Discovery

Goal: connect to a selected cluster and discover available API resources.

### Deliverables

- HTTP client for Kubernetes API server.
- TLS/certificate support based on kubeconfig.
- Authentication support for initial auth methods.
- Kubernetes `exec` credential plugin support for providers such as Teleport, EKS, GKE, and Azure.
- Teleport-friendly `tsh` flow: run the kubeconfig exec command and let browser SSO/MFA open when credentials are missing or expired.
- `/version`, `/api`, `/apis`, and API resource discovery.
- Namespace list loading.
- Permission-aware error handling.
- Request cancellation when switching clusters.

### Engineering Tasks

- Build `KubernetesAPIClient` around async/await.
- Define request builder:
  - API group/version/resource paths
  - namespace scoping
  - query parameters
  - pagination/continue tokens
  - timeout handling
- Implement typed wrappers for:
  - API discovery
  - namespaces
  - nodes
  - pods
  - services
  - deployments
- Add generic unstructured resource support for unknown kinds and CRDs.
- Add response/error models for Kubernetes `Status` objects.
- Implement exec credential runner:
  - resolve command paths and `installHint`
  - pass `exec.env` and `KUBERNETES_EXEC_INFO`
  - respect `interactiveMode`
  - decode `ExecCredential` v1/v1beta1
  - cache credentials until expiry and retry after 401
  - redact stdout/stderr and credential material

### UX Notes

- Show connection progress in the toolbar.
- Show a signing-in state when an exec credential plugin is running, especially for Teleport/browser auth.
- Display cluster version and active namespace near the dashboard header.
- Surface permission errors inline per resource group.

### Tests

- Unit tests for URL construction and response decoding.
- Unit tests for exec credential decoding, expiry, and redaction.
- Integration tests against the kind demo cluster where practical.
- Mock API server tests for auth, TLS, pagination, and error states.

### Exit Criteria

- App can connect to the demo cluster.
- App can connect through an exec-auth kubeconfig when the configured CLI is available.
- App can discover core, apps, batch, and custom API groups.
- Namespace list loads and can be selected.

## Phase 3: Main App Shell And Navigation

Goal: create the daily-use navigation model for clusters, dashboards, resource groups, and detail views.

### Deliverables

- Three-pane macOS layout:
  - cluster/context sidebar
  - resource navigation sidebar or section list
  - detail/table/inspector content
- Dashboard landing page per selected cluster.
- Resource group navigation:
  - Workloads
  - Network
  - Config
  - Storage
  - Access Control
  - Custom Resources
  - Events
  - Nodes
  - Namespaces
- Namespace selector with `All namespaces` support where applicable.
- Global search/quick open for resources.
- Window state restoration.

### Engineering Tasks

- Build navigation state model independent from view hierarchy.
- Implement route types for dashboard, resource list, resource detail, logs, YAML, events, and settings.
- Add command menu entries:
  - connect/disconnect
  - refresh
  - focus search
  - switch namespace
  - copy name
  - open YAML
  - open logs
- Add toolbar actions that adapt to selected route.

### UX Notes

- The first screen after selecting a cluster should be useful immediately: health summary, recent events, namespace status, top workloads.
- Resource navigation should support both grouped browsing and quick open.
- Avoid hiding important operational state behind hover-only controls.

### Exit Criteria

- User can move from cluster selection to dashboard to resource list to resource detail without dead ends.
- Keyboard shortcuts cover the main navigation path.

## Phase 4: Dashboard And Cluster Stats

Goal: provide a clear operational overview for a connected cluster.

### Deliverables

- Cluster dashboard with:
  - Kubernetes version
  - node count and readiness
  - namespace count
  - pod health summary
  - workload health summary
  - recent warning events
  - CPU/memory capacity and usage when metrics are available
  - storage summary
- Metrics Server detection.
- Graceful fallback when metrics APIs are unavailable.
- Refresh controls and last-updated indicators.

### Engineering Tasks

- Query and aggregate:
  - nodes
  - pods
  - namespaces
  - deployments
  - daemonsets
  - statefulsets
  - jobs
  - cronjobs
  - events
  - persistent volumes and claims
  - metrics APIs if present
- Implement health calculators for common resources.
- Add status taxonomy:
  - healthy
  - progressing
  - warning
  - failed
  - unknown
- Add dashboard view models that can update incrementally.

### UX Notes

- Dashboard cards should be compact and information-dense, not marketing-style panels.
- Warning events should be actionable links into the related resource.
- Metrics unavailable should be a subtle state, not a scary error.

### Tests

- Unit tests for health calculators.
- Snapshot or UI tests for dashboard empty/loading/error/healthy states.

### Exit Criteria

- Demo cluster dashboard shows meaningful workload, pod, event, and node information.
- Missing metrics do not break the dashboard.

## Phase 5: Resource Browsing

Goal: browse Kubernetes resources by group with sorting, filtering, namespace scoping, and status indicators.

### Deliverables

- Resource table views for:
  - Pods
  - Deployments
  - ReplicaSets
  - StatefulSets
  - DaemonSets
  - Jobs
  - CronJobs
  - Services
  - Ingresses
  - ConfigMaps
  - Secrets
  - PersistentVolumes
  - PersistentVolumeClaims
  - StorageClasses
  - ServiceAccounts
  - Roles
  - RoleBindings
  - ClusterRoles
  - ClusterRoleBindings
  - Nodes
  - Namespaces
  - Events
  - CRDs
  - Custom resources
- Generic resource table fallback for any discovered kind.
- Namespace filter, label filter, text search, and status filter.
- Column sorting and user-adjustable columns.
- Manual refresh and background update strategy.

### Engineering Tasks

- Define `ResourceIdentity`:
  - api group
  - version
  - kind
  - resource name
  - namespace
  - uid
- Create unstructured resource decoder with common metadata extraction.
- Add resource-specific summary mappers for key built-in kinds.
- Implement pagination for large clusters.
- Add efficient diffing for table updates.
- Add copy actions for name, namespace/name, UID, labels, and JSON path.

### UX Notes

- Tables should prioritize name, namespace, status, age, owner, readiness, restarts, and key resource-specific fields.
- Keep destructive actions out of primary browsing until later phases.
- Secrets should be visually distinguished and values should not be exposed by default.

### Tests

- Fixtures for each supported resource kind.
- Unit tests for metadata extraction, age formatting, status formatting, and filters.

### Exit Criteria

- User can browse all common resource groups in the demo cluster.
- Unknown discovered resource types are still visible through the generic table.

## Phase 6: Resource Detail, YAML, Events, And Relationships

Goal: inspect any resource deeply, including YAML and related objects.

### Deliverables

- Resource detail view with tabs/sections:
  - Overview
  - YAML
  - Events
  - Related
  - Conditions
  - Containers, where applicable
  - Metadata
- Read-only YAML viewer with syntax highlighting.
- Copy YAML and save YAML actions.
- Owner/reference graph:
  - Deployment to ReplicaSet to Pod
  - Job to Pod
  - Service to selected Pods
  - PVC to PV
  - Ingress to Service
- Event stream for selected resource.

### Engineering Tasks

- Add YAML renderer and syntax highlighting strategy.
- Build resource relationship resolver using owner references, selectors, labels, and known references.
- Normalize condition/status display across resource types.
- Add deep links/routes to related resources.
- Add local cache of recently viewed YAML snapshots for fast back navigation.

### UX Notes

- YAML must be readable and searchable.
- Related resources should feel like navigation, not a static graph diagram only.
- Error and empty states should explain whether data is missing because of permissions, unsupported kind, or no related objects.

### Tests

- Unit tests for relationship resolution.
- UI tests for opening YAML and navigating related resources.

### Exit Criteria

- User can open any resource, read YAML, inspect events, and navigate to related resources.

## Phase 7: Logs

Goal: view pod and container logs with basic operational controls.

### Deliverables

- Logs view for pods and workload-owned pods.
- Container selector.
- Follow mode.
- Previous container logs where available.
- Tail line count.
- Since time selector.
- Text search and filtering.
- Pause/resume stream.
- Copy selected lines and save logs.
- Timestamp toggle.

### Engineering Tasks

- Implement log endpoint requests:
  - `/api/v1/namespaces/{namespace}/pods/{pod}/log`
  - `follow`
  - `container`
  - `previous`
  - `tailLines`
  - `sinceSeconds`
  - `timestamps`
- Represent log streams as cancellable async sequences.
- Add buffering/backpressure so large logs do not freeze the UI.
- Add ANSI color handling or stripping.
- Add multi-pod log aggregation for deployments/jobs as a later subfeature.

### UX Notes

- Logs should behave like a native console: monospaced, fast, selectable, searchable, and stable while streaming.
- Follow mode should not fight the user when they scroll away from the bottom.
- Streaming errors should be shown inline with retry.

### Tests

- Unit tests for log request construction.
- Integration test against `vibekube-demo/log-counter`.
- Performance test with large synthetic log streams.

### Exit Criteria

- User can open live logs for the demo `log-counter` workload and follow them without UI stalls.

## Phase 8: Watches, Refresh, And Real-Time Updates

Goal: keep resource views current without requiring manual refresh.

### Deliverables

- Kubernetes watch support for resource lists and selected details.
- Reconnect/backoff behavior.
- Watch status indicators.
- Efficient list updates without full reload flicker.
- Manual refresh remains available.

### Engineering Tasks

- Implement `watch=true` streaming for list endpoints.
- Track `resourceVersion` and handle `410 Gone` relists.
- Build shared `ResourceWatchService`.
- Add throttling/debouncing for high-volume resources.
- Define memory limits and cleanup when navigating away or switching cluster.

### UX Notes

- Real-time updates should feel quiet. Avoid constantly moving selected rows.
- Show stale/offline state when watches fail.

### Tests

- Mock watch stream parser tests.
- Integration tests that create/delete demo resources and verify UI model updates.

### Exit Criteria

- Pod list updates as demo CronJobs create short-lived pods.
- Switching clusters/namespaces cancels old watches cleanly.

## Phase 9: Workload Debugging Basics

Goal: cover common debugging workflows beyond read-only inspection.

### Deliverables

- Describe-style synthesized view for pods and workloads.
- Pod restart count and termination reason drill-down.
- Container environment display.
- Mounted volumes display.
- Image and pull status.
- Port-forward basic support.
- Exec shell basic support.

### Engineering Tasks

- Add SPDY/WebSocket support strategy for exec and port-forward depending on Kubernetes API requirements and available Swift libraries.
- Build process/session models:
  - active exec sessions
  - active port forwards
  - cancellation
  - error states
- Add terminal-like view or native text session view for exec.
- Add local port allocation and conflict handling.

### UX Notes

- Exec and port-forward should be explicit, visible, and easy to stop.
- Show which cluster, namespace, pod, and container a session belongs to at all times.

### Tests

- Integration tests against demo pods where feasible.
- Manual QA checklist for cancelling sessions and app shutdown cleanup.

### Exit Criteria

- User can port-forward a service/pod in the demo cluster.
- User can start and stop a simple exec session.

## Phase 10: Safe Mutations

Goal: add common write actions with strong guardrails.

### Deliverables

- Scale deployments/statefulsets.
- Restart rollout.
- Delete resource.
- Edit YAML with server-side apply or replace strategy.
- Create resource from YAML.
- Apply local YAML file.
- Namespace creation/deletion.
- Secret/configmap creation basics.
- Diff preview before apply.
- RBAC-aware disabled states.

### Engineering Tasks

- Implement Kubernetes PATCH/PUT/POST/DELETE operations.
- Add dry-run support where available.
- Add diff model and UI.
- Add validation pipeline:
  - YAML parse
  - required metadata
  - namespace target
  - dry-run result
  - conflict detection
- Add audit trail in local app history.

### UX Notes

- Every mutation confirmation should name the cluster, namespace, resource kind, and resource name.
- Destructive actions should require deliberate confirmation.
- YAML editing should be powerful but clearly marked as advanced.

### Tests

- Mock API mutation tests.
- Integration tests in disposable kind cluster.
- UI tests for confirmation flows.

### Exit Criteria

- User can safely scale, restart, delete, and apply resources in the demo cluster.

## Phase 11: Preferences, Security, And Packaging

Goal: prepare Vibekube for real daily use outside the development environment.

### Deliverables

- Settings window:
  - kubeconfig paths
  - default namespace behavior
  - refresh/watch behavior
  - appearance/density
  - log limits
  - AI settings placeholder
- Keychain integration for any stored credentials or tokens that must be persisted.
- Sandboxing/notarization strategy.
- App signing and release packaging.
- Crash/error reporting decision.
- Privacy statement for local kubeconfig and AI usage.

### Engineering Tasks

- Audit secret handling.
- Add redaction utilities everywhere logs/errors might include credentials.
- Harden certificate and auth handling.
- Add app lifecycle cleanup for watches, logs, exec, and port-forwards.
- Create release build scripts.

### UX Notes

- Make privacy local-first and explicit.
- Explain when external AI services are used, before they are used.

### Exit Criteria

- App can be signed, packaged, and run on another Mac.
- No secrets are emitted into app logs during normal use.

## Phase 12: AI Foundations

Goal: prepare the architecture for AI features without entangling them with core Kubernetes operations.

### Deliverables

- AI provider abstraction.
- Local context builder for selected cluster/resource/log/event data.
- Redaction and permission filters before any AI request.
- AI chat/explain panel placeholder.
- Prompt templates for safe read-only explanations.
- User approval model for any suggested action.

### Initial AI Features

- Explain this resource.
- Summarize recent warning events.
- Explain why this pod is not ready.
- Summarize logs and highlight likely causes.
- Generate kubectl commands for the selected context.
- Draft YAML changes without applying them.
- Compare desired vs live YAML and explain differences.

### Guardrails

- AI cannot mutate the cluster directly in early versions.
- AI-generated commands and YAML must be shown to the user first.
- Redact secrets, tokens, env vars matching sensitive names, and secret data values.
- Keep cluster identity and user intent visible in every AI panel.

### Exit Criteria

- AI panel can explain selected demo resources using redacted local context.
- No AI path bypasses the normal mutation confirmation system.

## Phase 13: Advanced AI Operations

Goal: turn AI from explanation into guided operations while keeping users in control.

### Deliverables

- Guided troubleshooting flows:
  - CrashLoopBackOff
  - ImagePullBackOff
  - Pending pods
  - failed jobs
  - service has no endpoints
  - ingress not routing
- AI-generated investigation plans.
- Multi-resource incident summary.
- Suggested remediation with diff/command preview.
- Optional local runbook library.
- Optional team-shared prompt/runbook export.

### Exit Criteria

- AI can guide a user through common demo cluster failures and prepare safe remediations.

## Cross-Cutting Workstreams

### Performance

- Keep initial app launch independent from network calls.
- Use pagination and watches for large resources.
- Avoid decoding full YAML repeatedly on the main actor.
- Cap log buffers and resource caches.
- Profile large-table scrolling and log streaming.

### Accessibility

- Full keyboard navigation.
- VoiceOver labels for status indicators and icon-only buttons.
- High contrast-safe status colors.
- Reduced transparency support.
- Clear focus rings and selection states.

### Observability

- Structured `OSLog` categories:
  - app lifecycle
  - kubeconfig
  - connection
  - discovery
  - resources
  - watches
  - logs
  - mutations
  - AI
- Debug diagnostics export with secrets redacted.

### Testing Strategy

- Unit tests for parsing, resource mapping, health computation, filters, and route state.
- Mock API tests for client behavior.
- Integration tests against `dev/k8s` kind cluster.
- UI smoke tests for launch, cluster selection, resource browsing, YAML, and logs.
- Manual QA checklists for auth providers, cloud clusters, and packaging.

### Documentation

- `docs/ARCHITECTURE.md`: finalized architecture after Phase 0.
- `docs/DEVELOPMENT.md`: setup, build, test, demo cluster usage.
- `docs/KUBERNETES_CLIENT.md`: API client design and auth support matrix.
- `docs/DESIGN_SYSTEM.md`: visual language, components, states, and accessibility.
- `docs/AI_SAFETY.md`: context redaction, approval model, and provider behavior.

## Suggested Milestone Plan

### Milestone 1: Read-Only Alpha

Includes Phases 0-7.

User can open Vibekube, select a kubeconfig context, connect to the demo cluster, browse common resources, inspect YAML/events/relationships, and stream logs.

### Milestone 2: Real-Time And Debugging Beta

Includes Phases 8-9.

User gets live updates, better debugging surfaces, port-forwarding, and basic exec.

### Milestone 3: Safe Operations Beta

Includes Phases 10-11.

User can perform common mutations with strong confirmations, package the app, and use it outside the development machine.

### Milestone 4: AI Preview

Includes Phases 12-13.

User gets explain/summarize/troubleshoot features with redaction and approval guardrails.

## Immediate Next Step

Start with a Phase 0 implementation plan. The first concrete implementation slice should replace the scaffold UI with a native macOS shell, define the core app services/protocols, remove sample Core Data entities if they are not needed, and add a documented build/test/dev-cluster workflow.
