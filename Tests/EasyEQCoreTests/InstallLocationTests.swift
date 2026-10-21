import Foundation
import Testing
@testable import EasyEQCore

@Test func applicationsFoldersCountAsInstalled() {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    func installed(_ path: String) -> Bool {
        InstallLocation.isInApplicationsFolder(URL(fileURLWithPath: path, isDirectory: true), homeDirectory: home)
    }
    #expect(installed("/Applications/EasyEQ.app"))
    #expect(installed("/Applications/Utilities/EasyEQ.app"))
    #expect(installed("/Users/someone/Applications/EasyEQ.app"))
    #expect(!installed("/Volumes/EasyEQ/EasyEQ.app"))
    #expect(!installed("/Users/someone/Downloads/EasyEQ.app"))
    #expect(!installed("/Applications"))
    #expect(!installed("/ApplicationsX/EasyEQ.app"))
    #expect(!installed("/private/var/folders/xx/AppTranslocation/ABC/d/EasyEQ.app"))
    #expect(!installed("/Users/someone/Desktop/Applications-old/EasyEQ.app"))
}
