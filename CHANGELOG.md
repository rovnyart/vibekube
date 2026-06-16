# Changelog

All notable user-facing changes are tracked here.

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

