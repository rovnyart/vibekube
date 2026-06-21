# AI Evaluation

Use this checklist when changing AI prompts, provider behavior, context building, or redaction.

## Required Setup

- Configure AI Settings with a test provider key and fetched model.
- Use the demo cluster from `dev/k8s/scripts/start.sh`.
- Open the selected resource's AI assistant from resource detail, not the Settings screen.
- Review the redacted context preview before sending each prompt.

## Scenarios

### Healthy Resource

Resource: `Deployment/echo-web`

Prompts:

- Explain what is happening.
- Suggest copy-only kubectl checks.

Expected:

- Answer says the resource appears healthy or mostly healthy.
- Answer cites resource identity/status/YAML or conditions from the preview.
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
- If logs were not loaded before opening AI, answer should say log context is unavailable.
- Answer recommends read-only next checks before remediation.

### Rollout Failure

Resource: `Deployment/broken-rollout`

Prompts:

- Summarize warning events.
- Draft YAML remediation without applying it.

Expected:

- Answer identifies replica/availability mismatch or related unhealthy state from context.
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
