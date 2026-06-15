import SwiftUI

struct ResourceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: $appModel.selectedResource) {
            ForEach(ResourceNavigationSection.allCases) { section in
                Section(section.title) {
                    ForEach(ResourceNavigationItem.items(in: section)) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item as ResourceNavigationItem?)
                            .accessibilityIdentifier("resource.nav.\(item.id)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Resources")
        .background(.bar)
    }
}
