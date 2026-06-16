# Phase 8: Watches And Real-Time Updates

Status: Started.

Goal: keep resource lists and details current through Kubernetes watches without flicker or stale data confusion.

## Current Progress

- [x] Phase plan exists.
- [x] Watch request support exists.
- [x] Watch event parser exists.
- [x] Active Pods list applies watch updates.
- [x] Reconnect/backoff exists for active Pods list watches.
- [x] UI indicates live/reconnecting/stale/failure state for active Pods list watches.
- [x] Open Pod details refresh when watched list rows move to a newer resourceVersion.
- [ ] True selected-resource detail watches and broader resource watches exist.

## Implementation Slices

### 8.1 Watch API

- [x] Add `watch=true` request builder.
- [x] Track `resourceVersion`.
- [x] Decode ADDED/MODIFIED/DELETED/BOOKMARK/ERROR events.
- [ ] Handle `410 Gone` by relisting.
- [x] Add timeout and cancellation behavior.

### 8.2 Watch Service

- [x] Define resource watch stream on the resource list service.
- [x] Start watches for the active Pods resource list.
- [ ] Start detail watch for selected resource.
- [x] Stop watches on route/context/namespace changes.
- [x] Apply backoff on transient failures for active Pods.
- [x] Surface persistent watch errors in the resource-list header.

### 8.3 Store Integration

- [x] Merge ADDED events.
- [x] Merge MODIFIED events.
- [x] Remove DELETED resources.
- [x] Preserve table selection where possible by mutating the existing loaded snapshot.
- [x] Refresh selected detail manifests when watched rows report a newer resourceVersion.
- [ ] Throttle high-volume updates.
- [ ] Avoid row jumping while user is interacting.

### 8.4 UI

- [x] Live status indicator.
- [x] Reconnecting/stale/failure status indicator.
- [x] Manual refresh fallback.
- [x] Detail header shows refreshing/updated/stale state.
- [ ] Subtle updated row indication.
- [ ] No noisy notifications for normal watch updates.

Checkpoint: stop when pod list updates as demo CronJobs create pods.

### 8.5 Tests

- [x] Watch parser tests.
- [ ] ResourceVersion relist tests.
- [x] Store merge tests for active Pods ADDED events.
- [x] Detail refresh test for active Pods MODIFIED events.
- [ ] Mock watch reconnect tests.
- [ ] Manual QA with demo CronJob pods.

## Acceptance Criteria

- [ ] Resource lists update without manual refresh.
- [x] Watch failures are visible but not disruptive for active Pods.
- [ ] Switching cluster or namespace cancels old watches.
- [ ] Selection and scroll position are not unnecessarily disrupted.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo get pods -w
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
