# Phase 9: Workload Debugging Basics

Status: Not started.

Goal: add practical debugging workflows: describe-style views, container details, port-forwarding, and basic exec.

## Current Progress

- [x] Phase plan exists.
- [ ] Describe-style view exists.
- [ ] Container details exist.
- [ ] Port-forwarding exists.
- [ ] Exec session support exists.
- [ ] Active sessions can be stopped safely.

## Implementation Slices

### 9.1 Describe-Style Views

- [ ] Pod scheduling summary.
- [ ] Container state summary.
- [ ] Restart/termination reason details.
- [ ] Image pull status.
- [ ] Environment variables with secret-aware redaction.
- [ ] Volume mounts.
- [ ] Probes.
- [ ] QoS and resource requests/limits.

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

- [ ] Add actions from pod/workload detail.
- [ ] Keep cluster/namespace/pod/container visible in session UI.
- [ ] Add clear active-session stop controls.
- [ ] Add failure explanations for RBAC/unsupported protocol.

### 9.5 Tests

- [ ] Unit tests for session lifecycle.
- [ ] Manual QA for port-forwarding demo service.
- [ ] Manual QA for exec into demo pod.
- [ ] Shutdown cleanup QA.

## Acceptance Criteria

- [ ] User can understand why a pod is unhealthy from one detail screen.
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
