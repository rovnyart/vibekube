# Phase 11: Preferences, Security, And Packaging

Status: Not started.

Goal: make Vibekube safe and comfortable as a daily app outside the development machine.

## Current Progress

- [x] Phase plan exists.
- [ ] Settings window exists.
- [ ] Secret handling audit complete.
- [ ] Keychain strategy implemented where needed.
- [ ] Packaging/signing path documented.
- [ ] Release build works.

## Implementation Slices

### 11.1 Settings

- [ ] Kubeconfig path settings.
- [ ] Default namespace behavior.
- [ ] Refresh/watch behavior.
- [ ] Table density.
- [ ] Appearance behavior.
- [ ] Log buffer limits.
- [ ] AI settings placeholder.
- [ ] Reset local preferences action.

### 11.2 Security Audit

- [ ] Audit kubeconfig parsing logs.
- [ ] Audit API client logs.
- [ ] Audit error surfaces.
- [ ] Audit YAML secret display.
- [ ] Audit AI context redaction hooks.
- [ ] Add redaction utilities where missing.
- [ ] Add tests for redaction.

### 11.3 Credential Storage

- [ ] Decide what must be stored, if anything.
- [ ] Use Keychain for persisted secrets.
- [ ] Avoid duplicating kubeconfig credentials unnecessarily.
- [ ] Document where data lives.

### 11.4 Packaging

- [ ] Decide sandbox entitlement strategy.
- [ ] Configure signing.
- [ ] Configure notarization path.
- [ ] Create release build script.
- [ ] Test app on a clean macOS user profile.
- [ ] Add release checklist.

Checkpoint: stop before changing sandbox/signing settings if they affect local development.

### 11.5 Privacy And Diagnostics

- [ ] Add privacy statement.
- [ ] Add diagnostics export with redaction.
- [ ] Add app version/build display.
- [ ] Decide crash reporting policy.

## Acceptance Criteria

- [ ] Settings cover the important app behaviors.
- [ ] No secrets appear in logs, diagnostics, or normal UI errors.
- [ ] App can be signed and packaged.
- [ ] Fresh-machine setup is documented.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
xcodebuild -project vibekube.xcodeproj -scheme vibekube -configuration Release -destination 'platform=macOS' build
```
