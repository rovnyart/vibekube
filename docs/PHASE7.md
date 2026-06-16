# Phase 7: Logs

Status: Review checkpoint.

Goal: provide a fast, native log viewer for pods, containers, and common workload-owned pods.

## Current Progress

- [x] Phase plan exists.
- [x] Pod log request builder exists.
- [x] Streaming log client exists.
- [x] Pod detail Logs tab exists.
- [x] Container selector exists for multi-container Pods.
- [x] Timestamp, live/follow, search, grep/filter, copy, and expanded-view controls exist.
- [x] Previous terminated-container logs, tail selector, download-all, and save-current-view controls exist.
- [x] Safe JSONL pretty-print mode exists for readable structured logs.
- [x] Scroll-aware live follow with jump-to-latest exists.
- [x] Pause/resume exists via the Live toggle.
- [ ] Since selector exists.

## Checkpoint Notes

- The primary logs entry point is the Pod detail inspector: open Pods, select a Pod, then choose the Logs tab.
- The standalone Logs route is hidden from primary navigation until it has a clearer product role.
- The Logs tab supports bounded tail loading and live streaming via Kubernetes `follow=true`.
- Live streaming starts with `tailLines=0` and seeds from the already-loaded recent tail, so enabling Live appends new lines instead of replaying the pod log backlog.
- The Live checkbox is the pause/resume control: turning it off stops streaming and keeps the current snapshot visible.
- Log requests support container, previous, follow, tailLines, sinceSeconds, and timestamps at the request model level.
- The UI can toggle timestamps, live streaming, JSONL pretty-printing, search highlighting, grep-style line filtering, manual refresh, displayed-log copy, and an expanded log sheet.
- Live auto-follow is scroll-aware: if the user scrolls away from the bottom, Vibekube stops forcing the view downward and shows a jump-to-latest action.
- Live logs are capped in memory to the most recent 5,000 lines.
- Previous terminated-container logs, tail selector, download-all logs, and save-current-view are wired through the Pod detail Logs tab.
- JSONL mode safely pretty-prints valid object/array log lines and leaves malformed or plain-text lines unchanged. Grep still filters against raw log lines; copy/save displayed logs use the rendered view.
- Since controls remain pending.
- Large-log hardening still needs stream retry UI, ANSI handling, and explicit buffer-limit tests.

## Implementation Slices

### 7.1 Log API

- [x] Build pod log endpoint.
- [x] Support `container`.
- [x] Support `previous`.
- [x] Support `follow`.
- [x] Support `tailLines`.
- [x] Support `sinceSeconds`.
- [x] Support `timestamps`.
- [x] Map log API errors to user-facing states.

### 7.2 Streaming Engine

- [x] Represent logs as cancellable async sequence.
- [x] Buffer log chunks off the main actor.
- [x] Cap memory for long streams.
- [ ] Strip or render ANSI sequences.
- [ ] Handle reconnect/retry manually.
- [x] Cancel streams on route/context change.

### 7.3 Logs UI

- [x] Monospaced log view.
- [x] Container selector.
- [x] Follow toggle.
- [x] Previous terminated-container logs toggle.
- [x] Tail line selector.
- [ ] Since selector.
- [x] Timestamp toggle.
- [x] Search/filter target Pods through toolbar search.
- [x] Search current logs with highlighted matches.
- [x] Grep-style filter for matching log lines.
- [x] Safe JSONL pretty-print mode for structured log lines.
- [x] Expanded log view.
- [x] Pause/resume through the Live toggle.
- [x] Scroll-aware live follow and jump-to-latest.
- [x] Copy displayed lines.
- [x] Download all available logs for the selected pod/container.
- [x] Save currently displayed/filtered logs.
- [ ] Inline retry on stream failure.
- [x] Manual refresh for current Pod logs.

Checkpoint: stop when selecting `log-counter` can tail, stream, scroll without forced follow, jump to latest, search, grep-filter, JSON-format, copy, and expand logs without freezing.

### 7.4 Workload Logs

- [x] Open logs from a Pod through the Pod detail inspector.
- [ ] Open logs from a Deployment by selecting owned Pods.
- [ ] Open logs from a Job by selecting owned Pods.
- [ ] Add multi-pod aggregation plan but defer if it risks Phase 7 scope.

### 7.5 Tests

- [x] Log query construction tests.
- [x] App model log route and Pod log load tests.
- [x] App model streaming append tests.
- [ ] Streaming parser tests.
- [ ] Buffer limit tests.
- [ ] Integration/manual QA against `vibekube-demo/log-counter` JSONL logs.

## Acceptance Criteria

- [x] User can stream live logs from the demo `log-counter` pod.
- [x] User can pause logs by turning Live off.
- [x] User can search, grep, JSON-format, copy, download all logs, save displayed logs, and view previous terminated-container logs.
- [x] Scrolling away from the bottom disables aggressive auto-follow behavior.
- [ ] Large logs do not freeze the app.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo logs -f deploy/log-counter
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
