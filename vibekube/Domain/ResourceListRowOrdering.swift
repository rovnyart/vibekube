import Foundation

enum ResourceListRowOrdering {
    static func orderedRows(
        _ rows: [KubernetesUnstructuredResource],
        sortOrder: [KeyPathComparator<KubernetesUnstructuredResource>],
        preservedOrderIDs: [KubernetesUnstructuredResource.ID],
        preserveExistingOrder: Bool
    ) -> [KubernetesUnstructuredResource] {
        let naturallySortedRows = stableSortedRows(rows, sortOrder: sortOrder)
        guard preserveExistingOrder, !preservedOrderIDs.isEmpty else {
            return naturallySortedRows
        }

        var rowsByID: [KubernetesUnstructuredResource.ID: KubernetesUnstructuredResource] = [:]
        for row in naturallySortedRows {
            rowsByID[row.id] = row
        }

        var orderedRows: [KubernetesUnstructuredResource] = []
        var includedIDs = Set<KubernetesUnstructuredResource.ID>()

        for id in preservedOrderIDs {
            guard let row = rowsByID[id] else {
                continue
            }

            orderedRows.append(row)
            includedIDs.insert(id)
        }

        orderedRows.append(contentsOf: naturallySortedRows.filter { !includedIDs.contains($0.id) })
        return orderedRows
    }

    private static func stableSortedRows(
        _ rows: [KubernetesUnstructuredResource],
        sortOrder: [KeyPathComparator<KubernetesUnstructuredResource>]
    ) -> [KubernetesUnstructuredResource] {
        rows.enumerated()
            .sorted { lhs, rhs in
                for comparator in sortOrder {
                    switch comparator.compare(lhs.element, rhs.element) {
                    case .orderedAscending:
                        return true
                    case .orderedDescending:
                        return false
                    case .orderedSame:
                        continue
                    }
                }

                let lhsKey = fallbackSortKey(for: lhs.element)
                let rhsKey = fallbackSortKey(for: rhs.element)
                if lhsKey != rhsKey {
                    return lhsKey.localizedStandardCompare(rhsKey) == .orderedAscending
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func fallbackSortKey(for row: KubernetesUnstructuredResource) -> String {
        [
            row.displayNamespace,
            row.displayKind,
            row.displayName,
            row.id
        ]
        .joined(separator: "/")
    }
}
