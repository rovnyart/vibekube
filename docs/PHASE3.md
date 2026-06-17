# Phase 3: Main App Shell And Navigation

Status: Review checkpoint.

Goal: make the app navigation feel like a real Kubernetes client: cluster, dashboard, resource groups, details, YAML, logs, and settings all reachable through stable routes.

## Current Progress

- [x] Phase plan exists.
- [x] Basic route state exists through `ResourceNavigationItem` and `AppModel.selectedResource`.
- [x] Sidebar uses real cluster/namespace state.
- [x] Resource groups are navigable.
- [x] Toolbar exposes cluster, searchable namespace, search, refresh, and settings controls.
- [x] Keyboard shortcuts exist for search, common routes, detail tabs, YAML, detail logs, and refresh.
- [x] Formal top-level app route model with selected cluster/resource restoration exists.
- [x] Menus expose route-aware resource detail/YAML/log actions.
- [ ] Full keyboard navigation and focus traversal coverage is complete.

## Checkpoint Notes

- The app uses a three-column native `NavigationSplitView`: clusters, resource navigation, and detail content.
- Cluster selection, connect/disconnect, searchable namespace selection, search, refresh, and settings are reachable from the toolbar.
- Resource navigation is grouped into Overview, Workloads, Network, Config, Storage, Access Control, Cluster, and Custom.
- Built-in resource groups route to live list views when discovery finds the matching API resource.
- Dashboard, Settings, Custom Resources, resource lists, bottom detail inspector tabs, and placeholder states are reachable without dead ends.
- A standalone top-level Logs route was removed; logs now live in the resource detail inspector where the selected Pod context is explicit.
- The current shell has a persisted top-level `AppRoute` for selected cluster and resource, plus focused commands for the active resource detail inspector. Deep links, full resource-detail routes, and a true quick-open palette remain future work.

## Implementation Slices

### 3.1 Navigation State

- [x] Define formal `AppRoute`.
- [ ] Define formal `ClusterRoute`.
- [x] Define resource navigation item model.
- [x] Define resource navigation sections.
- [x] Add route restoration for selected cluster and view.
- [x] Keep top-level routing independent from individual SwiftUI views.

### 3.2 Resource Navigation

- [x] Add Workloads section.
- [x] Add Network section.
- [x] Add Config section.
- [x] Add Storage section.
- [x] Add Access Control section.
- [x] Add Cluster section with Nodes, Namespaces, and Events.
- [x] Add Custom Resources section.
- [x] Show discovery/scope indicators for available resources.
- [x] Dim unavailable resources based on discovery state.

### 3.3 Toolbar And Commands

- [x] Add refresh command.
- [x] Add search command.
- [ ] Add true quick-open palette.
- [x] Add namespace switching control.
- [x] Add namespace search for clusters with large namespace counts.
- [x] Add copy resource identity commands.
- [x] Add open YAML command for active detail inspector.
- [x] Add open logs command where applicable.
- [x] Add settings command.

### 3.4 Detail Placeholders

- [x] Dashboard route view.
- [x] Resource list route view.
- [x] Resource detail inspector route.
- [x] YAML detail tab.
- [x] Pod detail Logs tab is reachable from the resource detail inspector.
- [x] Events resource route and detail tab.
- [x] Settings placeholder route view.

Checkpoint: stop when navigation is complete even if data is still placeholder/mock-backed.

### 3.5 Tests

- [x] Unit tests for route transitions.
- [x] Model and view-level smoke coverage exercises resource detail overview state.
- [ ] UI test for dashboard to pods to placeholder detail.
- [ ] UI test for keyboard shortcut focus behavior.

## Acceptance Criteria

- [x] User can move through the app without dead ends.
- [x] Top-level selected cluster/resource route state survives app relaunch.
- [x] Menus expose route-aware actions for current shell/detail context.
- [x] Main navigation works with pointer.
- [ ] Main navigation works comprehensively with keyboard and focus traversal.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
