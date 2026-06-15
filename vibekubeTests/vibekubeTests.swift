//
//  vibekubeTests.swift
//  vibekubeTests
//
//  Created by art on 27.05.2026.
//

import Testing
@testable import vibekube

struct vibekubeTests {

    @MainActor
    @Test func appModelSelectsFirstClusterByDefault() {
        let model = AppModel(clusters: ClusterSummary.preview)

        #expect(model.selectedClusterID == "kind-vibekube-dev")
        #expect(model.selectedResource == .dashboard)
    }

    @MainActor
    @Test func appModelConnectsAndDisconnectsSelectedCluster() {
        let model = AppModel(clusters: ClusterSummary.preview)

        model.connectSelectedCluster()
        #expect(model.selectedConnectionState == .connected)

        model.disconnectSelectedCluster()
        #expect(model.selectedConnectionState == .disconnected)
    }

    @Test func resourceNavigationGroupsWorkloads() {
        #expect(ResourceNavigationItem.pods.section == .workloads)
        #expect(ResourceNavigationItem.deployments.section == .workloads)
        #expect(ResourceNavigationItem.services.section == .network)
    }

}
