# Changelog

All notable user-facing changes are tracked here.

## 0.6.0 - 2026-06-21

Changes since 0.5.0:

### Added

- Safe Kubernetes mutation workflows for common day-to-day operations, including scaling workloads, restarting rollouts, deleting resources, and applying YAML with explicit user confirmation.
- Server-side dry-run preview and diff flow for YAML edits, so existing resources can be edited, searched, previewed, confirmed, applied, and refreshed without guessing what Kubernetes will accept.
- A highlighted YAML editing experience with line numbers, search, indentation support, expanded diff review, validation errors, and structured apply confirmation.
- Global Apply YAML tooling with file loading, dry-run preview, and quick generators for basic Namespaces, ConfigMaps, and Secrets.
- Local mutation action history with status, target resource, timestamp, failure details, and Secret-value redaction.
- AI provider settings for OpenAI-compatible and Anthropic-compatible APIs, including custom base URLs, custom headers, Keychain-stored secrets, model discovery, and availability testing.
- Resource-scoped AI assistant for explaining selected Kubernetes resources from visible, redacted context.
- Cluster-aware read-only AI gathering for resource questions, including Events, conditions, selected logs, selector-matched related Pods, related Pod health, and bounded log/event inspection when a prompt asks about runtime behavior.
- Streaming AI chat with Markdown rendering, syntax-highlighted code blocks, copy controls, stop generation, clear chat, and Jump to bottom behavior that respects manual scrolling.
- Top-level AI status page showing provider readiness, selected model, and Keychain status.

### Changed

- Resource detail actions now live in a dedicated Actions flow from the detail header instead of being mixed into read-only inspector tabs.
- AI assistant opens as a resizable standalone window with a structured context browser and a transcript showing what Vibekube read before contacting the provider.
- AI suggestions are read-only by design: generated commands and YAML are for copy/preview, and no AI response can mutate a cluster automatically.
- Privacy documentation and settings behavior now distinguish local-only browsing from optional user-configured AI provider requests.

## 0.5.0 - 2026-06-21

Changes since 0.4.0:

### Added

- Container-aware Pod exec actions for opening an external-terminal `kubectl exec` shell from Pod workflows.
- Shell picker for Pod exec, with common shell choices exposed before launching the external terminal.
- Pod-local exec launch history in Pod detail, including command, container, timestamp, and failed launch attempts.
- Clearer debug-action failure explanations for exec and port-forward failures, including RBAC and streaming-protocol hints.
- Echo demo workload now serves static content, making browser-based port-forward validation straightforward.
- Connection progress now distinguishes kubeconfig exec-auth signing-in work from generic connecting state.
- API-client test coverage for connection success, auth failure, timeout/cancellation, malformed responses, and exec-auth progress.

### Changed

- Pod exec entry points were consolidated and clarified: pod-level actions use a default shell, while per-container actions stay available where container choice matters.
- Phase 9 workload debugging is now complete for the read-only release, covering event-aware debug summaries, port-forwarding, external exec, and local launch history.
- Dashboard expansion is intentionally canceled for now; the release keeps the small, fast dashboard shape instead of reintroducing expensive cluster-wide panels.
- Release-hardening docs now explicitly cover sandbox strategy, temporary client-certificate keychain use, credential-storage boundaries, crash reporting, telemetry, diagnostics, and AI-placeholder decisions.
- Clean-machine validation is recorded from daily use on a non-development work Mac since 0.3.0.

### Fixed

- Active port-forward sessions are stopped on app quit.
- Port-forward start now detects local port conflicts before launching `kubectl`.
- Stopped port-forward sessions are kept visible long enough to understand their final state.
- Port-forward and exec helper command lookup now uses the common Homebrew/system path environment.
- Secret handling now redacts more surfaces, including diagnostics messages, Kubernetes status errors, exec-plugin stderr, Secret YAML payload fields, and Secret reveal logging.
- Dashboard-related roadmap/docs no longer imply we should build the previously laggy rich dashboard path for this release.

## 0.4.0 - 2026-06-17

Changes since 0.3.0:

### Added

- Workload debug summaries with warning Event context, scheduling signals, QoS, container state, restart/termination details, probes, volume mounts, and resource requests/limits.
- `kubectl`-backed port-forward sessions for Pods, Services, and Deployments, including visible session state and stop controls.
- External-terminal Pod exec from the Pods table context menu and from per-container detail actions.
- External terminal preference for exec shells, with hardcoded choices for Terminal, iTerm2, Ghostty, and Warp.
- Container detail inspector for Pod manifests.
- Related-resource navigation for owner references, workload and Service selectors, Ingress backends, PVC/PV bindings, CronJob Jobs, and Pod ConfigMap/Secret references.
- Environment inspector support for `env`, `envFrom`, ConfigMap refs, Secret refs, field refs, resource refs, and volume-sourced environment context.
- Save/export action for rendered resource YAML.
- Demo cluster fixtures for debugging unhealthy Pods, failed Jobs, image pull failures, restarts, previous logs, port-forwarding, exec, Ingresses, and storage relationships.

### Changed

- Pods table now emphasizes operational signals with a wider Name column, readiness and restart columns, and clearer unhealthy status styling.
- Large `envFrom` ConfigMap and Secret groups are collapsed so very large environment surfaces remain usable.
- Resource relationship jumps now use scoped filters instead of leaking through the global search box.
- Standalone hidden Logs navigation was removed; logs now live in the relevant resource detail flow.
- Phase docs were realigned with the current product state after the debugging and relationship work.

### Fixed

- Stopping a port-forward no longer reports a normal user stop as a failed session.
- Completed init containers no longer incorrectly make otherwise healthy Pods look unhealthy.
- Workload debug summaries show clearer context when related warning Events are absent.
- `kubectl` launch paths include common Homebrew and system locations for port-forward and exec helpers.
- Reverted an early workload Pod rollup that was noisy and unreliable in the detail overview.

## 0.3.0 - 2026-06-16

Changes since 0.2.0:

### Added

- Settings for the default namespace behavior when connecting to a cluster.
- Setting to enable or disable live Kubernetes resource watches.
- Kubeconfig path override setting for custom files or colon-separated KUBECONFIG lists.
- Table density setting for compact, comfortable, and spacious resource/log layouts.
- Appearance setting for System, Light, and Dark themes.

### Changed

- Table density now lives in the Appearance settings section with theme controls.
- Settings mutations are deferred out of SwiftUI view updates to avoid undefined update behavior warnings.

## 0.2.0 - 2026-06-16

Changes since 0.1.7:

### Added

- Real-time watches for active resource lists beyond the first Pods implementation.
- Selected-resource detail watches, including version-aware refresh for open inspectors.
- Durable watch reconnect handling for transient transport failures and long idle/background periods.
- Resource watch status UI for live, reconnecting, stale, and failed states.
- Stable table ordering while inspecting resources, plus subtle updated-row feedback for watch changes.
- Burst coalescing for high-volume watch updates.
- Safe JSONL log formatting for readable structured log lines.
- Log `since` selector, smart live-follow behavior, and a more reliable "Jump to latest" flow.
- Live log buffer hardening with ANSI escape stripping and an explicit line cap.
- Settings for live log buffer size and Secret reveal confirmation.
- Local diagnostics logging/export with redaction, retention controls, and optional cluster-name inclusion.
- Large-cluster pagination and cancellable resource-list loading progress.
- Release readiness docs covering privacy, clean-machine checks, signing, notarization, and packaging.

### Changed

- Phase 8 watches moved to review checkpoint after demo and real-cluster validation.
- Resource detail header layout was polished for smaller screens.
- Pod watch UI now treats quiet watches as live instead of confusingly stuck.
- Environment rendering now expands `envFrom` ConfigMap and Secret keys while only masking Secret-backed values.
- Inspector tabs, sidebar branding, current-context badge, and namespace picker received UI polish.
- App deployment target is macOS 26.0.

### Fixed

- Resource watches recover after app idle/background timeouts instead of remaining failed.
- Resource list rows no longer jump around while the user is inspecting watched resources.
- Expired watch resource versions trigger relist and resume.
- Burst watch updates no longer cause excessive detail refresh churn.
- Live logs no longer replay from the beginning when streaming starts.
- Log text buffering strips ANSI/control sequences before rendering.
- Client certificate chain handling avoids empty certificate arrays and local crashes.
- Kubernetes TLS handling works for CA-pinned and exec-auth corporate clusters.
- Resource-list loading and dashboard navigation remain responsive on larger or slower clusters.
