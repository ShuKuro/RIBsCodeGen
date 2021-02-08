//
//  main.swift
//  RIBsCodeGen
//
//  Created by 今入　庸介 on 2021/02/03.
//

import Foundation
import PathKit
import Yams

let version = "0.1.0"

var setting: Setting!

func main() {
    let arguments = [String](CommandLine.arguments.dropFirst())

    guard let setting = analyzeSettings() else {
        print("")
        print("\n failure.".red.applyingStyle(.bold))
        exit(1)
    }
    RIBsCodeGen.setting = setting

    run(with: arguments)
}

// MARK: - Execute
func run(with commandLineArguments: [String]) {
    guard let argument = analyzeArguments(commandLineArguments: commandLineArguments) else {
        return showResult(.failure(error: .lackOfArguments))
    }

    switch argument.first {
    case "help":
        let result = HelpCommand().run()
        showResult(result)
        exit(0)
    case "version":
        let result = VersionCommand(version: version).run()
        showResult(result)
        exit(0)
    case "add" where !argument.hasParent:
        let result = makeCreateRIBCommand(argument: argument).run()
        showResult(result)
        exit(0)
    case "add" where argument.hasParent:
        let resultCreateRIB = makeCreateRIBCommand(argument: argument).run()
        showResult(resultCreateRIB)

        let resultCreateComponentExtension = makeCreateComponentExtension(argument: argument).run()
        showResult(resultCreateComponentExtension)

        let resultDependency = makeDependencyCommand(argument: argument).run()
        showResult(resultDependency)
        exit(0)
    case "link":
        let resultCreateComponentExtension = makeCreateComponentExtension(argument: argument).run()
        showResult(resultCreateComponentExtension)

        let resultDependency = makeDependencyCommand(argument: argument).run()
        showResult(resultDependency)
        exit(0)
    case "scaffold":
        let edges = makeEdges(argument: argument)
        edges.forEach { edge in
            let resultCreateRIB = makeCreateRIBCommand(edge: edge).run()
            showResult(resultCreateRIB)

            let resultCreateComponentExtension = makeCreateComponentExtension(edge: edge).run()
            showResult(resultCreateComponentExtension)

            let resultDependency = makeDependencyCommand(edge: edge).run()
            showResult(resultDependency)
        }
        exit(0)
    default:
        let result = HelpCommand().run()
        showResult(result)
        exit(0)
    }
}

// MARK: - Convenient methods
func showResult(_ result: Result) {
    switch result {
    case let .success(message):
        print(message)
    case let .failure(error):
        print(error.message.red)
        print("\n failure.".red.applyingStyle(.bold))
        exit(Int32(error.code))
    }
}

func allSwiftSourcePaths(directoryPath: String) -> [String] {
    let absolutePath = Path(directoryPath).absolute()

    do {
        return try absolutePath.recursiveChildren().filter({ $0.extension == "swift" }).map({ $0.string })
    } catch {
        return []
    }
}

// MARK: - Analyze methods
func analyzeArguments(commandLineArguments: [String]) -> Argument? {
    guard let firstArgument = commandLineArguments.first else {
        print("Lack of argument.".red.bold)
        return nil
    }

    let commandLineArgumentsLackOfFirst = commandLineArguments.dropFirst()
    guard let secondArgument = commandLineArgumentsLackOfFirst.first else {
        print("Lack of argument.".red.bold)
        return nil
    }
    let optionArguments = commandLineArgumentsLackOfFirst.dropFirst()

    var otherArguments = [String:String]()
    var latestOptionKey = ""
    optionArguments.forEach { argument in
        if argument.contains("--") {
            let optionKey = argument.replacingOccurrences(of: "--", with: "")
            otherArguments[optionKey] = ""
            latestOptionKey = optionKey
        } else {
            otherArguments[latestOptionKey] = argument
        }
    }

    return Argument(first: firstArgument, second: secondArgument, options: otherArguments)
}

func analyzeSettings() -> Setting? {
    guard let settingFilePath = Path.current.glob(".ribscodegen").first else {
        print("Not found setting file, add .ribscodegen at current directory".red.bold)
        return nil
    }

    let settingFile: String? = try? settingFilePath.read()
    guard let settingFileString = settingFile else {
        print("Failed to read .ribscodegen.".red.bold)
        return nil
    }

    let decoder = YAMLDecoder()
    do {
        return try decoder.decode(Setting.self, from: settingFileString)
    } catch {
        print("Failed to decode .ribscodegen. Check the setting values.".red.bold)
        return nil
    }
}

// MARK: - Make command methods
func makeCreateRIBCommand(argument: Argument) -> Command {
    let paths = allSwiftSourcePaths(directoryPath: setting.targetDirectory)
    return CreateRIBCommand(paths: paths,
                            setting: setting,
                            target: argument.second,
                            isOwnsView: !argument.noView)
}

func makeCreateRIBCommand(edge: Edge) -> Command {
    let paths = allSwiftSourcePaths(directoryPath: setting.targetDirectory)
    return CreateRIBCommand(paths: paths,
                            setting: setting,
                            target: edge.target,
                            isOwnsView: edge.isOwnsView)
}

func makeCreateComponentExtension(argument: Argument) -> Command {
    let paths = allSwiftSourcePaths(directoryPath: setting.targetDirectory)
    return CreateComponentExtension(paths: paths,
                                    setting: setting,
                                    parent: argument.parent,
                                    child: argument.second)
}

func makeCreateComponentExtension(edge: Edge) -> Command {
    let paths = allSwiftSourcePaths(directoryPath: setting.targetDirectory)
    return CreateComponentExtension(paths: paths,
                                    setting: setting,
                                    parent: edge.parent,
                                    child: edge.target)
}

func makeDependencyCommand(argument: Argument) -> Command {
    let paths = allSwiftSourcePaths(directoryPath: setting.targetDirectory)
    return DependencyCommand(paths: paths,
                             parent: argument.parent,
                             child: argument.second)
}

func makeDependencyCommand(edge: Edge) -> Command {
    let paths = allSwiftSourcePaths(directoryPath: setting.targetDirectory)
    return DependencyCommand(paths: paths,
                             parent: edge.parent,
                             child: edge.target)
}

func makeEdges(argument: Argument) -> [Edge] {
    guard let treePath = Path.current.glob(argument.second).first else {
        fatalError("Needs to add markdown file path for second argument.".red.bold)
    }

    guard let treeString: String = try? treePath.read() else {
        fatalError("Failed to read file: \(treePath)".red.bold)
    }

    let argumentParentRIBName = argument.parent

    let treeArray = treeString.components(separatedBy: "\n")
    let reversedTreeArray = treeArray.reversed()
    let nodes: [Node] = reversedTreeArray
        .map { $0.components(separatedBy: "- ") }
        .map { array -> Node? in
            let spaceCount = array.first?.count ?? 0
            guard let ribName = array.last, !ribName.isEmpty else {
                return nil
            }
            let erasedSpaceRIBName = ribName.replacingOccurrences(of: " ", with: "")
            let isOwnsView = !erasedSpaceRIBName.contains("*")
            let extractedRIBNameString = erasedSpaceRIBName.replacingOccurrences(of: "*", with: "")
            return Node(spaceCount: spaceCount, ribName: extractedRIBNameString, isOwnsView: isOwnsView)
        }
        .compactMap { $0 }

    var edges = [Edge]()
    for (index, node) in nodes.enumerated() {
        let filteredNodes = nodes[index..<nodes.count]

        guard let parentNode = filteredNodes.filter({ $0.spaceCount < node.spaceCount }).first else {
            edges.append(Edge(parent: argumentParentRIBName, target: node.ribName, isOwnsView: node.isOwnsView))
            continue
        }
        edges.append(Edge(parent: parentNode.ribName, target: node.ribName, isOwnsView: node.isOwnsView))
    }

    return edges.reversed()
}

main()
