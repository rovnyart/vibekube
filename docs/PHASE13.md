# Phase 13: Advanced AI Operations

Status: Not started.

Goal: evolve AI from explanation into guided, user-approved Kubernetes troubleshooting and remediation workflows.

## Current Progress

- [x] Phase plan exists.
- [ ] Troubleshooting workflow model exists.
- [ ] Investigation plan generation exists.
- [ ] Remediation preview exists.
- [ ] Runbook library exists.
- [ ] User approval flow integrates with safe mutations.

## Implementation Slices

### 13.1 Troubleshooting Workflows

- [ ] CrashLoopBackOff.
- [ ] ImagePullBackOff.
- [ ] Pending pods.
- [ ] Failed jobs.
- [ ] Service has no endpoints.
- [ ] Ingress not routing.
- [ ] PVC pending.
- [ ] Node not ready.

### 13.2 Investigation Plans

- [ ] Generate step-by-step investigation plan.
- [ ] Gather required local context for each step.
- [ ] Mark completed investigation steps.
- [ ] Link steps to app routes.
- [ ] Let user rerun analysis after cluster state changes.

### 13.3 Remediation Drafts

- [ ] Suggest kubectl commands.
- [ ] Suggest YAML patches.
- [ ] Explain risk and blast radius.
- [ ] Preview diffs.
- [ ] Require user approval.
- [ ] Hand approved changes to Phase 10 mutation flow.

Checkpoint: stop before connecting AI suggestions to mutation execution paths.

### 13.4 Runbooks

- [ ] Add local runbook format.
- [ ] Add built-in runbooks for common demo failures.
- [ ] Allow exporting/importing runbooks.
- [ ] Allow AI to cite runbook steps.
- [ ] Keep runbooks local by default.

### 13.5 Evaluation

- [ ] Create demo failure scenarios.
- [ ] Test explanations against known causes.
- [ ] Test redaction under realistic incidents.
- [ ] Test refusal/uncertainty behavior.
- [ ] Track user-approved vs rejected suggestions locally if privacy policy allows.

## Acceptance Criteria

- [ ] AI can guide a user through common demo cluster failures.
- [ ] Suggested remediations are explainable and previewed.
- [ ] No AI-generated remediation executes without normal user confirmation.
- [ ] The user can inspect what context informed the recommendation.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
