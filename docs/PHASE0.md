# Phase 0: Project Foundation

Status: In planning. This phase is the first implementation target.

Goal: replace the default Xcode scaffold with a native macOS app foundation that can support cluster selection, resource browsing, logs, and later AI features.

## Current Progress

- [x] Xcode SwiftUI scaffold exists.
- [x] Local kind demo cluster scripts exist under `dev/k8s`.
- [x] High-level roadmap exists in `docs/ROADMAP.md`.
- [x] Phase plan exists in this file.
- [ ] App scaffold sample UI removed.
- [ ] Vibekube folder/module structure created.
- [ ] Native macOS shell implemented.
- [ ] Build and test commands documented.
- [ ] First UI smoke test updated.

## Implementation Slices

### 0.1 Baseline Audit

- [ ] Confirm macOS deployment target.
- [ ] Confirm Swift version and Xcode project settings.
- [ ] Inspect generated Core Data model usage.
- [ ] Decide whether Phase 0 keeps Core Data, removes it, or defers persistence cleanup.
- [ ] Record build/test commands in `docs/DEVELOPMENT.md`.

Checkpoint: stop after the audit if deployment target or persistence choice needs user approval.

### 0.2 App Structure

- [ ] Create app folders:
  - `App`
  - `Features`
  - `Features/Clusters`
  - `Features/Dashboard`
  - `Features/Resources`
  - `Features/Logs`
  - `Domain`
  - `KubernetesClient`
  - `Persistence`
  - `SharedUI`
  - `Infrastructure`
- [ ] Move app entry files into the new structure if Xcode project membership remains clean.
- [ ] Add placeholder protocols for core services:
  - `ClusterRegistry`
  - `ConnectionManaging`
  - `ResourceStoring`
  - `UserPreferencesProviding`
- [ ] Add mock implementations for preview UI.

Checkpoint: stop after the structure compiles.

### 0.3 Native Shell

- [ ] Replace sample `NavigationView`/Core Data item list.
- [ ] Implement `NavigationSplitView` shell.
- [ ] Add cluster/context sidebar placeholder.
- [ ] Add resource group sidebar placeholder.
- [ ] Add dashboard placeholder detail view.
- [ ] Add native toolbar with:
  - cluster picker placeholder
  - connection status
  - refresh button
  - search button
  - settings button
- [ ] Add command menu stubs for refresh, search, cluster switching, and settings.
- [ ] Use SF Symbols for toolbar and navigation icons.

Checkpoint: stop when the app first looks like Vibekube instead of the scaffold.

### 0.4 Design Foundation

- [ ] Define shared status color tokens.
- [ ] Define compact table/list row density constants.
- [ ] Define empty/loading/error state components.
- [ ] Define connection status badge component.
- [ ] Add Liquid Glass/material-aware container styles while preserving data readability.
- [ ] Verify light and dark mode basics.

Checkpoint: stop for visual feedback after the shell and placeholders are visible.

### 0.5 Tests And Documentation

- [ ] Update launch UI test to assert Vibekube shell appears.
- [ ] Add basic unit test target placeholder for domain logic.
- [ ] Add `docs/DEVELOPMENT.md` with:
  - build command
  - test command
  - demo cluster start/stop/status commands
  - troubleshooting notes
- [ ] Update `docs/PROGRESS.md` after Phase 0 completion.

## Acceptance Criteria

- [ ] App launches into a native Vibekube shell.
- [ ] No generated sample item list remains visible.
- [ ] Toolbar, sidebar, dashboard placeholder, and resource placeholder are present.
- [ ] Build passes from command line.
- [ ] Tests pass or any scaffold limitations are documented.
- [ ] User can test the visual shell and give feedback before Phase 1.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
dev/k8s/scripts/status.sh
```
