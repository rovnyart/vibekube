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
- `exec` credential plugins are parsed as supported connection paths, including Teleport `tsh` detection for corporate kubeconfigs.
- App Sandbox is disabled for the app target so Vibekube can read local kubeconfig files, referenced certificate/key paths, and support the Kubernetes client workflows documented in Phase 11. The Phase 11 release decision keeps sandboxing off for current direct distribution.
- Preview and model tests can use deterministic preview clusters so they do not depend on the developer machine kubeconfig.

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
- [x] Parse exec credential plugin metadata.
- [x] Detect Teleport `tsh` exec auth for display.
- [ ] Normalize server URLs.
- [x] Redact secrets in debug descriptions and errors.

### 1.3 Registry And File Watching

- [ ] Implement `ClusterRegistry`.
- [x] Publish discovered contexts to SwiftUI.
- [ ] Watch kubeconfig files for changes.
- [x] Add manual reload action.
- [x] Persist recently selected context.
- [x] Persist preferred namespace per context.

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
- [x] Model tests cover deterministic context restoration and kubeconfig override loading.

## Acceptance Criteria

- [x] App startup shows kubeconfig contexts without connecting to the cluster.
- [x] Demo `kind-vibekube-dev` context appears when the demo cluster is configured.
- [x] Current context is visually marked.
- [x] Invalid configs produce useful errors.
- [x] Tokens and keys never appear in logs or UI error text.

## Validation Results

- [x] `kubectl config current-context` returns `kind-vibekube-dev` locally.
- [x] `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests`
- [x] Model tests cover context restoration and namespace preference behavior.
- [ ] Manual app review by user.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl config current-context
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
