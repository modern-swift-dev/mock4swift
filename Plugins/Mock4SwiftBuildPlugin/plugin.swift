import Foundation
import PackagePlugin

private enum SourceRegion {
    case code
    case lineComment
    case blockComment(depth: Int)
    case string(hashes: Int, multiline: Bool)
}

@main struct Mock4SwiftBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let currentModule = target.sourceModule else {
            return []
        }

        let localTargetIDs = Set(context.package.targets.map(\.id))
        let sourceDependencies = target.recursiveTargetDependencies
            .compactMap(\.sourceModule)
        var seenModules = Set<String>()
        let localModules = ([currentModule] + sourceDependencies.filter { localTargetIDs.contains($0.id) })
            .filter { seenModules.insert($0.id).inserted }
        let externalModules = sourceDependencies
            .filter { !localTargetIDs.contains($0.id) }
            .sorted { ($0.moduleName, $0.id) < ($1.moduleName, $1.id) }
        let localModulesByName = Dictionary(grouping: localModules, by: \.moduleName)
        let externalModulesByName = Dictionary(grouping: externalModules, by: \.moduleName)

        var selectedModules = Dictionary(uniqueKeysWithValues: localModules.map { ($0.id, $0) })
        var scannedModules = Set<String>()
        var modulesToScan = [currentModule]
        while let module = modulesToScan.popLast() {
            guard scannedModules.insert(module.id).inserted else {
                continue
            }
            for importedModule in try importedModuleNames(in: swiftSourceFiles(for: module)).sorted() {
                modulesToScan += localModulesByName[importedModule] ?? []
                guard let candidates = externalModulesByName[importedModule] else {
                    continue
                }
                for candidate in candidates where selectedModules[candidate.id] == nil {
                    selectedModules[candidate.id] = candidate
                    modulesToScan.append(candidate)
                }
            }
        }
        let modules = selectedModules.values.sorted { ($0.moduleName, $0.id) < ($1.moduleName, $1.id) }

        let output = context.pluginWorkDirectoryURL.appending(component: "Mock4Swift.generated.swift")
        var arguments = ["--output", output.path, "--target-module", currentModule.moduleName]
        var inputFiles = [URL]()
        var seenFiles = Set<URL>()

        for module in modules {
            let files = swiftSourceFiles(for: module)
                .filter { seenFiles.insert($0).inserted }
            guard !files.isEmpty else {
                continue
            }
            arguments += ["--module", module.moduleName]
            arguments += files.map(\.path)
            inputFiles += files
        }

        guard !inputFiles.isEmpty else {
            return []
        }
        return [.buildCommand(
            displayName: "Generating Mock4Swift mocks for \(target.name)",
            executable: try context.tool(named: "Mock4SwiftGenerator").url,
            arguments: arguments,
            inputFiles: inputFiles,
            outputFiles: [output]
        )]
    }

    private func swiftSourceFiles(for module: SourceModuleTarget) -> [URL] {
        module.sourceFiles
            .filter { $0.type == .source && $0.url.pathExtension == "swift" }
            .map(\.url)
            .sorted { $0.path < $1.path }
    }

    private func importedModuleNames(in files: [URL]) throws -> Set<String> {
        let expression = try NSRegularExpression(
            pattern: #"(?m)^\s*(?:(?:@[A-Za-z_][A-Za-z0-9_]*)(?:\([^)\r\n]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private|open)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
        )

        return try files.reduce(into: Set<String>()) { modules, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            let sourceCode = sourceCodeOnly(source)
            let range = NSRange(sourceCode.startIndex..., in: sourceCode)
            for match in expression.matches(in: sourceCode, range: range) {
                guard let moduleRange = Range(match.range(at: 1), in: sourceCode) else {
                    continue
                }
                modules.insert(String(sourceCode[moduleRange]))
            }
        }
    }

    private func sourceCodeOnly(_ source: String) -> String {
        let bytes = Array(source.utf8)
        var result = bytes
        var region = SourceRegion.code
        var index = 0

        func matches(_ pattern: [UInt8], at index: Int) -> Bool {
            index + pattern.count <= bytes.count
                && bytes[index ..< index + pattern.count].elementsEqual(pattern)
        }

        func mask(_ range: Range<Int>) {
            for offset in range where result[offset] != 10 && result[offset] != 13 {
                result[offset] = 32
            }
        }

        while index < bytes.count {
            switch region {
                case .code:
                    if matches([47, 47], at: index) {
                        mask(index ..< index + 2)
                        index += 2
                        region = .lineComment
                    } else if matches([47, 42], at: index) {
                        mask(index ..< index + 2)
                        index += 2
                        region = .blockComment(depth: 1)
                    } else {
                        var quoteIndex = index
                        while quoteIndex < bytes.count, bytes[quoteIndex] == 35 {
                            quoteIndex += 1
                        }
                        guard quoteIndex < bytes.count, bytes[quoteIndex] == 34 else {
                            index += 1
                            continue
                        }
                        let hashes = quoteIndex - index
                        let multiline = matches([34, 34, 34], at: quoteIndex)
                        let openingLength = hashes + (multiline ? 3 : 1)
                        mask(index ..< index + openingLength)
                        index += openingLength
                        region = .string(hashes: hashes, multiline: multiline)
                    }

                case .lineComment:
                    if bytes[index] == 10 || bytes[index] == 13 {
                        index += 1
                        region = .code
                    } else {
                        result[index] = 32
                        index += 1
                    }

                case let .blockComment(depth):
                    if matches([47, 42], at: index) {
                        mask(index ..< index + 2)
                        index += 2
                        region = .blockComment(depth: depth + 1)
                    } else if matches([42, 47], at: index) {
                        mask(index ..< index + 2)
                        index += 2
                        region = depth == 1 ? .code : .blockComment(depth: depth - 1)
                    } else {
                        mask(index ..< index + 1)
                        index += 1
                    }

                case let .string(hashes, multiline):
                    let quotes = multiline ? [UInt8](repeating: 34, count: 3) : [34]
                    let closing = quotes + [UInt8](repeating: 35, count: hashes)
                    if matches(closing, at: index) {
                        mask(index ..< index + closing.count)
                        index += closing.count
                        region = .code
                    } else if hashes == 0, bytes[index] == 92, index + 1 < bytes.count {
                        mask(index ..< index + 2)
                        index += 2
                    } else {
                        mask(index ..< index + 1)
                        index += 1
                    }
            }
        }

        return String(decoding: result, as: UTF8.self)
    }
}
