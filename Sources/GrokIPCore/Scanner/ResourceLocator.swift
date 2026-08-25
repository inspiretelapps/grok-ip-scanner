import Foundation

public enum ResourceLocator {
    public static func url(name: String, ext: String? = nil, subdirectory: String? = nil) -> URL? {
        let filename = ext.map { "\(name).\($0)" } ?? name
        var candidates: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("Sources/GrokIPCore/Resources/\(filename)"))
        candidates.append(cwd.appendingPathComponent("Sources/GrokIP/Resources/\(filename)"))
        if let subdirectory {
            candidates.append(cwd.appendingPathComponent("Sources/GrokIP/Resources/\(subdirectory)/\(filename)"))
            candidates.append(cwd.appendingPathComponent("Sources/GrokIPCore/Resources/\(subdirectory)/\(filename)"))
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            candidates.append(url)
        }
        if let root = Bundle.main.resourceURL {
            if let subdirectory {
                candidates.append(root.appendingPathComponent(subdirectory).appendingPathComponent(filename))
            }
            candidates.append(root.appendingPathComponent(filename))
            candidates.append(root.appendingPathComponent("Resources").appendingPathComponent(filename))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(filename))
        if let subdirectory {
            candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(subdirectory)/\(filename)"))
        }

        candidates.append(cwd.appendingPathComponent(filename))

        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        candidates.append(exe.appendingPathComponent(filename))
        candidates.append(exe.appendingPathComponent("../Resources/\(filename)").standardizedFileURL)
        if let subdirectory {
            candidates.append(exe.appendingPathComponent("../Resources/\(subdirectory)/\(filename)").standardizedFileURL)
        }

        return candidates.first { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        }
    }
}
