# Phase 2: Kubernetes API Connectivity And Discovery

Status: Not started.

Goal: connect to the selected cluster, authenticate safely, and discover available Kubernetes APIs.

## Current Progress

- [x] Phase plan exists.
- [ ] API client protocol exists.
- [ ] TLS/auth from kubeconfig works.
- [ ] `/version` request works.
- [ ] API discovery works.
- [ ] Namespaces load.
- [ ] Connection errors are mapped to user-facing states.

## Implementation Slices

### 2.1 Client Foundation

- [ ] Define `KubernetesAPIClient`.
- [ ] Define `KubernetesRequest`.
- [ ] Define `KubernetesResponseError`.
- [ ] Define Kubernetes `Status` decoding.
- [ ] Add URL builder for core and grouped APIs.
- [ ] Add cancellation support when switching contexts.

### 2.2 TLS And Auth

- [ ] Support certificate-authority data.
- [ ] Support certificate-authority file paths.
- [ ] Support bearer token auth.
- [ ] Support client certificate/key auth if feasible in first pass.
- [ ] Represent unsupported auth-provider cases cleanly.
- [ ] Represent exec auth as planned or stubbed with clear UI.
- [ ] Ensure secrets are redacted in logs/errors.

Checkpoint: stop before adding any complex auth helper dependency.

### 2.3 Discovery APIs

- [ ] Implement `/version`.
- [ ] Implement `/api`.
- [ ] Implement `/apis`.
- [ ] Implement resource discovery for each group/version.
- [ ] Persist discovered resource metadata in memory.
- [ ] Detect namespaced vs cluster-scoped resources.
- [ ] Detect verbs available from discovery data.

### 2.4 Namespace Loading

- [ ] Load namespaces.
- [ ] Display namespace selector in toolbar.
- [ ] Support `All namespaces`.
- [ ] Persist selected namespace per context.
- [ ] Handle permission-denied namespace list.

### 2.5 UI Connection Flow

- [ ] Connect on selected context.
- [ ] Show connecting state.
- [ ] Show connected state with cluster version.
- [ ] Show unauthorized state.
- [ ] Show unavailable state.
- [ ] Show certificate error state.
- [ ] Add retry action.
- [ ] Disconnect/cancel on context switch.

### 2.6 Tests

- [ ] Request URL unit tests.
- [ ] Kubernetes `Status` decoding tests.
- [ ] Mock server tests for `/version` and discovery.
- [ ] Integration test against kind where practical.

## Acceptance Criteria

- [ ] Selecting the demo context connects successfully.
- [ ] Toolbar shows connected status and Kubernetes version.
- [ ] API groups/resources are discovered.
- [ ] Namespaces are available in the selector.
- [ ] Bad auth, offline server, and certificate failures are understandable.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl version
kubectl api-resources
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
