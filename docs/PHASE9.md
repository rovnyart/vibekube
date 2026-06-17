# Phase 9: Workload Debugging Basics

Status: Started.

Goal: add practical debugging workflows: describe-style views, container details, port-forwarding, and basic exec.

## Current Progress

- [x] Phase plan exists.
- [x] Initial describe-style debug summary exists.
- [x] Container details exist for Pod detail manifests.
- [ ] Port-forwarding exists.
- [ ] Exec session support exists.
- [ ] Active sessions can be stopped safely.

## Implementation Slices

### 9.1 Describe-Style Views

- [x] Pod/workload problem summary.
- [x] Quick actions from debug summary to Events, Logs, Containers, Env, and YAML.
- [x] Event-aware debug summary with warning and empty-event context.
- [x] Pod scheduling summary.
- [x] Container state summary for Pod detail manifests.
- [x] Restart/termination reason details for Pod detail manifests.
- [x] Image pull status from container waiting reasons.
- [x] Selector-backed workload Pod rollups.
- [x] Environment variables with secret-aware redaction.
- [x] Volume mounts.
- [x] Probes.
- [x] QoS class summary.
- [x] Resource requests/limits.
- [x] Scheduling and resource request debug signals.

### 9.2 Port Forward

- [ ] Decide native WebSocket/SPDY strategy or isolated `kubectl` adapter.
- [ ] Add `PortForwardSession` model.
- [ ] Add local port selection.
- [ ] Detect local port conflicts.
- [ ] Start session.
- [ ] Stop session.
- [ ] Show active sessions.
- [ ] Cleanup on app quit/context switch.

Checkpoint: stop before choosing `kubectl` fallback vs native implementation if the tradeoff is significant.

### 9.3 Exec

- [ ] Decide native WebSocket/SPDY strategy or isolated `kubectl` adapter.
- [ ] Add `ExecSession` model.
- [ ] Select pod/container.
- [ ] Select command/shell.
- [ ] Add terminal-like UI.
- [ ] Stop session.
- [ ] Cleanup on app quit/context switch.

### 9.4 Debugging UX

- [x] Add actions from pod/workload detail.
- [ ] Keep cluster/namespace/pod/container visible in session UI.
- [ ] Add clear active-session stop controls.
- [ ] Add failure explanations for RBAC/unsupported protocol.

### 9.5 Tests

- [x] Unit tests for workload debug summary signals.
- [ ] Unit tests for session lifecycle.
- [ ] Manual QA for port-forwarding demo service.
- [ ] Manual QA for exec into demo pod.
- [ ] Shutdown cleanup QA.

## Acceptance Criteria

- [x] User can understand common unhealthy Pod/workload signals and related warning Events from one detail screen.
- [ ] User can port-forward a demo service or pod.
- [ ] User can start and stop a basic exec session.
- [ ] Active sessions never become hidden or orphaned.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo port-forward svc/echo-web 18080:80
kubectl -n vibekube-demo exec deploy/echo-web -- sh -c 'hostname'
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
