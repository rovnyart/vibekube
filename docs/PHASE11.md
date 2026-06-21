# Phase 11: Preferences, Security, And Packaging

Status: Complete for read-only release.

Goal: make Vibekube safe and comfortable as a daily app outside the development machine.

## Current Progress

- [x] Phase plan exists.
- [x] Settings view exists for diagnostics.
- [x] Secret handling audit complete.
- [x] Keychain strategy implemented where needed.
- [x] Packaging/signing path documented.
- [x] Release script exists.
- [x] App version/build appears in About Vibekube.
- [x] Signed/notarized DMG path has been exercised on the development machine.
- [x] Clean-machine release validation complete.
- [x] Diagnostics export exists.
- [x] Optional local JSONL file logging exists and is disabled by default.
- [x] Diagnostics retention and cluster-name inclusion settings exist.
- [x] Log buffer and Secret reveal confirmation settings exist.
- [x] Default namespace behavior setting exists.
- [x] Refresh/watch behavior setting exists.
- [x] Kubeconfig path override setting exists.
- [x] Table density setting exists.
- [x] Appearance behavior setting exists.
- [x] External terminal app setting exists.
- [x] Reset local preferences action exists.
- [x] Privacy statement exists.
- [x] Crash reporting policy decided.
- [x] AI settings placeholder decision recorded.

## Implementation Slices

### 11.1 Settings

- [x] Diagnostics file logging toggle.
- [x] Diagnostics cluster-name inclusion toggle.
- [x] Diagnostics retention setting.
- [x] Kubeconfig path settings.
- [x] Default namespace behavior.
- [x] Refresh/watch behavior.
- [x] Table density.
- [x] Appearance behavior.
- [x] External terminal app.
- [x] Log buffer limits.
- [x] Secret reveal confirmation behavior.
- [x] AI settings placeholder not shipped before Phase 12.
- [x] Reset local preferences action.

### 11.2 Security Audit

- [x] Audit kubeconfig parsing logs.
- [x] Audit API client logs.
- [x] Audit error surfaces.
- [x] Audit YAML secret display.
- [x] Keep Secret manifest payload fields redacted by default.
- [x] Keep Secret-backed environment values masked by default.
- [x] Confirm AI context redaction is future work; no AI context is built or sent yet, and Linear `ART-40` tracks the required redaction pipeline before Phase 12 enables AI context.
- [x] Add diagnostics redaction utilities.
- [x] Add diagnostics redaction tests.

Audit result: kubeconfig parsing does not log raw kubeconfig content, bearer tokens, or client key/certificate payloads. API client authentication applies credentials only to ephemeral `URLRequest` headers. Secret list rows avoid indexing payload data, Secret YAML redacts top-level `data`, `stringData`, and `binaryData`, Secret annotations and Secret-backed environment values stay masked by default, and reveal actions log only hashed namespace/Secret/key identifiers. Diagnostics metadata already redacted sensitive keys and bearer-like values; this checkpoint also redacts free-form diagnostics messages, Kubernetes client error descriptions, Kubernetes status messages, transport errors, and exec-plugin stderr for bearer tokens, token/password/secret/key fields, command-line secret flags, and PEM private key/certificate blocks.

### 11.3 Credential Storage

- [x] Decide what must be stored, if anything.
- [x] Use Keychain for persisted secrets where needed.
- [x] Avoid duplicating kubeconfig credentials unnecessarily.
- [x] Document where data lives.

Credential storage decision: Vibekube does not currently store app-owned secrets. Kubeconfig credentials are read from kubeconfig files or path references as needed, exec credentials are cached in memory only until their Kubernetes `expirationTimestamp`, and decoded Secret values are revealed in memory only for the selected UI session. Client certificate/key material is imported into a temporary keychain only to create the `SecIdentity` required by `URLSession` mTLS; that temporary keychain is deleted when the session delegate is deallocated and is not a persistent credential store. Because there are no persisted Vibekube-owned secrets today, no login-keychain storage is required for the current read-only release. If future AI providers, hosted services, mutation credentials, or user-entered tokens require persistence, storing them in Keychain is mandatory before shipping that feature.

### 11.4 Packaging

- [x] Decide sandbox entitlement strategy.
- [x] Configure signing.
- [x] Configure notarization path.
- [x] Create release build script.
- [x] Test app on a clean macOS user profile or non-development Mac.
- [x] Add release checklist.
- [x] Confirm released DMG against at least one non-development Mac.

Validation note: the app has been used daily on a separate work Mac since version 0.3.0, including real-cluster workflows. This closes the Phase 11 clean-machine/non-development-machine validation item as of 2026-06-20. Keep `docs/RELEASE_CHECKLIST.md` as a per-release checklist for future DMG builds.

Sandbox decision: keep App Sandbox disabled for the current direct Developer ID distribution. Vibekube needs to read kubeconfig files and referenced certificate/key files from user-controlled locations, open outbound Kubernetes API connections, run kubeconfig exec credential plugins such as `tsh`, launch external-terminal `kubectl exec`, and run `kubectl port-forward`. A sandboxed build would require a broader file-access/bookmark, process-execution, and helper-tool design pass, and would likely break common kubeconfig exec-auth workflows. Hardened runtime, signing, notarization, local-first behavior, redaction, and the no-persistent-secret policy are the current release hardening boundary.

Checkpoint: stop before changing sandbox/signing settings if they affect local development.

### 11.5 Privacy And Diagnostics

- [x] Add privacy statement.
- [x] Add in-memory diagnostics ring buffer.
- [x] Add optional local JSONL diagnostics logging.
- [x] Add diagnostics export with redaction.
- [x] Add app version/build display.
- [x] Decide crash reporting policy.

Crash reporting decision: Vibekube does not include automatic crash reporting, telemetry, analytics, or automatic update checks in the current direct-distribution release. Diagnostics remain local and user-driven: the app keeps an in-memory diagnostics buffer, optional local JSONL logging is disabled by default, and exports happen only when the user explicitly invokes them. macOS may still create system crash reports outside Vibekube's control. If Vibekube adds automatic crash reporting later, it must be opt-in, documented in `docs/PRIVACY.md`, and go through the same redaction/privacy review as future AI network paths.

AI settings decision: do not ship a visible AI settings placeholder before Phase 12. A placeholder would imply unfinished network/provider behavior and make the privacy story less clear. AI settings should appear only when the provider, consent, storage, and redaction model is implemented.

## Acceptance Criteria

- [x] Settings cover the important app behaviors.
- [x] No secrets appear in logs, diagnostics, or normal UI errors.
- [x] App can be signed and packaged.
- [x] Fresh-machine setup is documented.

## Validation Commands

```sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' build
xcodebuild -project vibekube.xcodeproj -scheme vibekube -configuration Release -destination 'platform=macOS' build
```
