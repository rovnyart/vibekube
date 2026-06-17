# Phase 6: Resource Detail, YAML, Events, And Relationships

Status: Review checkpoint.

Goal: inspect any Kubernetes resource deeply, including readable YAML, conditions, events, metadata, and related resources.

## Current Progress

- [x] Phase plan exists.
- [x] Read-only resource detail inspector exists from list selection.
- [ ] Dedicated resource detail route exists.
- [x] Basic YAML viewer exists.
- [x] Event panel exists.
- [x] Initial relationship resolver exists.
- [x] Conditions/metadata views exist.

## Checkpoint Notes

- Resource table row selection now opens a detail inspector.
- Resource details now open in a bottom inspector instead of a right-side pane, which preserves table width on laptop screens.
- The bottom inspector supports multiple open resource tabs with close controls.
- The inspector fetches the full object through generic discovery-derived `get` endpoints.
- Open detail tabs refresh their manifest when the backing list row reports a newer Kubernetes `resourceVersion`.
- The manifest view is read-only, selectable, line-numbered, searchable, copyable, saveable, and lightly syntax-highlighted.
- Secret manifests redact top-level `data`, `stringData`, and `binaryData`.
- Resource detail now has Overview, Events, Logs, Env, YAML, Metadata, and Conditions tabs.
- The overview tab extracts status, identity, owner references, conditions, and pod-like container summaries.
- Owner references for known Kubernetes kinds are clickable and navigate to the matching resource list.
- Deployments expose a Related ReplicaSets action that opens ReplicaSets with a clearable owner-reference filter.
- Workloads and Services with concrete label selectors expose a Related Pods action that opens Pods with a clearable selector filter.
- CronJobs expose a Related Jobs action that opens Jobs with a clearable owner-reference filter.
- Ingresses expose Related Services actions for `spec.defaultBackend` and rule path backends.
- PersistentVolumeClaims expose their bound PersistentVolume when `spec.volumeName` is present.
- Pods expose related ConfigMaps and Secrets from `env`, `envFrom`, and volume references.
- Pod details now include an Environment tab for `env`, `envFrom`, ConfigMap refs, field refs, resource refs, and Secret key refs.
- Pod `envFrom` ConfigMaps and Secrets are resolved into the env vars Kubernetes actually injects when the user has `get` access to the referenced object.
- Literal and ConfigMap-backed values render directly; only Secret-backed values are masked and revealable.
- The Environment tab groups values by source and collapses large groups so big `envFrom` ConfigMaps stay navigable.
- Invalid `envFrom` keys are skipped using Kubernetes-style env var name rules instead of being shown as fake variables.
- Secret-backed env values are masked by default and fetched/decoded on demand through an eye reveal button.
- Resource details now include an Events tab that reads Kubernetes Events for the selected object using `events.k8s.io/v1` or core `v1/Event`.
- The richer Phase 6 detail experience still needs custom metadata sections and a dedicated Related tab.

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
- [x] Resolve ConfigMap values used by explicit `configMapKeyRef` env vars.
- [x] Resolve ConfigMap/Secret keys used by `envFrom`, preserving Secret masking.
- [x] Treat loaded details as stale when the selected row has a newer `resourceVersion`.

### 6.2 YAML Viewer

- [x] Convert resource object to readable YAML.
- [x] Add basic syntax highlighting.
- [x] Add find-in-YAML.
- [x] Add copy YAML.
- [x] Add save YAML.
- [x] Keep YAML read-only in this phase.
- [x] Redact secret data by default or require explicit reveal.

Checkpoint: stop for feedback on YAML readability and secret display policy.

### 6.3 Events And Conditions

- [x] Query events related to selected resource.
- [x] Show event type, reason, message, count, source, and age.
- [x] Show conditions with status, reason, message, and last transition time.
- [x] Link events back to involved objects.

### 6.4 Relationships

- [x] Deployment to ReplicaSet to Pod.
- [x] Deployment to selected Pods.
- [x] StatefulSet to Pod.
- [x] DaemonSet to Pod.
- [x] Job to Pod.
- [x] CronJob to Job.
- [x] Service to selected Pods.
- [x] Ingress to Service.
- [x] PVC to PV.
- [x] ConfigMap/Secret references from Pods where feasible.

### 6.5 UI

- [x] Bottom detail inspector.
- [x] Multiple resource detail tabs.
- [x] Overview tab.
- [x] YAML tab.
- [x] Events tab.
- [ ] Related tab.
- [x] Conditions tab.
- [x] Metadata tab.
- [x] Environment tab for pod-like resources.
- [x] Group and filter large environment sets.
- [x] Dedicated containers tab for pod-like resources.
- [x] ConfigMap values render directly for environment references.
- [x] Manifest freshness indicator in the detail header.

### 6.6 Secret Reveal

- [x] Keep Secret YAML redacted by default.
- [x] Show Secret references from pod env vars.
- [x] Reveal individual Secret key values on demand.
- [x] Surface RBAC/fetch failures per env row.
- [x] Add a global setting for secret reveal confirmation policy.

### 6.7 Tests

- [x] YAML rendering tests.
- [x] Secret redaction tests.
- [x] YAML search indexing tests.
- [x] Resource summary extraction tests.
- [x] Pod container detail extraction tests.
- [x] Pod environment extraction tests.
- [x] Secret env reveal tests.
- [x] `envFrom` expansion tests.
- [x] Preview UI smoke test opens resource detail overview.
- [x] Relationship resolver tests.
- [x] Resource event decoding tests.
- [x] Resource event model load tests.
- [x] Version-aware detail refresh test for watched Pod rows.
- [ ] UI navigation tests for related resources.

## Acceptance Criteria

- [x] User can open any listed get-capable resource from a table row.
- [x] YAML is readable, searchable, copyable, saveable, and safe for secrets.
- [x] Pod env vars and Secret refs are visible without exposing secret values by default.
- [x] Events and conditions explain resource state.
- [ ] Related resources are navigable.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo get deploy echo-web -o yaml
kubectl -n vibekube-demo describe deploy echo-web
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
