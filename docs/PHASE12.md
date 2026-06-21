# Phase 12: AI Foundations

Status: In progress.

Goal: add safe AI explain/summarize capabilities on top of local Kubernetes context without allowing hidden cluster mutations.

## Current Progress

- [x] Phase plan exists.
- [x] AI provider abstraction exists.
- [x] Keychain-backed provider secrets exist.
- [x] Provider model discovery/test settings UI exists.
- [x] Context builder exists.
- [x] Redaction pipeline exists.
- [x] AI panel exists.
- [x] Read-only explain flows exist.

## Implementation Slices

### 12.1 AI Architecture

- [x] Define `AIProvider`.
- [x] Define `AIRequest`.
- [x] Define `AIResponse`.
- [x] Define `AIContextBundle`.
- [x] Define provider configuration model.
- [x] Add cancellation behavior.
- [x] Keep AI separate from Kubernetes mutation services.
- [x] Store API keys and custom provider headers in Keychain.
- [x] Discover models from provider APIs before model selection is enabled.

Checkpoint: provider settings now support OpenAI-compatible and Anthropic-compatible key auth with model discovery. Stop before sending Kubernetes context to any provider.

### 12.2 Context Builder

- [x] Build context for selected resource.
- [x] Include relevant events.
- [x] Include relevant conditions.
- [ ] Include selected log snippets.
- [ ] Include related resource summaries.
- [x] Include cluster context and namespace.
- [ ] Enforce size limits.

### 12.3 Redaction And Policy

- [x] Redact Secret data.
- [x] Redact tokens.
- [ ] Redact likely passwords/API keys in env vars.
- [x] Redact kubeconfig-style credentials through the shared diagnostics redactor.
- [x] Show context preview before external resource explain requests.
- [x] Keep provider calls user-initiated.
- [x] Add tests for redaction.

### 12.4 AI UI

- [x] Add AI side panel.
- [x] Explain selected resource.
- [ ] Summarize warning events.
- [ ] Explain pod readiness failure.
- [ ] Summarize selected logs.
- [ ] Generate kubectl command suggestions.
- [ ] Draft YAML changes without applying them.

### 12.5 Guardrails

- [x] AI cannot mutate the cluster directly.
- [x] AI command/YAML suggestions are copy or preview only.
- [x] Every AI answer is prompted to name the context it used.
- [x] Empty/missing configuration is handled honestly.

## Acceptance Criteria

- [x] User can ask AI to explain a selected demo resource.
- [ ] User can summarize demo logs.
- [x] Sensitive values are redacted before provider calls.
- [x] AI-generated actions are never executed automatically.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
