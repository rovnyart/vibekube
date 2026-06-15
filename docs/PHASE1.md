# Phase 1: Kubeconfig Discovery And Cluster Selection

Status: Not started.

Goal: parse local kubeconfig files on startup, show contexts immediately, and let the user select the cluster/context to connect to.

## Current Progress

- [x] Phase plan exists.
- [ ] Kubeconfig data models exist.
- [ ] Kubeconfig parser exists.
- [ ] `KUBECONFIG` path list support exists.
- [ ] Context list UI uses parsed data.
- [ ] Current context is preselected.
- [ ] Unsupported auth states are visible and understandable.

## Implementation Slices

### 1.1 Models And Fixtures

- [ ] Define `Kubeconfig`.
- [ ] Define `KubeconfigCluster`.
- [ ] Define `KubeconfigContext`.
- [ ] Define `KubeconfigUser`.
- [ ] Define `KubeAuthMethod`.
- [ ] Define `KubeconfigSource`.
- [ ] Add fixtures for:
  - kind demo cluster
  - token auth
  - certificate auth
  - exec auth
  - malformed YAML
  - missing current context

Checkpoint: stop if a YAML dependency decision is needed.

### 1.2 Parser

- [ ] Add YAML parser dependency or native parsing adapter.
- [ ] Load default `~/.kube/config`.
- [ ] Load `KUBECONFIG` colon-separated path list.
- [ ] Merge kubeconfigs with Kubernetes precedence rules.
- [ ] Decode certificate-authority-data.
- [ ] Decode client-certificate-data.
- [ ] Decode client-key-data.
- [ ] Preserve certificate/key file paths when data is path-based.
- [ ] Normalize server URLs.
- [ ] Redact secrets in debug descriptions and errors.

### 1.3 Registry And File Watching

- [ ] Implement `ClusterRegistry`.
- [ ] Publish discovered contexts to SwiftUI.
- [ ] Watch kubeconfig files for changes.
- [ ] Add manual reload action.
- [ ] Persist recently selected context.
- [ ] Persist preferred namespace per context.

### 1.4 Cluster Selection UI

- [ ] Replace cluster placeholder with parsed context list.
- [ ] Group contexts by source or cluster.
- [ ] Show current context badge.
- [ ] Show auth capability state.
- [ ] Add empty state for missing kubeconfig.
- [ ] Add malformed config error state.
- [ ] Add search/filter for contexts.

### 1.5 Tests

- [ ] Parser unit tests.
- [ ] Merge precedence tests.
- [ ] Secret redaction tests.
- [ ] File watching test or documented manual QA.
- [ ] UI test for context list using fixture injection.

## Acceptance Criteria

- [ ] App startup shows kubeconfig contexts without connecting to the cluster.
- [ ] Demo `kind-vibekube-dev` context appears when the demo cluster is configured.
- [ ] Current context is visually marked.
- [ ] Invalid configs produce useful errors.
- [ ] Tokens and keys never appear in logs or UI error text.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl config current-context
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
