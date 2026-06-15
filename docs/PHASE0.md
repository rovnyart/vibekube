# Phase 0: Project Foundation

Status: Review checkpoint.

Goal: replace the default Xcode scaffold with a native macOS app foundation that can support cluster selection, resource browsing, logs, and later AI features.

## Current Progress

- [x] Xcode SwiftUI scaffold exists.
- [x] Local kind demo cluster scripts exist under `dev/k8s`.
- [x] High-level roadmap exists in `docs/ROADMAP.md`.
- [x] Phase plan exists in this file.
- [x] App scaffold sample UI removed.
- [x] Vibekube folder/module structure created.
- [x] Native macOS shell implemented.
- [x] Build and test commands documented.
- [x] First UI smoke test updated.

## Implementation Slices

### 0.1 Baseline Audit

- [x] Confirm macOS deployment target.
- [x] Confirm Swift version and Xcode project settings.
- [x] Inspect generated Core Data model usage.
- [x] Decide whether Phase 0 keeps Core Data, removes it, or defers persistence cleanup.
- [x] Record build/test commands in `docs/DEVELOPMENT.md`.

Checkpoint: stop after the audit if deployment target or persistence choice needs user approval.

### 0.2 App Structure

- [x] Create app folders:
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
- [x] Move app entry files into the new structure if Xcode project membership remains clean.
- [x] Add placeholder protocols for core services:
  - `ClusterRegistry`
  - `ConnectionManaging`
  - `ResourceStoring`
  - `UserPreferencesProviding`
- [x] Add mock implementations for preview UI.

Checkpoint: stop after the structure compiles.

### 0.3 Native Shell

- [x] Replace sample `NavigationView`/Core Data item list.
- [x] Implement `NavigationSplitView` shell.
- [x] Add cluster/context sidebar placeholder.
- [x] Add resource group sidebar placeholder.
- [x] Add dashboard placeholder detail view.
- [x] Add native toolbar with:
  - cluster picker placeholder
  - connection status
  - refresh button
  - search button
  - settings button
- [x] Add command menu stubs for refresh, search, cluster switching, and settings.
- [x] Use SF Symbols for toolbar and navigation icons.

Checkpoint: stop when the app first looks like Vibekube instead of the scaffold.

### 0.4 Design Foundation

- [x] Define shared status color tokens.
- [x] Define compact table/list row density constants.
- [x] Define empty/loading/error state components.
- [x] Define connection status badge component.
- [x] Add Liquid Glass/material-aware container styles while preserving data readability.
- [ ] Verify light and dark mode basics.

Checkpoint: stop for visual feedback after the shell and placeholders are visible.

### 0.5 Tests And Documentation

- [x] Update launch UI test to assert Vibekube shell appears.
- [x] Add basic unit test target placeholder for domain logic.
- [x] Add `docs/DEVELOPMENT.md` with:
  - build command
  - test command
  - demo cluster start/stop/status commands
  - troubleshooting notes
- [x] Update `docs/PROGRESS.md` after Phase 0 checkpoint.

## Acceptance Criteria

- [x] App launches into a native Vibekube shell.
- [x] No generated sample item list remains visible.
- [x] Toolbar, sidebar, dashboard placeholder, and resource placeholder are present.
- [x] Build passes from command line.
- [x] Tests pass or any scaffold limitations are documented.
- [x] User can test the visual shell and give feedback before Phase 1.

## Validation Results

- Build passed on June 15, 2026 with `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build`.
- Unit tests passed on June 15, 2026 with `xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test -only-testing:vibekubeTests`.
- Full UI test run compiled but failed before executing UI assertions because Xcode timed out while enabling automation mode locally.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
dev/k8s/scripts/status.sh
```
