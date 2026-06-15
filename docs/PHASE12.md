# Phase 12: AI Foundations

Status: Not started.

Goal: add safe AI explain/summarize capabilities on top of local Kubernetes context without allowing hidden cluster mutations.

## Current Progress

- [x] Phase plan exists.
- [ ] AI provider abstraction exists.
- [ ] Context builder exists.
- [ ] Redaction pipeline exists.
- [ ] AI panel exists.
- [ ] Read-only explain flows exist.

## Implementation Slices

### 12.1 AI Architecture

- [ ] Define `AIProvider`.
- [ ] Define `AIRequest`.
- [ ] Define `AIResponse`.
- [ ] Define `AIContextBundle`.
- [ ] Define provider configuration model.
- [ ] Add cancellation and retry behavior.
- [ ] Keep AI separate from Kubernetes mutation services.

Checkpoint: stop before choosing or wiring any external provider.

### 12.2 Context Builder

- [ ] Build context for selected resource.
- [ ] Include relevant events.
- [ ] Include relevant conditions.
- [ ] Include selected log snippets.
- [ ] Include related resource summaries.
- [ ] Include cluster version and namespace.
- [ ] Enforce size limits.

### 12.3 Redaction And Policy

- [ ] Redact Secret data.
- [ ] Redact tokens.
- [ ] Redact likely passwords/API keys in env vars.
- [ ] Redact kubeconfig credentials.
- [ ] Show context preview before first external request.
- [ ] Add explicit user consent for sending data outside the Mac.
- [ ] Add tests for redaction.

### 12.4 AI UI

- [ ] Add AI side panel.
- [ ] Explain selected resource.
- [ ] Summarize warning events.
- [ ] Explain pod readiness failure.
- [ ] Summarize selected logs.
- [ ] Generate kubectl command suggestions.
- [ ] Draft YAML changes without applying them.

### 12.5 Guardrails

- [ ] AI cannot mutate the cluster directly.
- [ ] AI command/YAML suggestions are copy or preview only.
- [ ] Every AI answer names the context it used.
- [ ] Empty/missing context is handled honestly.

## Acceptance Criteria

- [ ] User can ask AI to explain a selected demo resource.
- [ ] User can summarize demo logs.
- [ ] Sensitive values are redacted before provider calls.
- [ ] AI-generated actions are never executed automatically.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
