import Foundation
import Testing
@testable import EasyEQCore

@Test func editsSnapClampAndDirty() {
    var s = EditingSession(selection: .builtIn(.flat), saved: .flat(.ten))
    s.setGain(0.2, at: 0); #expect(s.current.gains[0] == 0); #expect(!s.isDirty)
    s.setGain(20, at: 1);  #expect(s.current.gains[1] == 12); #expect(s.isDirty)
    s.resetBand(at: 1);    #expect(!s.isDirty)
    s.setGain(-3.04, at: 2); #expect(s.current.gains[2] == -3.0)
    s.revert(); #expect(s.current == .flat(.ten))
}

@Test func outOfRangeIndexIsNoOp() {
    var s = EditingSession(selection: .builtIn(.flat), saved: .flat(.ten))
    s.setGain(5, at: -1); s.setGain(5, at: 10); s.resetBand(at: 99); s.resetBand(at: -3)
    #expect(s.current == .flat(.ten))
    #expect(!s.isDirty)
}

@Test func negativeSnapAndBoundaryValues() {
    var s = EditingSession(selection: .builtIn(.flat), saved: .flat(.ten))
    s.setGain(-0.2, at: 0); #expect(s.current.gains[0] == 0)
    #expect(s.current.gains[0].sign == .plus)
    s.setGain(0.3, at: 1); #expect(s.current.gains[1] == 0.3)
    s.setGain(-30, at: 2); #expect(s.current.gains[2] == -12)
}

@Test func layoutSwitchIsAnUnsavedChange() {
    var s = EditingSession(selection: .user(UUID()), saved: BuiltInPreset.voice.settings(for: .ten))
    s.switchLayout(to: .thirtyOne)
    #expect(s.isDirty && s.current.layout == .thirtyOne)
    s.revert(); #expect(s.current.layout == .ten)
}

@Test func markSavedClearsDirtyAndSetsSelection() {
    var s = EditingSession(selection: .builtIn(.voice), saved: BuiltInPreset.voice.settings(for: .ten))
    s.setGain(4, at: 3)
    let id = UUID()
    s.markSaved(as: .user(id))
    #expect(!s.isDirty)
    #expect(s.selection == .user(id))
    #expect(s.saved.gains[3] == 4)
}

@Test func builtInsCannotBeSavedInPlace() {
    #expect(!EditingSession(selection: .builtIn(.voice), saved: .flat(.ten)).canSaveInPlace)
    #expect(EditingSession(selection: .user(UUID()), saved: .flat(.ten)).canSaveInPlace)
}

@Test func namesAndDeletion() {
    #expect(EditingSession.uniqueName("  ", existing: []) == nil)
    #expect(EditingSession.uniqueName("直播", existing: ["直播"]) == "直播 2")
    #expect(EditingSession.uniqueName("直播", existing: ["直播", "直播 2"]) == "直播 3")
    let id = UUID()
    #expect(EditingSession.selectionAfterDeleting(id, current: .user(id)) == .builtIn(.voice))
}

@Test func uniqueNameTrimsAndKeepsFreeNames() {
    #expect(EditingSession.uniqueName("  直播 \n", existing: []) == "直播")
    #expect(EditingSession.uniqueName(" 直播 ", existing: ["直播"]) == "直播 2")
    #expect(EditingSession.uniqueName("新", existing: ["旧"]) == "新")
}

@Test func deletingAnotherPresetKeepsSelection() {
    let other = UUID()
    #expect(EditingSession.selectionAfterDeleting(UUID(), current: .user(other)) == .user(other))
    #expect(EditingSession.selectionAfterDeleting(UUID(), current: .builtIn(.flat)) == .builtIn(.flat))
}

@Test func replaceCurrentMakesDirtyAndRevertRestores() {
    var session = EditingSession(selection: .builtIn(.flat), saved: .flat(.ten))
    var spiky = EQSettings.flat(.ten)
    spiky.gains[4] = 12
    session.replaceCurrent(with: spiky.smoothed())
    #expect(session.current.gains[4] == 6)
    #expect(session.isDirty)
    session.revert()
    #expect(!session.isDirty)
    session.replaceCurrent(with: .flat(.fifteen))            // wrong layout: ignored
    #expect(session.current.layout == .ten)
}
