# Phase 8: Watches And Real-Time Updates

Status: Started.

Goal: keep resource lists and details current through Kubernetes watches without flicker or stale data confusion.

## Current Progress

- [x] Phase plan exists.
- [x] Watch request support exists.
- [x] Watch event parser exists.
- [x] Active resource lists apply watch updates when the discovered resource supports `watch`.
- [x] Reconnect/backoff exists for active resource list watches.
- [x] UI indicates live/reconnecting/stale/failure state for active resource list watches.
- [x] Expired watch resourceVersions relist and resume from a fresh resourceVersion.
- [x] Open resource details refresh when watched list rows move to a newer resourceVersion.
- [x] Broader active-resource list watches exist.
- [x] True selected-resource detail watches exist.
- [x] Transient watch timeouts keep reconnecting after long idle/background periods.

## Implementation Slices

### 8.1 Watch API

- [x] Add `watch=true` request builder.
- [x] Track `resourceVersion`.
- [x] Decode ADDED/MODIFIED/DELETED/BOOKMARK/ERROR events.
- [x] Handle `410 Gone` by relisting.
- [x] Add timeout and cancellation behavior.

### 8.2 Watch Service

- [x] Define resource watch stream on the resource list service.
- [x] Start watches for active resource lists whose discovered API resource supports `watch`.
- [x] Start detail watch for selected resource.
- [x] Stop watches on route/context/namespace changes.
- [x] Apply backoff on transient failures for active resource watches.
- [x] Surface persistent watch errors in the resource-list header.
- [x] Keep retrying transient transport failures with capped backoff instead of stopping after a small retry budget.

### 8.3 Store Integration

- [x] Merge ADDED events.
- [x] Merge MODIFIED events.
- [x] Remove DELETED resources.
- [x] Preserve table selection where possible by mutating the existing loaded snapshot.
- [x] Refresh selected detail manifests when watched rows report a newer resourceVersion.
- [x] Throttle high-volume updates.
- [x] Avoid row jumping while user is interacting.

### 8.4 UI

- [x] Live status indicator.
- [x] Reconnecting/stale/failure status indicator.
- [x] Manual refresh fallback.
- [x] Detail header shows refreshing/updated/stale state.
- [ ] Subtle updated row indication.
- [ ] No noisy notifications for normal watch updates.

Checkpoint: stop when pod and deployment lists can receive watch updates without manual refresh.

### 8.5 Tests

- [x] Watch parser tests.
- [x] ResourceVersion relist tests.
- [x] Transient watch reconnect persistence test.
- [x] Store merge tests for active Pods and Deployments ADDED events.
- [x] Detail refresh tests for active Pod and Deployment MODIFIED events.
- [x] Selected-resource detail watch refresh test.
- [x] Burst watch coalescing test.
- [ ] Mock watch reconnect tests.
- [ ] Manual QA with demo CronJob pods.

## Acceptance Criteria

- [x] Watchable active resource lists update without manual refresh.
- [x] Watch failures are visible but not disruptive for active resources.
- [x] Switching cluster or namespace cancels old watches.
- [x] Selection and scroll position are not unnecessarily disrupted.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo get pods -w
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
