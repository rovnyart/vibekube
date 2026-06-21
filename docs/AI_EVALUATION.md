# AI Evaluation

Use this checklist when changing AI prompts, provider behavior, context building, or redaction.

## Required Setup

- Configure AI Settings with a test provider key and fetched model.
- For OpenAI-compatible providers, chat requests should use `max_completion_tokens` and should not send legacy `max_tokens`.
- Use the demo cluster from `dev/k8s/scripts/start.sh`.
- Open the selected resource's AI assistant from resource detail, not the Settings screen.
- The assistant should open as a standalone resizable window, not a fixed attached sheet.
- The top-level AI page should show provider readiness, selected model, and Keychain status without exposing the API key.
- Review the redacted context preview before sending each prompt.
- When asking about Pod logs, confirm the assistant shows a Vibekube tools card and fetches logs without requiring the Logs tab to be opened first.
- When asking about a workload or Service with a selector, confirm the assistant gathers matching Pods server-side, inspects related Pod events, and attempts bounded related Pod logs when the prompt asks about logs/runtime behavior, even for currently healthy matching Pods.
- Confirm the tools card lists only read-only inspection work and any read failures; it must not mutate the cluster.
- Confirm streamed answers appear incrementally and render Markdown headings, lists, emphasis, and code blocks cleanly.
- Confirm code blocks have syntax highlighting and a copy control.
- While an answer is streaming, confirm the composer button becomes Stop and stops the provider response without freezing the assistant.
- Confirm the composer is multiline: Return inserts a newline, Command+Return sends, and the Send button stays aligned with the input.
- Confirm chat output auto-scrolls while untouched; after manually scrolling upward, auto-scroll should pause and a Jump to bottom control should appear.
- Confirm Jump to bottom returns the transcript to the latest output and hides the control.
- Confirm Clear Chat removes the current transcript/context cards without changing provider settings or Keychain secrets.

## Scenarios

### Healthy Resource

Resource: `Deployment/echo-web`

Prompts:

- Explain what is happening.
- Suggest copy-only kubectl checks.

Expected:

- Answer says the resource appears healthy or mostly healthy.
- Answer cites resource identity/status/YAML or conditions from the preview.
- If asked about Pod logs from the Deployment, the tools card says Vibekube read matching Pods for the selector and read current logs from the matching Pod container before the provider answer.
- If Kubernetes returns no current log lines, answer names the specific matching Pod/container where logs were empty.
- No destructive action is presented as something Vibekube performed.

### Image Pull Failure

Resource: `Pod/broken-node-pulse-*` or another demo ImagePullBackOff pod.

Prompts:

- Explain what is happening.
- Find likely root causes.
- Suggest copy-only kubectl checks.

Expected:

- Answer calls out image pull failure, image name/tag, registry/auth possibilities, and events if present.
- Suggested commands are copy-only inspection commands.
- No Secret values or credentials appear.

### Crash Loop

Resource: `Pod/crashloop-previous-logs`

Prompts:

- Explain pod readiness failure.
- Summarize selected logs after loading current or previous logs in the Logs tab.

Expected:

- Answer distinguishes current state, restarts, container status, and loaded log snippets.
- If logs were not loaded before opening AI, Vibekube should fetch relevant current logs and previous logs for restarted/crashing containers before the provider answer.
- Answer recommends read-only next checks before remediation.

### Rollout Failure

Resource: `Deployment/broken-rollout`

Prompts:

- Summarize warning events.
- Why is this Deployment unavailable? Check matching Pods, warning events, and logs if they exist.
- Draft YAML remediation without applying it.

Expected:

- The tools card says Vibekube read matching Pods for the selector and names any unhealthy related Pod inspected.
- The sent context panel shows a `Related Pod Health` section with related Pod status, container state, related Pod events, and any log read failure/success.
- If the prompt explicitly asks for logs, the tools card should include bounded related Pod log reads even if the matching Pods are healthy.
- Answer identifies the related ImagePullBackOff or other Pod-level blocker, not only the Deployment replica/availability mismatch.
- Draft YAML is clearly a draft and is not applied by Vibekube.
- User is directed to review through the normal YAML preview/apply flow if they choose to act.

### Secret Redaction

Resource: any `Secret`, or a Pod with Secret-backed env vars.

Prompts:

- Explain what this resource does.

Expected:

- Redacted context preview shows Secret `data`, `stringData`, and `binaryData` values as `<redacted>`.
- API tokens, bearer tokens, passwords, private keys, certificates, and Secret-backed env values do not appear in the prompt or answer.

## Failure Checks

- Empty AI configuration shows the Settings call to action instead of a chat composer.
- Provider/model failure surfaces an error in the assistant without changing the cluster.
- Oversized YAML/log context is truncated with `<truncated by Vibekube before AI request>`.
- AI responses never trigger mutation services directly.
- AI read-only gathering never calls mutation services and never executes suggested kubectl commands.
- OpenAI-compatible chat requests should stream over provider SSE responses, use `max_completion_tokens`, and never send legacy `max_tokens`.
