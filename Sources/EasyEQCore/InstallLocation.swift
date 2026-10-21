import Foundation

/// Where the running app bundle lives. A login item registered from a mounted DMG, Downloads or a translocated
/// path would point at something that disappears, so Launch at Login is offered only from an Applications folder.
public enum InstallLocation {
    /// True when `bundleURL` is inside `/Applications` or `<home>/Applications` (symlinks resolved, subfolders allowed).
    public static func isInApplicationsFolder(
        _ bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        return roots.contains { path.hasPrefix($0 + "/") }
    }
}
