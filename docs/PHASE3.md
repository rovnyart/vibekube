# Phase 3: Main App Shell And Navigation

Status: Not started.

Goal: make the app navigation feel like a real Kubernetes client: cluster, dashboard, resource groups, details, YAML, logs, and settings all reachable through stable routes.

## Current Progress

- [x] Phase plan exists.
- [ ] Route model exists.
- [ ] Sidebar uses real cluster/namespace state.
- [ ] Resource groups are navigable.
- [ ] Toolbar adapts to route.
- [ ] Keyboard shortcuts exist.

## Implementation Slices

### 3.1 Navigation State

- [ ] Define `AppRoute`.
- [ ] Define `ClusterRoute`.
- [ ] Define `ResourceRoute`.
- [ ] Define `ResourceGroup`.
- [ ] Add route restoration for selected cluster and view.
- [ ] Keep routing independent from individual SwiftUI views.

### 3.2 Resource Navigation

- [ ] Add Workloads section.
- [ ] Add Network section.
- [ ] Add Config section.
- [ ] Add Storage section.
- [ ] Add Access Control section.
- [ ] Add Nodes section.
- [ ] Add Namespaces section.
- [ ] Add Events section.
- [ ] Add Custom Resources section.
- [ ] Hide or dim unavailable groups based on discovery state.

### 3.3 Toolbar And Commands

- [ ] Add route-aware refresh.
- [ ] Add search/quick-open command.
- [ ] Add namespace switching command.
- [ ] Add copy resource identity commands.
- [ ] Add open YAML command.
- [ ] Add open logs command where applicable.
- [ ] Add settings command.

### 3.4 Detail Placeholders

- [ ] Dashboard route view.
- [ ] Resource list route view.
- [ ] Resource detail route view.
- [ ] YAML route view.
- [ ] Logs route view.
- [ ] Events route view.
- [ ] Settings route view.

Checkpoint: stop when navigation is complete even if data is still placeholder/mock-backed.

### 3.5 Tests

- [ ] Unit tests for route transitions.
- [ ] UI test for dashboard to pods to placeholder detail.
- [ ] UI test for keyboard shortcut focus behavior.

## Acceptance Criteria

- [ ] User can move through the app without dead ends.
- [ ] Route state survives normal sidebar/detail transitions.
- [ ] Toolbar actions reflect the current screen.
- [ ] Main navigation works with keyboard and pointer.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
