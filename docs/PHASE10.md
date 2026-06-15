# Phase 10: Safe Mutations

Status: Not started.

Goal: add common write operations with strong previews, confirmations, RBAC awareness, and rollback-friendly behavior.

## Current Progress

- [x] Phase plan exists.
- [ ] Mutation API exists.
- [ ] Dry-run/diff support exists.
- [ ] Confirmations exist.
- [ ] Scale/restart/delete/apply flows exist.
- [ ] Local action history exists.

## Implementation Slices

### 10.1 Mutation Foundation

- [ ] Define `MutationRequest`.
- [ ] Define `MutationPreview`.
- [ ] Define `MutationResult`.
- [ ] Implement POST.
- [ ] Implement PUT.
- [ ] Implement PATCH.
- [ ] Implement DELETE.
- [ ] Decode Kubernetes `Status`.
- [ ] Support dry-run where available.

Checkpoint: stop before enabling any mutation UI against a real cluster.

### 10.2 Diff And Validation

- [ ] Parse YAML safely.
- [ ] Validate apiVersion/kind/metadata.
- [ ] Validate namespace targeting.
- [ ] Fetch live object for diff.
- [ ] Render diff preview.
- [ ] Detect conflicts/resourceVersion issues.
- [ ] Show RBAC/permission failures clearly.

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

- [ ] Mutation request tests.
- [ ] Dry-run tests against mock server.
- [ ] Diff rendering tests.
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
