# Phase 10: Safe Mutations

Status: Started.

Goal: add common write operations with strong previews, confirmations, RBAC awareness, and rollback-friendly behavior.

## Current Progress

- [x] Phase plan exists.
- [x] Mutation API exists.
- [x] Dry-run/diff support exists.
- [x] Confirmations exist for existing-resource YAML apply.
- [ ] Scale/restart/delete/apply flows exist.
- [ ] Local action history exists.
- [x] Kubernetes `Status` mutation errors surface HTTP code, reason, field causes, and retry hints.
- [x] Dry-run is supported at the request layer and exposed in the YAML detail editor as a no-apply preview.
- [x] Non-UI mutation preview foundation parses YAML, validates target identity, runs server-side dry-run, fetches live state, and produces a diff.
- [x] YAML detail tab can edit a highlighted draft manifest and render server-side dry-run diff or validation errors without mutating the cluster.
- [x] Existing-resource YAML edits can be searched, previewed in a split or expanded diff, confirmed, applied, and refreshed back into the detail/list UI.
- [x] Rendered Kubernetes YAML from existing resources can be round-tripped through preview, including managedFields keys and resource quantity edits.

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
- [x] Show RBAC/permission failures clearly.

Checkpoint: existing-resource YAML edits now have a highlighted editor with line numbers, indentation help, keyboard-friendly draft search, server-side dry-run preview, split and expanded diff rendering, validation causes, conflict handling, permission/error surfacing, confirmation-gated apply, and post-apply detail/list refresh. Rendered resource YAML round-trips through the preview parser for managedFields and resource quantity edits.

### 10.3 Common Actions

- [ ] Scale Deployment.
- [ ] Scale StatefulSet.
- [ ] Restart rollout.
- [ ] Delete resource.
- [x] Edit existing-resource YAML.
- [ ] Create resource from YAML.
- [ ] Apply YAML file.
- [ ] Create namespace.
- [ ] Delete namespace.
- [ ] Create ConfigMap basics.
- [ ] Create Secret basics with hidden values.

### 10.4 Safety UX

- [x] Confirm cluster/context for existing-resource YAML apply.
- [x] Confirm namespace for existing-resource YAML apply.
- [x] Confirm kind/name for existing-resource YAML apply.
- [ ] Require typed confirmation for destructive actions.
- [ ] Disable unsupported actions based on discovery/RBAC.
- [ ] Record local action history.

### 10.5 Tests

- [x] Mutation request tests.
- [x] Dry-run tests against mock server.
- [x] Diff rendering tests.
- [x] AppModel preview wiring tests.
- [x] AppModel apply wiring tests.
- [x] Rendered YAML preview regression tests for managedFields and resource quantities.
- [ ] Confirmation flow UI tests.
- [ ] Integration tests against disposable kind cluster.

## Acceptance Criteria

- [ ] User can safely scale a demo deployment.
- [ ] User can restart a rollout.
- [ ] User can delete a disposable resource with clear confirmation.
- [x] User can preview and apply existing-resource YAML.
- [ ] Failed mutations leave the UI in a clear, recoverable state.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo scale deploy/echo-web --replicas=3
kubectl -n vibekube-demo rollout restart deploy/echo-web
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```

## Validation Log

- 2026-06-21: Focused mutation tests passed:
  `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests/KubernetesMutationPreviewTests -only-testing:vibekubeTests/vibekubeTests/appModelAppliesPreviewedMutationForSelectedResourceRow -only-testing:vibekubeTests/vibekubeTests/appModelPreviewsMutationForSelectedResourceRow`
- 2026-06-21: Manual Computer Use QA against `kind-vibekube-dev` edited `Deployment/echo-web` YAML, searched the draft, previewed the server dry-run diff, expanded the diff, confirmed apply, and verified the live resource returned to `64Mi` memory with `kubectl`.
- 2026-06-21: Manual Computer Use QA verified edit-mode `Cmd+F` focuses draft search from the WebKit editor, Enter advances matches while keeping focus in search, and only one Apply action appears after dry-run preview.
