# Vibekube Development

## Requirements

- Xcode 26.5 or newer.
- macOS 26.5 SDK.
- Docker and kind for the local Kubernetes demo cluster.
- kubectl for manual cluster validation.

## Build

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
```

## Test

Unit tests:

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests
```

Full test suite:

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```

The current suite is focused on non-UI tests. Verify visible SwiftUI flows manually from Xcode until a dedicated UI automation target is restored.

## Demo Cluster

Start:

```sh
dev/k8s/scripts/start.sh
```

Status:

```sh
dev/k8s/scripts/status.sh
```

Stop:

```sh
dev/k8s/scripts/stop.sh
```

Useful checks:

```sh
kubectl config current-context
kubectl -n vibekube-demo get pods -w
kubectl -n vibekube-demo logs -f deploy/log-counter
kubectl -n vibekube-demo describe svc echo-web
```

## Current Architecture

- `vibekube/App`: app entry point, commands, and root app model.
- `vibekube/Domain`: pure app and Kubernetes-facing domain models.
- `vibekube/Features`: SwiftUI feature views.
- `vibekube/KubernetesClient`: future native Kubernetes API client.
- `vibekube/Persistence`: future preferences and local cache storage.
- `vibekube/SharedUI`: reusable visual components.
- `vibekube/Infrastructure`: preview and adapter implementations.

Phase 0 intentionally removed the generated Core Data sample. Persistence will return as explicit app preferences and caches instead of scaffold demo entities.
