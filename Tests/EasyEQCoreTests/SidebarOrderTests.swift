import Testing
@testable import EasyEQCore

struct SidebarOrderTests {
    // a b | c d (hidden) | e f
    let full = ["a", "b", "c", "d", "e", "f"]
    let visible = ["a", "b", "e", "f"]

    @Test func visibleSelectionStepsAndClamps() {
        #expect(SidebarOrder.nextVisible(from: "b", delta: 1, fullOrder: full, visible: visible) == "e")
        #expect(SidebarOrder.nextVisible(from: "e", delta: -1, fullOrder: full, visible: visible) == "b")
        #expect(SidebarOrder.nextVisible(from: "a", delta: -1, fullOrder: full, visible: visible) == "a")
        #expect(SidebarOrder.nextVisible(from: "f", delta: 1, fullOrder: full, visible: visible) == "f")
    }

    @Test func hiddenSelectionMovesToNearestVisibleNeighbour() {
        #expect(SidebarOrder.nextVisible(from: "c", delta: 1, fullOrder: full, visible: visible) == "e")
        #expect(SidebarOrder.nextVisible(from: "d", delta: 1, fullOrder: full, visible: visible) == "e")
        #expect(SidebarOrder.nextVisible(from: "c", delta: -1, fullOrder: full, visible: visible) == "b")
        #expect(SidebarOrder.nextVisible(from: "d", delta: -1, fullOrder: full, visible: visible) == "b")
    }

    @Test func hiddenSelectionWithNothingVisibleBeyondClamps() {
        // Hidden tail: e f hidden.
        #expect(SidebarOrder.nextVisible(from: "e", delta: 1, fullOrder: full, visible: ["a", "b", "c", "d"]) == "d")
        // Hidden head: a b hidden.
        #expect(SidebarOrder.nextVisible(from: "b", delta: -1, fullOrder: full, visible: ["c", "d", "e", "f"]) == "c")
    }

    @Test func nothingToSelect() {
        #expect(SidebarOrder.nextVisible(from: "a", delta: 1, fullOrder: full, visible: []) == nil)
        #expect(SidebarOrder.nextVisible(from: "zzz", delta: 1, fullOrder: full, visible: visible) == nil)
    }
}
