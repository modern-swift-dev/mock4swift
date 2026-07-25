import Foundation
import PackagePlugin

@main
struct Mock4SwiftBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let currentModule = target.sourceModule else { return [] }

        let localTargetIDs = Set(context.package.targets.map(\.id))
        let dependencies = target.recursiveTargetDependencies
            .compactMap(\.sourceModule)
            .filter { localTargetIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        var seenModules = Set<String>()
        let modules = ([currentModule] + dependencies).filter { seenModules.insert($0.id).inserted }

        let output = context.pluginWorkDirectoryURL.appending(component: "Mock4Swift.generated.swift")
        var arguments = ["--output", output.path, "--target-module", currentModule.moduleName]
        var inputFiles = [URL]()
        var seenFiles = Set<URL>()

        for module in modules {
            let files = module.sourceFiles
                .filter { $0.type == .source && $0.url.pathExtension == "swift" }
                .map(\.url)
                .filter { seenFiles.insert($0).inserted }
            guard !files.isEmpty else { continue }
            arguments += ["--module", module.moduleName]
            arguments += files.map(\.path)
            inputFiles += files
        }

        guard !inputFiles.isEmpty else { return [] }
        return [.buildCommand(
            displayName: "Generating Mock4Swift mocks for \(target.name)",
            executable: try context.tool(named: "Mock4SwiftGenerator").url,
            arguments: arguments,
            inputFiles: inputFiles,
            outputFiles: [output]
        )]
    }
}
