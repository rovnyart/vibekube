# Phase 3: Main App Shell And Navigation

Status: Review checkpoint.

Goal: make the app navigation feel like a real Kubernetes client: cluster, dashboard, resource groups, details, YAML, logs, and settings all reachable through stable routes.

## Current Progress

- [x] Phase plan exists.
- [x] Basic route state exists through `ResourceNavigationItem` and `AppModel.selectedResource`.
- [x] Sidebar uses real cluster/namespace state.
- [x] Resource groups are navigable.
- [x] Toolbar exposes cluster, namespace, search, refresh, and settings controls.
- [x] Basic keyboard shortcuts exist for dashboard, pods, logs, and refresh.
- [ ] Formal app route model with restoration exists.
- [ ] Toolbar is fully route-aware for resource detail/YAML/log actions.
- [ ] Keyboard shortcut coverage is complete.

## Checkpoint Notes

- The app uses a three-column native `NavigationSplitView`: clusters, resource navigation, and detail content.
- Cluster selection, connect/disconnect, namespace selection, search, refresh, and settings are reachable from the toolbar.
- Resource navigation is grouped into Overview, Workloads, Network, Config, Storage, Access Control, Cluster, and Custom.
- Built-in resource groups route to live list views when discovery finds the matching API resource.
- Dashboard, Logs, Settings, Custom Resources, resource lists, bottom detail inspector tabs, and placeholder states are reachable without dead ends.
- The current shell is functional, but not yet a formal persisted route system. Deep links, restoration, quick-open, and route-aware detail commands remain future work.

## Implementation Slices

### 3.1 Navigation State

- [ ] Define formal `AppRoute`.
- [ ] Define formal `ClusterRoute`.
- [x] Define resource navigation item model.
- [x] Define resource navigation sections.
- [ ] Add route restoration for selected cluster and view.
- [ ] Keep routing independent from individual SwiftUI views.

### 3.2 Resource Navigation

- [x] Add Workloads section.
- [x] Add Network section.
- [x] Add Config section.
- [x] Add Storage section.
- [x] Add Access Control section.
- [x] Add Cluster section with Nodes, Namespaces, and Events.
- [x] Add Custom Resources section.
- [x] Show discovery/scope indicators for available resources.
- [ ] Hide or dim unavailable groups based on discovery state.

### 3.3 Toolbar And Commands

- [x] Add refresh command.
- [ ] Add search/quick-open command.
- [x] Add namespace switching control.
- [ ] Add copy resource identity commands.
- [ ] Add open YAML command.
- [ ] Add open logs command where applicable.
- [x] Add settings command.

### 3.4 Detail Placeholders

- [x] Dashboard route view.
- [x] Resource list route view.
- [x] Resource detail inspector route.
- [x] YAML detail tab.
- [x] Logs placeholder route view.
- [x] Events resource route and detail tab.
- [x] Settings placeholder route view.

Checkpoint: stop when navigation is complete even if data is still placeholder/mock-backed.

### 3.5 Tests

- [ ] Unit tests for route transitions.
- [x] Preview UI smoke test opens resource detail overview.
- [ ] UI test for dashboard to pods to placeholder detail.
- [ ] UI test for keyboard shortcut focus behavior.

## Acceptance Criteria

- [x] User can move through the app without dead ends.
- [ ] Route state survives app relaunch.
- [ ] Toolbar actions fully reflect the current screen.
- [x] Main navigation works with pointer.
- [ ] Main navigation works comprehensively with keyboard.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
