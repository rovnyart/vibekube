# Phase 6: Resource Detail, YAML, Events, And Relationships

Status: Started.

Goal: inspect any Kubernetes resource deeply, including readable YAML, conditions, events, metadata, and related resources.

## Current Progress

- [x] Phase plan exists.
- [x] Read-only resource detail inspector exists from list selection.
- [ ] Dedicated resource detail route exists.
- [x] Basic YAML viewer exists.
- [ ] Event panel exists.
- [ ] Relationship resolver exists.
- [ ] Conditions/metadata views exist.

## Checkpoint Notes

- Resource table row selection now opens a side inspector.
- The inspector fetches the full object through generic discovery-derived `get` endpoints.
- The manifest view is read-only, selectable, line-numbered, searchable, copyable, and lightly syntax-highlighted.
- Secret manifests redact top-level `data`, `stringData`, and `binaryData`.
- The richer Phase 6 detail experience still needs dedicated tabs, save/export YAML tools, conditions, events, relationships, and custom metadata sections.

## Implementation Slices

### 6.1 Detail Data Model

- [x] Define `ResourceDetailSnapshot`.
- [x] Load full resource object by identity.
- [ ] Extract metadata.
- [ ] Extract labels and annotations.
- [ ] Extract owner references.
- [ ] Extract conditions.
- [ ] Extract resource-specific status.

### 6.2 YAML Viewer

- [x] Convert resource object to readable YAML.
- [x] Add basic syntax highlighting.
- [x] Add find-in-YAML.
- [x] Add copy YAML.
- [ ] Add save YAML.
- [x] Keep YAML read-only in this phase.
- [x] Redact secret data by default or require explicit reveal.

Checkpoint: stop for feedback on YAML readability and secret display policy.

### 6.3 Events And Conditions

- [ ] Query events related to selected resource.
- [ ] Show event type, reason, message, count, source, and age.
- [ ] Show conditions with status, reason, message, and last transition time.
- [ ] Link events back to involved objects.

### 6.4 Relationships

- [ ] Deployment to ReplicaSet to Pod.
- [ ] StatefulSet to Pod.
- [ ] DaemonSet to Pod.
- [ ] Job to Pod.
- [ ] CronJob to Job.
- [ ] Service to selected Pods.
- [ ] Ingress to Service.
- [ ] PVC to PV.
- [ ] ConfigMap/Secret references from Pods where feasible.

### 6.5 UI

- [ ] Overview tab.
- [ ] YAML tab.
- [ ] Events tab.
- [ ] Related tab.
- [ ] Conditions tab.
- [ ] Metadata tab.
- [ ] Containers tab for pod-like resources.

### 6.6 Tests

- [x] YAML rendering tests.
- [x] Secret redaction tests.
- [x] YAML search indexing tests.
- [ ] Relationship resolver tests.
- [ ] UI navigation tests from resource list to detail and related resource.

## Acceptance Criteria

- [x] User can open any listed get-capable resource from a table row.
- [x] YAML is readable, searchable, copyable, and safe for secrets.
- [ ] Events and conditions explain resource state.
- [ ] Related resources are navigable.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo get deploy echo-web -o yaml
kubectl -n vibekube-demo describe deploy echo-web
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
