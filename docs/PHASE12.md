# Phase 12: AI Foundations

Status: Complete.

Goal: add safe AI explain/summarize capabilities on top of local Kubernetes context without allowing hidden cluster mutations.

## Current Progress

- [x] Phase plan exists.
- [x] AI provider abstraction exists.
- [x] Keychain-backed provider secrets exist.
- [x] Provider model discovery/test settings UI exists.
- [x] Context builder exists.
- [x] Redaction pipeline exists.
- [x] AI panel exists.
- [x] Top-level AI status page exists.
- [x] Resizable AI assistant window exists.
- [x] AI answers render Markdown and highlighted code blocks.
- [x] OpenAI-compatible streaming chat transport exists.
- [x] Streaming AI responses can be stopped from the composer.
- [x] Read-only explain flows exist.
- [x] Resource-scoped AI gathers read-only cluster evidence before provider calls.
- [x] Pod logs and events are loaded on demand when the prompt needs runtime context.
- [x] Workload and Service AI prompts gather selector-matched Pod health, related Pod events, and bounded log attempts for unhealthy Pods.
- [x] The context preview switches to the exact enriched context sent to the provider after read-only gathering.
- [x] AI foundation evaluation checklist exists.

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
- [x] Add provider request tests for endpoint construction, auth headers, custom headers, chat payloads, and configuration gating.
- [x] Use `max_completion_tokens` for OpenAI-compatible chat requests and omit optional sampling parameters for newer OpenAI models.
- [x] Stream AI answer deltas from provider SSE responses.

Checkpoint: provider settings now support OpenAI-compatible and Anthropic-compatible key auth with model discovery. Stop before sending Kubernetes context to any provider.

### 12.2 Context Builder

- [x] Build context for selected resource.
- [x] Include relevant events.
- [x] Include relevant conditions.
- [x] Include selected log snippets.
- [x] Load Pod log snippets on demand for log/runtime prompts instead of requiring the Logs tab first.
- [x] Include related resource summaries.
- [x] Include selector-matched related Pod health for workloads and Services.
- [x] Include cluster context and namespace.
- [x] Enforce size limits.
- [x] Show read-only tool results in the assistant transcript before the provider answer.

### 12.3 Redaction And Policy

- [x] Redact Secret data.
- [x] Redact tokens.
- [x] Redact likely passwords/API keys in env vars.
- [x] Redact kubeconfig-style credentials through the shared diagnostics redactor.
- [x] Show context preview before external resource explain requests.
- [x] Keep provider calls user-initiated.
- [x] Add tests for redaction.

### 12.4 AI UI

- [x] Add AI side panel.
- [x] Explain selected resource.
- [x] Summarize warning events.
- [x] Explain pod readiness failure.
- [x] Summarize selected logs.
- [x] Generate kubectl command suggestions.
- [x] Draft YAML changes without applying them.
- [x] Add a top-level AI page showing provider readiness, selected model, Keychain status, and setup/test actions.
- [x] Keep stored API keys out of the input field while preserving the saved key when editing headers.
- [x] Show the saved selected model after relaunch even before refetching the model list.
- [x] Replace the attached sheet with a resizable standalone assistant window.
- [x] Replace raw context wall with section navigation and highlighted code surfaces.
- [x] Render AI answers as Markdown with code-block copy controls.
- [x] Show live streaming answer state with animated provider activity.
- [x] Let the user stop an in-flight model response.
- [x] Auto-follow streaming chat output until the user scrolls away, then show a Jump to bottom control.
- [x] Show the actual sent context after read-only gathering so the user can audit what the provider saw.

### 12.5 Guardrails

- [x] AI cannot mutate the cluster directly.
- [x] AI tool gathering is limited to Vibekube-owned read-only inspection paths.
- [x] AI command/YAML suggestions are copy or preview only.
- [x] Every AI answer is prompted to name the context it used.
- [x] Empty/missing configuration is handled honestly.

## Acceptance Criteria

- [x] User can ask AI to explain a selected demo resource.
- [x] User can summarize demo logs.
- [x] Sensitive values are redacted before provider calls.
- [x] AI-generated actions are never executed automatically.
- [x] User can stop a streaming provider response.
- [x] Chat auto-scroll does not fight the user after they scroll away from the bottom.
- [x] Provider-backed manual evaluation passes with a real test key/model.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
xcodebuild -scheme vibekube -configuration Debug -only-testing:vibekubeTests/AIProviderClientTests test
```

Manual provider/model evaluation: [`AI_EVALUATION.md`](AI_EVALUATION.md).
