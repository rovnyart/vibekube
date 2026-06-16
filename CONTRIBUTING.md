# Contributing To Vibekube

Thanks for taking a look at Vibekube. The project is still young, so the most helpful contributions are focused fixes, careful UX polish, and small feature slices that preserve the app's speed and safety.

## Principles

- Keep the app fast. Resource-heavy screens should stay responsive on real clusters.
- Prefer native macOS controls and patterns.
- Keep Kubernetes operations read-only unless a planned safe mutation workflow explicitly allows writes.
- Treat secrets as sensitive by default. Do not log kubeconfig contents, tokens, client keys, Secret payloads, or revealed Secret values.
- Use existing app architecture and local patterns before adding new abstractions or dependencies.

## Setup

Requirements:

- Xcode 26.5 or newer.
- macOS 26.5 SDK.
- Docker, kind, and kubectl for the demo cluster.

Build:

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
```

Run the main unit test suite:

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests
```

Start the local demo cluster:

```sh
dev/k8s/scripts/start.sh
```

Stop it when finished:

```sh
dev/k8s/scripts/stop.sh
```

## Pull Requests

Before opening a PR:

- Keep the scope narrow and explain the user-visible change.
- Add or update focused tests for model, parsing, Kubernetes client, diagnostics, or formatting behavior.
- Update docs when behavior, release process, privacy, diagnostics, or roadmap status changes.
- Run the focused non-UI test suite above.
- Manually test visible UI changes in the app.

Full UI automation is not required for ordinary contributions. Prefer deterministic unit tests plus manual UI verification unless the change specifically needs UI automation.

## Security And Privacy

Do not include real kubeconfigs, corporate cluster names, tokens, certificates, private keys, Secret values, or production manifests in issues or PRs.

Diagnostics and logs should remain redacted. If a bug requires sensitive context, reduce it to a synthetic fixture or describe the shape of the data without exposing the value.

## Roadmap

The current roadmap and phase tracking live in [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/PROGRESS.md](docs/PROGRESS.md).

