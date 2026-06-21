# Phase 10: Safe Mutations

Status: Started.

Goal: add common write operations with strong previews, confirmations, RBAC awareness, and rollback-friendly behavior.

## Current Progress

- [x] Phase plan exists.
- [x] Mutation API exists.
- [ ] Dry-run/diff support exists.
- [ ] Confirmations exist.
- [ ] Scale/restart/delete/apply flows exist.
- [ ] Local action history exists.
- [x] Kubernetes `Status` mutation errors surface HTTP code, reason, field causes, and retry hints.
- [x] Dry-run is supported at the request layer; user-facing diff preview is still pending.
- [x] Non-UI mutation preview foundation parses YAML, validates target identity, runs server-side dry-run, fetches live state, and produces a diff.

## Implementation Slices

### 10.1 Mutation Foundation

- [x] Define `MutationRequest`.
- [x] Define `MutationPreview`.
- [x] Define `MutationResult`.
- [x] Implement POST.
- [x] Implement PUT.
- [x] Implement PATCH.
- [x] Implement DELETE.
- [x] Decode Kubernetes `Status`.
- [x] Support dry-run where available.

Checkpoint: mutation client/service foundation is implemented and tested without exposing mutation UI against a real cluster.

### 10.2 Diff And Validation

- [x] Parse YAML safely.
- [x] Validate apiVersion/kind/metadata.
- [x] Validate namespace targeting.
- [x] Fetch live object for diff.
- [x] Render diff preview.
- [x] Detect conflicts/resourceVersion issues.
- [ ] Show RBAC/permission failures clearly.

Checkpoint: non-UI preview/diff foundation exists for existing-resource YAML edits. Visible preview UI, confirmation flow, and apply actions are still pending.

### 10.3 Common Actions

- [ ] Scale Deployment.
- [ ] Scale StatefulSet.
- [ ] Restart rollout.
- [ ] Delete resource.
- [ ] Edit YAML.
- [ ] Create resource from YAML.
- [ ] Apply YAML file.
- [ ] Create namespace.
- [ ] Delete namespace.
- [ ] Create ConfigMap basics.
- [ ] Create Secret basics with hidden values.

### 10.4 Safety UX

- [ ] Confirm cluster/context.
- [ ] Confirm namespace.
- [ ] Confirm kind/name.
- [ ] Require typed confirmation for destructive actions.
- [ ] Disable unsupported actions based on discovery/RBAC.
- [ ] Record local action history.

### 10.5 Tests

- [x] Mutation request tests.
- [x] Dry-run tests against mock server.
- [x] Diff rendering tests.
- [ ] Confirmation flow UI tests.
- [ ] Integration tests against disposable kind cluster.

## Acceptance Criteria

- [ ] User can safely scale a demo deployment.
- [ ] User can restart a rollout.
- [ ] User can delete a disposable resource with clear confirmation.
- [ ] User can preview and apply YAML.
- [ ] Failed mutations leave the UI in a clear, recoverable state.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo scale deploy/echo-web --replicas=3
kubectl -n vibekube-demo rollout restart deploy/echo-web
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
