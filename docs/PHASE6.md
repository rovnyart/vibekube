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
- [x] Conditions/metadata views exist.

## Checkpoint Notes

- Resource table row selection now opens a detail inspector.
- Resource details now open in a bottom inspector instead of a right-side pane, which preserves table width on laptop screens.
- The bottom inspector supports multiple open resource tabs with close controls.
- The inspector fetches the full object through generic discovery-derived `get` endpoints.
- The manifest view is read-only, selectable, line-numbered, searchable, copyable, and lightly syntax-highlighted.
- Secret manifests redact top-level `data`, `stringData`, and `binaryData`.
- Resource detail now has Overview, YAML, Metadata, and Conditions tabs.
- The overview tab extracts status, identity, owner references, conditions, and pod-like container summaries.
- Pod details now include an Environment tab for `env`, `envFrom`, ConfigMap refs, field refs, resource refs, and Secret key refs.
- Secret-backed env values are masked by default and fetched/decoded on demand through an eye reveal button.
- The richer Phase 6 detail experience still needs save/export YAML tools, events, relationships, ConfigMap value reveal, and custom metadata sections.

## Implementation Slices

### 6.1 Detail Data Model

- [x] Define `ResourceDetailSnapshot`.
- [x] Load full resource object by identity.
- [x] Extract metadata.
- [x] Extract labels and annotations.
- [x] Extract owner references.
- [x] Extract conditions.
- [x] Extract resource-specific status.
- [x] Extract pod container environment variables.
- [x] Extract pod `envFrom` ConfigMap/Secret references.

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

- [x] Bottom detail inspector.
- [x] Multiple resource detail tabs.
- [x] Overview tab.
- [x] YAML tab.
- [ ] Events tab.
- [ ] Related tab.
- [x] Conditions tab.
- [x] Metadata tab.
- [x] Environment tab for pod-like resources.
- [ ] Dedicated containers tab for pod-like resources.
- [ ] ConfigMap value reveal for environment references.

### 6.6 Secret Reveal

- [x] Keep Secret YAML redacted by default.
- [x] Show Secret references from pod env vars.
- [x] Reveal individual Secret key values on demand.
- [x] Surface RBAC/fetch failures per env row.
- [ ] Add a global setting for secret reveal confirmation policy.

### 6.7 Tests

- [x] YAML rendering tests.
- [x] Secret redaction tests.
- [x] YAML search indexing tests.
- [x] Resource summary extraction tests.
- [x] Pod environment extraction tests.
- [x] Secret env reveal tests.
- [x] Preview UI smoke test opens resource detail overview.
- [ ] Relationship resolver tests.
- [ ] UI navigation tests for events and related resources.

## Acceptance Criteria

- [x] User can open any listed get-capable resource from a table row.
- [x] YAML is readable, searchable, copyable, and safe for secrets.
- [x] Pod env vars and Secret refs are visible without exposing secret values by default.
- [ ] Events and conditions explain resource state.
- [ ] Related resources are navigable.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo get deploy echo-web -o yaml
kubectl -n vibekube-demo describe deploy echo-web
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
