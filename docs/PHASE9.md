# Phase 9: Workload Debugging Basics

Status: Started.

Goal: add practical debugging workflows: describe-style views, container details, port-forwarding, and basic exec.

## Current Progress

- [x] Phase plan exists.
- [x] Initial describe-style debug summary exists.
- [x] Container details exist for Pod detail manifests.
- [x] Basic `kubectl`-backed port-forwarding exists for Pods, Services, and Deployments.
- [x] Basic external-terminal Pod exec support exists.
- [x] Active port-forward sessions can be stopped safely.
- [x] Active port-forward sessions are stopped when the app terminates.
- [x] Port-forward starts detect local port conflicts before launching `kubectl`.
- [x] Pod exec actions have a shell picker for common shells.
- [x] External exec launches are visible in lightweight in-app history.

## Implementation Slices

### 9.1 Describe-Style Views

- [x] Pod/workload problem summary.
- [x] Quick actions from debug summary to Events, Logs, Containers, Env, and YAML.
- [x] Event-aware debug summary with warning and empty-event context.
- [x] Pod scheduling summary.
- [x] Container state summary for Pod detail manifests.
- [x] Restart/termination reason details for Pod detail manifests.
- [x] Image pull status from container waiting reasons.
- [x] Environment variables with secret-aware redaction.
- [x] Volume mounts.
- [x] Probes.
- [x] QoS class summary.
- [x] Resource requests/limits.
- [x] Scheduling and resource request debug signals.

### 9.2 Port Forward

- [x] Decide native WebSocket/SPDY strategy or isolated `kubectl` adapter.
- [x] Use isolated `kubectl` adapter for the first slice.
- [x] Add `PortForwardSession` model.
- [x] Add deterministic local port defaults.
- [x] Detect local port conflicts.
- [x] Start session.
- [x] Stop session.
- [x] Show active sessions.
- [x] Cleanup on context switch/disconnect.
- [x] Cleanup on app quit.

Checkpoint: keep `kubectl` isolated behind a service protocol. Native API streaming can replace the adapter later without changing the app model/UI flow.

### 9.3 Exec

- [x] Decide native WebSocket/SPDY strategy or isolated `kubectl` adapter.
- [x] Use isolated `kubectl exec` external-terminal adapter for the first slice.
- [x] Select pod from Pods table context menu.
- [x] Select container from Pod Containers detail tab.
- [x] Select default shell command.
- [x] Add terminal app preference.
- [x] Add command/shell picker.
- [x] Track external exec launches as lightweight history.
- [ ] Cleanup on app quit/context switch if future native sessions are added.

### 9.4 Debugging UX

- [x] Add actions from pod/workload detail.
- [x] Keep cluster/namespace/resource visible in port-forward session UI.
- [x] Add clear active port-forward stop controls.
- [x] Add Pod context menu action for exec.
- [x] Add per-container exec actions outside the Overview tab.
- [x] Add failure explanations for RBAC/unsupported protocol.

### 9.5 Tests

- [x] Unit tests for workload debug summary signals.
- [x] Unit tests for port-forward session lifecycle.
- [x] Unit tests for external-terminal exec command construction.
- [x] Unit tests for external-terminal exec preference wiring.
- [ ] Manual QA for port-forwarding demo service.
- [ ] Manual QA for exec into demo pod.
- [ ] Shutdown cleanup QA.

## Acceptance Criteria

- [x] User can understand common unhealthy Pod/workload signals and related warning Events from one detail screen.
- [x] User can port-forward a service, deployment, or pod with declared ports.
- [x] User can open a basic Pod exec shell in an external Terminal window.
- [x] Active port-forward sessions are visible from the toolbar and detail overview.
- [x] External exec launches have a visible in-app history or native sessions never become hidden/orphaned.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl -n vibekube-demo port-forward svc/echo-web 18080:80
kubectl -n vibekube-demo exec deploy/echo-web -- sh -c 'hostname'
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
