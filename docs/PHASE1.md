# Phase 1: Kubeconfig Discovery And Cluster Selection

Status: Review checkpoint.

Goal: parse local kubeconfig files on startup, show contexts immediately, and let the user select the cluster/context to connect to.

## Current Progress

- [x] Phase plan exists.
- [x] Kubeconfig data models exist.
- [x] Kubeconfig parser exists.
- [x] `KUBECONFIG` path list support exists.
- [x] Context list UI uses parsed data.
- [x] Current context is preselected.
- [x] Unsupported auth states are visible and understandable.

## Checkpoint Notes

- The app now loads kubeconfig contexts on startup through `AppModel`.
- Default discovery reads `~/.kube/config`; `KUBECONFIG` colon-separated path lists are supported.
- Kubeconfig parsing is currently a focused native parser that covers the structures needed for the first client slice. Revisit a full YAML dependency if we hit advanced YAML features in real configs.
- App Sandbox is disabled for the app target at this checkpoint so Vibekube can read local kubeconfig files and, in the next phase, make Kubernetes API calls. Revisit distribution hardening in Phase 11.
- UI tests use `VIBEKUBE_USE_PREVIEW_CLUSTERS=1` so they stay deterministic and do not depend on the developer machine kubeconfig.

## Implementation Slices

### 1.1 Models And Fixtures

- [x] Define `Kubeconfig`.
- [x] Define `KubeconfigCluster`.
- [x] Define `KubeconfigContext`.
- [x] Define `KubeconfigUser`.
- [x] Define `KubeAuthMethod`.
- [x] Define `KubeconfigSource`.
- [ ] Add fixtures for:
  - [x] kind demo cluster
  - [x] token auth
  - [x] certificate auth
  - [x] exec auth
  - [x] malformed YAML
  - missing current context

Checkpoint result: no external YAML dependency added yet; native parser is enough for the first visible kubeconfig slice.

### 1.2 Parser

- [x] Add YAML parser dependency or native parsing adapter.
- [x] Load default `~/.kube/config`.
- [x] Load `KUBECONFIG` colon-separated path list.
- [x] Merge kubeconfigs with Kubernetes precedence rules.
- [x] Decode certificate-authority-data.
- [x] Decode client-certificate-data.
- [x] Decode client-key-data.
- [x] Preserve certificate/key file paths when data is path-based.
- [ ] Normalize server URLs.
- [x] Redact secrets in debug descriptions and errors.

### 1.3 Registry And File Watching

- [ ] Implement `ClusterRegistry`.
- [x] Publish discovered contexts to SwiftUI.
- [ ] Watch kubeconfig files for changes.
- [x] Add manual reload action.
- [ ] Persist recently selected context.
- [ ] Persist preferred namespace per context.

### 1.4 Cluster Selection UI

- [x] Replace cluster placeholder with parsed context list.
- [ ] Group contexts by source or cluster.
- [x] Show current context badge.
- [x] Show auth capability state.
- [x] Add empty state for missing kubeconfig.
- [x] Add malformed config error state.
- [ ] Add search/filter for contexts.

### 1.5 Tests

- [x] Parser unit tests.
- [x] Merge precedence tests.
- [x] Secret redaction tests.
- [ ] File watching test or documented manual QA.
- [x] UI test for context list using fixture injection.

## Acceptance Criteria

- [x] App startup shows kubeconfig contexts without connecting to the cluster.
- [x] Demo `kind-vibekube-dev` context appears when the demo cluster is configured.
- [x] Current context is visually marked.
- [x] Invalid configs produce useful errors.
- [x] Tokens and keys never appear in logs or UI error text.

## Validation Results

- [x] `kubectl config current-context` returns `kind-vibekube-dev` locally.
- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests`
- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeUITests`
- [ ] Manual app review by user.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl config current-context
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
