# Changelog

All notable user-facing changes are tracked here.

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
