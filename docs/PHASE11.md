# Phase 11: Preferences, Security, And Packaging

Status: Started.

Goal: make Vibekube safe and comfortable as a daily app outside the development machine.

## Current Progress

- [x] Phase plan exists.
- [x] Settings view exists for diagnostics.
- [ ] Secret handling audit complete.
- [ ] Keychain strategy implemented where needed.
- [x] Packaging/signing path documented.
- [x] Release script exists.
- [x] App version/build appears in About Vibekube.
- [x] Signed/notarized DMG path has been exercised on the development machine.
- [ ] Clean-machine release validation complete.
- [x] Diagnostics export exists.
- [x] Optional local JSONL file logging exists and is disabled by default.
- [x] Diagnostics retention and cluster-name inclusion settings exist.
- [x] Log buffer and Secret reveal confirmation settings exist.
- [x] Default namespace behavior setting exists.
- [x] Refresh/watch behavior setting exists.
- [x] Kubeconfig path override setting exists.
- [x] Privacy statement exists.

## Implementation Slices

### 11.1 Settings

- [x] Diagnostics file logging toggle.
- [x] Diagnostics cluster-name inclusion toggle.
- [x] Diagnostics retention setting.
- [x] Kubeconfig path settings.
- [x] Default namespace behavior.
- [x] Refresh/watch behavior.
- [ ] Table density.
- [ ] Appearance behavior.
- [x] Log buffer limits.
- [x] Secret reveal confirmation behavior.
- [ ] AI settings placeholder.
- [ ] Reset local preferences action.

### 11.2 Security Audit

- [ ] Audit kubeconfig parsing logs.
- [ ] Audit API client logs.
- [ ] Audit error surfaces.
- [ ] Audit YAML secret display.
- [x] Keep Secret manifest payload fields redacted by default.
- [x] Keep Secret-backed environment values masked by default.
- [ ] Audit AI context redaction hooks.
- [x] Add diagnostics redaction utilities.
- [x] Add diagnostics redaction tests.

### 11.3 Credential Storage

- [ ] Decide what must be stored, if anything.
- [ ] Use Keychain for persisted secrets.
- [ ] Avoid duplicating kubeconfig credentials unnecessarily.
- [x] Document where data lives.

### 11.4 Packaging

- [ ] Decide sandbox entitlement strategy.
- [x] Configure signing.
- [x] Configure notarization path.
- [x] Create release build script.
- [ ] Test app on a clean macOS user profile.
- [x] Add release checklist.
- [ ] Confirm released DMG against at least one non-development Mac.

Checkpoint: stop before changing sandbox/signing settings if they affect local development.

### 11.5 Privacy And Diagnostics

- [x] Add privacy statement.
- [x] Add in-memory diagnostics ring buffer.
- [x] Add optional local JSONL diagnostics logging.
- [x] Add diagnostics export with redaction.
- [x] Add app version/build display.
- [ ] Decide crash reporting policy.

## Acceptance Criteria

- [ ] Settings cover the important app behaviors.
- [ ] No secrets appear in logs, diagnostics, or normal UI errors.
- [x] App can be signed and packaged.
- [x] Fresh-machine setup is documented.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
xcodebuild -project vibekube.xcodeproj -scheme vibekube -configuration Release -destination 'platform=macOS' build
```
