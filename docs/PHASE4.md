# Phase 4: Dashboard And Cluster Stats

Status: Not started.

Goal: show a useful operational overview for the selected cluster.

## Current Progress

- [x] Phase plan exists.
- [ ] Dashboard data model exists.
- [ ] Node/pod/workload summaries load.
- [ ] Recent warning events load.
- [ ] Metrics API availability is detected.
- [ ] Dashboard UI handles loading, empty, healthy, warning, and error states.

## Implementation Slices

### 4.1 Summary Models

- [ ] Define `ClusterDashboardSnapshot`.
- [ ] Define `NodeHealthSummary`.
- [ ] Define `PodHealthSummary`.
- [ ] Define `WorkloadHealthSummary`.
- [ ] Define `EventSummary`.
- [ ] Define `MetricsAvailability`.

### 4.2 Data Loading

- [ ] Load Kubernetes version.
- [ ] Load nodes and readiness.
- [ ] Load namespaces.
- [ ] Load pods across selected namespace scope.
- [ ] Load deployments, statefulsets, daemonsets, jobs, and cronjobs.
- [ ] Load recent events.
- [ ] Load PV/PVC summary.
- [ ] Try metrics API and gracefully degrade.

### 4.3 Health Computation

- [ ] Compute node readiness.
- [ ] Compute pod phase counts.
- [ ] Compute restart warning counts.
- [ ] Compute workload desired/current/ready state.
- [ ] Identify warning events.
- [ ] Add status taxonomy: healthy, progressing, warning, failed, unknown.

### 4.4 Dashboard UI

- [ ] Cluster identity header.
- [ ] Health summary strip.
- [ ] Node card/table.
- [ ] Workload summary.
- [ ] Pod health summary.
- [ ] Recent warnings list.
- [ ] Storage summary.
- [ ] Metrics unavailable state.
- [ ] Last updated indicator.

Checkpoint: stop for visual review once demo cluster dashboard renders real data.

### 4.5 Tests

- [ ] Health computation unit tests.
- [ ] Dashboard view model tests.
- [ ] UI test for demo cluster dashboard if integration setup is available.

## Acceptance Criteria

- [ ] Demo cluster dashboard shows version, nodes, pods, workloads, and warning events.
- [ ] Dashboard links into related resources where routes exist.
- [ ] Missing metrics does not look like a failure.
- [ ] Refresh updates dashboard data.

## Validation Commands

```sh
dev/k8s/scripts/start.sh
kubectl get nodes
kubectl get pods -A
kubectl get events -A
xcodebuild -project vibekube.xcodeproj -scheme vibekube -destination 'platform=macOS' test
```
