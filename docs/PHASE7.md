# Phase 7: Logs

Status: Not started.

Goal: provide a fast, native log viewer for pods, containers, and common workload-owned pods.

## Current Progress

- [x] Phase plan exists.
- [ ] Pod log request builder exists.
- [ ] Streaming log client exists.
- [ ] Logs route exists.
- [ ] Container selector exists.
- [ ] Follow, pause, search, copy, and save controls exist.

## Implementation Slices

### 7.1 Log API

- [ ] Build pod log endpoint.
- [ ] Support `container`.
- [ ] Support `previous`.
- [ ] Support `follow`.
- [ ] Support `tailLines`.
- [ ] Support `sinceSeconds`.
- [ ] Support `timestamps`.
- [ ] Map log API errors to user-facing states.

### 7.2 Streaming Engine

- [ ] Represent logs as cancellable async sequence.
- [ ] Buffer log chunks off the main actor.
- [ ] Cap memory for long streams.
- [ ] Strip or render ANSI sequences.
- [ ] Handle reconnect/retry manually.
- [ ] Cancel streams on route/context change.

### 7.3 Logs UI

- [ ] Monospaced log view.
- [ ] Container selector.
- [ ] Follow toggle.
- [ ] Previous logs toggle.
- [ ] Tail line selector.
- [ ] Since selector.
- [ ] Timestamp toggle.
- [ ] Search/filter.
- [ ] Pause/resume.
- [ ] Copy selected lines.
- [ ] Save logs.
- [ ] Inline retry on stream failure.

Checkpoint: stop when `log-counter` streams smoothly in the demo cluster.

### 7.4 Workload Logs

- [ ] Open logs from a Pod.
- [ ] Open logs from a Deployment by selecting owned Pods.
- [ ] Open logs from a Job by selecting owned Pods.
- [ ] Add multi-pod aggregation plan but defer if it risks Phase 7 scope.

### 7.5 Tests

- [ ] Log URL construction tests.
- [ ] Streaming parser tests.
- [ ] Buffer limit tests.
- [ ] Integration/manual QA against `vibekube-demo/log-counter`.

## Acceptance Criteria

- [ ] User can stream live logs from the demo `log-counter` pod.
- [ ] User can pause, search, copy, and save logs.
- [ ] Scrolling away from the bottom disables aggressive auto-follow behavior.
- [ ] Large logs do not freeze the app.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo logs -f deploy/log-counter
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
