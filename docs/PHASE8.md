# Phase 8: Watches And Real-Time Updates

Status: Started.

Goal: keep resource lists and details current through Kubernetes watches without flicker or stale data confusion.

## Current Progress

- [x] Phase plan exists.
- [x] Watch request support exists.
- [x] Watch event parser exists.
- [x] Active Pods list applies watch updates.
- [ ] Reconnect/backoff exists.
- [ ] UI indicates live/stale state.

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
- [ ] Apply backoff on transient failures.
- [ ] Surface permanent errors.

### 8.3 Store Integration

- [x] Merge ADDED events.
- [x] Merge MODIFIED events.
- [x] Remove DELETED resources.
- [x] Preserve table selection where possible by mutating the existing loaded snapshot.
- [ ] Throttle high-volume updates.
- [ ] Avoid row jumping while user is interacting.

### 8.4 UI

- [ ] Live status indicator.
- [ ] Stale/offline status indicator.
- [ ] Manual refresh fallback.
- [ ] Subtle updated row indication.
- [ ] No noisy notifications for normal watch updates.

Checkpoint: stop when pod list updates as demo CronJobs create pods.

### 8.5 Tests

- [x] Watch parser tests.
- [ ] ResourceVersion relist tests.
- [x] Store merge tests for active Pods ADDED events.
- [ ] Mock watch reconnect tests.
- [ ] Manual QA with demo CronJob pods.

## Acceptance Criteria

- [ ] Resource lists update without manual refresh.
- [ ] Watch failures are visible but not disruptive.
- [ ] Switching cluster or namespace cancels old watches.
- [ ] Selection and scroll position are not unnecessarily disrupted.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo get pods -w
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
