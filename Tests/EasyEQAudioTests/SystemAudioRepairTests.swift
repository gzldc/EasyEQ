import Testing
@testable import EasyEQAudio

@Suite("SystemAudioRepair")
struct SystemAudioRepairTests {
    @Test func repairExitStatusClassification() {
        #expect(SystemAudioRepair.classify(exitCode: 0, standardError: "") == .restarted)
        #expect(SystemAudioRepair.classify(exitCode: 1, standardError: "0:80: execution error: User canceled. (-128)\n") == .cancelled)
        #expect(SystemAudioRepair.classify(exitCode: 1, standardError: "execution error: User cancelled.") == .cancelled)
        #expect(SystemAudioRepair.classify(exitCode: 1, standardError: "execution error: The administrator user name or password was incorrect. (-60007)\n")
            == .failed("execution error: The administrator user name or password was incorrect. (-60007)"))
        #expect(SystemAudioRepair.classify(exitCode: 2, standardError: "") == .failed(""))
    }

    @Test func repairScriptIsFixed() {
        #expect(SystemAudioRepair.script == "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges")
    }
}
