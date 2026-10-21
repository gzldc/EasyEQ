import Foundation

/// Pure arrow-key navigation over the sidebar's presets.
public enum SidebarOrder {
    /// The preset to select after pressing up (`delta < 0`) or down (`delta > 0`).
    ///
    /// `fullOrder` lists every preset in on-screen order ignoring collapsed sections; `visible` is the subset
    /// that is currently shown (same order). A visible selection moves one step and clamps at the ends. A hidden
    /// selection (its section is collapsed) moves to the nearest visible neighbour in that direction, or clamps
    /// to the last / first visible preset when there is none. Returns `nil` when there is nothing to move to.
    public static func nextVisible<T: Hashable>(from current: T, delta: Int, fullOrder: [T], visible: [T]) -> T? {
        guard !visible.isEmpty, delta != 0 else { return nil }
        if let index = visible.firstIndex(of: current) {
            return visible[min(max(index + (delta > 0 ? 1 : -1), 0), visible.count - 1)]
        }
        guard let position = fullOrder.firstIndex(of: current) else { return nil }
        let visibleSet = Set(visible)
        if delta > 0 {
            return fullOrder[(position + 1)...].first(where: visibleSet.contains) ?? visible.last
        }
        return fullOrder[..<position].last(where: visibleSet.contains) ?? visible.first
    }
}
