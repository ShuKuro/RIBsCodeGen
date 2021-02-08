//
//  CreateComponentExtension.swift
//  RIBsCodeGen
//
//  Created by 今入　庸介 on 2021/02/05.
//

import Foundation
import SourceKittenFramework
import PathKit

struct CreateComponentExtension: Command {
    let needsCreateTargetFile: Bool
    let targetDirectory: String
    let templateDirectory: String
    let parent: String
    let child: String

    init(paths: [String],
         setting: Setting,
         parent: String,
         child: String) {
        targetDirectory = setting.targetDirectory
        templateDirectory = setting.templateDirectory
        needsCreateTargetFile = paths.filter({ $0.contains("\(parent)Component+\(child).swift") }).isEmpty

        self.parent = parent
        self.child = child
    }

    func run() -> Result {
        guard needsCreateTargetFile else {
            return .success(message: "No need to add ComponentExtension, it already be exists.".yellow.bold)
        }
        do {
            try createDirectory()
        } catch {
            return .failure(error: .failedCreateDirectory)
        }

        do {
            try createFiles()
        } catch {
            return .failure(error: .failedCreateFile)
        }

        return .success(message: "Success to create \(parent)Component+\(child).swift".green.bold)
    }
}

// MARK: - Private methods
private extension CreateComponentExtension {
    func createDirectory() throws {
        let filePath = targetDirectory + "/\(parent)/Dependencies" // 親 Directory -> Dependencies
        guard !Path(filePath).exists else {
            print("skip to create directory: \(filePath)")
            return
        }

        try Path(stringLiteral: filePath).mkdir()
    }

    func createFiles() throws {
        let filePath = targetDirectory + "/\(parent)/Dependencies" + "/\(parent)Component+\(child).swift"
        let template: String = try Path(templateDirectory + "/ComponentExtension/ComponentExtension.swift").read()
        let replacedText = template
            .replacingOccurrences(of: "___VARIABLE_productName___", with: "\(parent)")
            .replacingOccurrences(of: "___VARIABLE_childName___", with: "\(child)")
        try Path(filePath).write(replacedText)
    }
}

