# Vibekube

Vibekube is a native macOS Kubernetes client focused on fast read-only cluster browsing, rich pod logs, and clean day-to-day debugging workflows.

It is built as a local-first desktop app: Vibekube reads your kubeconfig, connects directly to Kubernetes API servers, and does not send cluster data to a Vibekube backend.

## Download

Download the latest notarized macOS build from [vibekube.tech](https://vibekube.tech).

## Highlights

- Native macOS interface with sidebar contexts, resource navigation, toolbar search, and namespace selection.
- Kubeconfig discovery with support for standard Kubernetes auth, client certificates, bearer tokens, and exec credential plugins such as Teleport `tsh`.
- Fast resource browsing for common Kubernetes resources and CRDs.
- Resource inspector with Overview, Events, Logs, Env, searchable/copyable/saveable YAML, Metadata, and Conditions tabs.
- Workload debug summaries that call out unhealthy signals, warning Events, scheduling context, container state, probes, mounts, and resource requests/limits.
- Practical debug actions, including `kubectl`-backed port-forwarding and external-terminal Pod exec from Pod context menus or per-container detail.
- Related-resource navigation for common Kubernetes paths such as owner references, workload/service selectors, Ingress backends, PVC/PV bindings, and Pod ConfigMap/Secret references.
- Rich pod logs: live streaming, timestamps, search, grep-style filtering, JSONL formatting, previous container logs, fullscreen mode, copy, save, and download-all.
- Large Env views stay navigable by grouping and collapsing `envFrom` ConfigMap and Secret values.
- Real-time watches for active resource lists and selected resource details, with reconnect handling after idle/background timeouts.
- Safe Secret handling: Secret manifest payloads are redacted by default, Secret-backed env values are masked until explicitly revealed, and diagnostics redact sensitive data.
- Optional local diagnostics logging to `~/Library/Logs/Vibekube`, disabled by default.

## Requirements

- macOS 26.0 or later.
- A working Kubernetes kubeconfig, usually `~/.kube/config`.
- Any external kubeconfig exec plugins used by your contexts, for example `tsh`, `aws`, `gcloud`, or `kubelogin`.

## Development

Requirements:

- Xcode 26.5 or newer.
- Docker, kind, and kubectl for the local demo cluster.

Build:

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
```

Run the focused non-UI test suite:

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests
```

Start the demo cluster:

```sh
dev/k8s/scripts/start.sh
```

More development notes live in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md), and the implementation roadmap lives in [docs/ROADMAP.md](docs/ROADMAP.md).

## Release Builds

Release packaging is handled by:

```sh
NOTARY_PROFILE=vibekube-notary scripts/release current
```

See [docs/RELEASE.md](docs/RELEASE.md) for signing, notarization, and DMG verification details.

## Privacy

Vibekube is local-first and currently has no telemetry, crash reporting, automatic update checks, or AI network requests. See [docs/PRIVACY.md](docs/PRIVACY.md).
