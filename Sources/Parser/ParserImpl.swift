//
//  Copyright © 2021 Dropbox, Inc. All rights reserved.
//

import Files
import Foundation
import SourceKittenFramework
import Utilities

public final class ParserImpl: Parser {
    private let queue = DispatchQueue(
        label: "com.dropbox.ParserImpl",
        qos: .background,
        attributes: .concurrent,
        autoreleaseFrequency: .workItem
    )
    private let typeRegex: NSRegularExpression

    public var printOnly = false
    public var cachePath: String?

    public init() throws {
        self.typeRegex = try NSRegularExpression(pattern: #"\([^\)]*\)"#, options: [])
    }

    public func listTypes(from input: ParserListTypesInput, rootFolderPath: String) throws -> ParserListTypesOutput {
        LogInfo("Starting parser of \(input.filePaths.count) files")
        LogVerbose(input.description)

        let cacheFolder: Folder?
        if let cachePath = cachePath {
            cacheFolder = try? Folder(path: "/").createSubfolderIfNeeded(at: cachePath)
        } else {
            cacheFolder = nil
        }

        var parsedFiles = [String: ParsedFile]()
        input.overrides?.forEach { parsedFiles[$0.filePath] = $0 }

        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        input.filePaths.forEach { filePath -> Void in
            lock.lock()
            guard parsedFiles[filePath] == nil else {
                lock.unlock()
                return
            }
            lock.unlock()
            
            dispatchGroup.enter()
            queue.async { () -> Void in

                let file: ParsedFile
                if let cachedFile = self.cachedFile(forPath: filePath, cacheFolder: cacheFolder) {
                    file = cachedFile
                } else {
                    do {
                        file = try self.parse(filePath, rootFolderPath: rootFolderPath)
                    } catch {
                        Log(error)
                        file = ParsedFile(
                            filePath: filePath,
                            definedTypeNames: [],
                            requiredTypeNames: [],
                            error: error.localizedDescription
                        )
                    }
                    self.cache(file: file, cacheFolder: cacheFolder)
                }
                lock.lock()
                parsedFiles[filePath] = file
                lock.unlock()
                dispatchGroup.leave()
            }
        }
        dispatchGroup.wait()

        let processedFiles = process(parsedFiles: parsedFiles)
        let output = ParserListTypesOutput(files: processedFiles)
        LogInfo("Parser finished processing \(output.files.count) files at \(rootFolderPath)")

        writeJson(output: output, toPath: input.jsonOutputPath)
        writeCsv(output: output, toPath: input.csvOutputPath)

        log(output: output)

        return output
    }

    // MARK: - Private

    public func cacheFileName(forFilePath filePath: String) -> String {
        let digest = filePath.utf8.md5
        return "\(digest).json"
    }

    private func cachedFile(forPath filePath: String, cacheFolder: Folder?) -> ParsedFile? {
        guard let cacheFile = try? cacheFolder?.file(at: cacheFileName(forFilePath: filePath)) else { return nil }
        do {
            let json = try cacheFile.readAsString()
            let parsedFile: ParsedFile = try json.parseJson()
            return parsedFile
        } catch {
            LogError("Failed to load cached file due to \(error)")
            return nil
        }
    }

    private func cache(file: ParsedFile, cacheFolder: Folder?) {
        do {
            guard let cacheFile = try cacheFolder?.createFileIfNeeded(at: cacheFileName(forFilePath: file.filePath))
            else { return }
            let jsonString = try file.json()
            try cacheFile.write(jsonString)
        } catch {
            LogError("Failed to cache file due to \(error)")
        }
    }

    private func process(parsedFiles: [String: ParsedFile]) -> [ParsedFile] {
        let definedTypeNames = parsedFiles.values
            .filter { $0.error == nil }
            .reduce(into: Set<String>()) { $0.formUnion($1.definedTypeNames) }
        let processedFiles = parsedFiles.values.map { file -> ParsedFile in
            var file = file
            file.requiredTypeNames = file.requiredTypeNames.filter { definedTypeNames.contains($0) }
            return file
        }
        return processedFiles.sorted { $0.filePath < $1.filePath }
    }

    private func log(output: ParserListTypesOutput) {
        let errorFiles = output.files.filter { $0.error != nil }.map(\.filePath)
        if !errorFiles.isEmpty {
            LogInfo(errorFiles.reduce("File Errors\n") { $0 + $1 + "\n" })
        }

        let definedTypeNames = output.files.reduce(into: Set<String>()) { $0.formUnion($1.definedTypeNames) }
        let requiredTypeNames = output.files.reduce(into: Set<String>()) { $0.formUnion($1.requiredTypeNames) }
        let missingTypeNames = requiredTypeNames.subtracting(definedTypeNames)
        if !missingTypeNames.isEmpty {
            LogInfo(missingTypeNames.reduce("Missing Types\n") { $0 + $1 + "\n" })
        }
    }

    private func writeJson(output: ParserListTypesOutput, toPath outputFilePath: String?) {
        guard let outputFilePath = outputFilePath else {
            return
        }
        do {
            try Folder(path: "/").createFileIfNeeded(at: outputFilePath)
        } catch {
            LogWarn("Failed to create file due to \(error)")
        }
        do {
            let jsonString = try output.json()
            let outputFile = try Files.File(path: outputFilePath)
            try outputFile.write(jsonString)
        } catch {
            LogError("Failed to write json output file due to \(error)")
        }
    }

    private func writeCsv(output: ParserListTypesOutput, toPath outputFilePath: String?) {
        guard let outputFilePath = outputFilePath else {
            return
        }
        do {
            try Folder(path: "/").createFileIfNeeded(at: outputFilePath)
        } catch {
            LogWarn("Failed to create file due to \(error)")
        }

        let definedTypeNames = output.files
            .filter { $0.error == nil }
            .reduce(into: Set<String>()) { $0.formUnion($1.definedTypeNames) }
        let fileTypeCount = output.files
            .sorted { $0.filePath < $1.filePath }
            .reduce("File Path,Type Count,Types\n") { output, file -> String in
                let missingTypes = definedTypeNames.intersection(file.requiredTypeNames).sorted()
                let types = missingTypes.joined(separator: " ")
                return output + "\(file.filePath),\(missingTypes.count),\(types)\n"
            }

        do {
            let outputFile = try Files.File(path: outputFilePath)
            try outputFile.write(fileTypeCount)
        } catch {
            LogError("Failed to write csv output file due to \(error)")
        }
    }

    private func parse(_ filePath: String, rootFolderPath: String) throws -> ParsedFile {
        let fileURL = URL(fileURLWithPath: rootFolderPath).appendingPathComponent(filePath)
        let fullPath = fileURL.path
        print("===== Parsing \(fullPath)")
        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw SystemError.missingFile
        }
        switch fileURL.pathExtension {
        case "swift": return try parseSwift(filePath, fullPath: fullPath)
        case "h": return try parseObjcHeader(filePath, fullPath: fullPath)
        case "mm", "m": return try parseObjcImplementation(filePath, fullPath: fullPath)
        default: throw SystemError.failedToParse(reason: "Invalid file type \(fileURL.pathExtension)")
        }
    }

    private func parseObjcImplementation(_ filePath: String, fullPath: String) throws -> ParsedFile {
        let file = try Files.File(path: fullPath)
        let parsedFile = try file.readAsString().components(separatedBy: CharacterSet.alphanumerics.inverted)
        var requiredTypeNames = Set<String>(parsedFile)
        requiredTypeNames = clean(types: requiredTypeNames)
        return ParsedFile(
            filePath: filePath,
            definedTypeNames: [],
            requiredTypeNames: requiredTypeNames.sorted(),
            error: nil
        )
    }

    private func parseObjcHeader(_ filePath: String, fullPath: String) throws -> ParsedFile {
        let compilerArguments = ["-x", "objective-c", "-fmodules", "-isysroot", sdkPath()]
        let unit = ClangTranslationUnit(headerFiles: [fullPath], compilerArguments: compilerArguments)
        guard let declarations = unit.declarations[fullPath] else {
            throw SystemError.failedToParse(reason: "Clang failed to create translation unit")
        }
        var definedTypeNames = Set<String>()
        var requiredTypeNames = Set<String>()
        try declarations.forEach {
            try parseTypes(
                from: $0,
                definedTypeNames: &definedTypeNames,
                requiredTypeNames: &requiredTypeNames
            )
        }
        definedTypeNames = clean(types: definedTypeNames)
        requiredTypeNames = clean(types: requiredTypeNames)

        requiredTypeNames.subtract(definedTypeNames)
        requiredTypeNames.subtract(SystemTypeNames.objc)
        definedTypeNames.subtract(SystemTypeNames.objc)
        return ParsedFile(
            filePath: filePath,
            definedTypeNames: definedTypeNames.sorted(),
            requiredTypeNames: requiredTypeNames.sorted(),
            error: nil
        )
    }

    private func parseTypes(
        from sourceDeclaration: SourceDeclaration,
        definedTypeNames: inout Set<String>,
        requiredTypeNames: inout Set<String>
    ) throws {
        try sourceDeclaration.children.forEach {
            try parseTypes(
                from: $0,
                definedTypeNames: &definedTypeNames,
                requiredTypeNames: &requiredTypeNames
            )
        }
        guard let declaration = sourceDeclaration.declaration else {
            LogVerbose("Skipping \(sourceDeclaration.type)")
            return
        }

        switch sourceDeclaration.type {
        case .category:
            break
        case .class:
            guard let name = sourceDeclaration.name
            else { throw SystemError.failedToParse(reason: "Missing class name") }
            definedTypeNames.insert(name)
            if let swiftName = sourceDeclaration.swiftName {
                definedTypeNames.insert(swiftName)
            }
        case .constant:
            break
        case .enum:
            guard let name = sourceDeclaration.name
            else { throw SystemError.failedToParse(reason: "Missing enum name") }
            let newDefinition = declaration.range(of: #"\{(.*|\n)*\}"#, options: .regularExpression) != nil
            if newDefinition {
                definedTypeNames.insert(name)
            } else {
                requiredTypeNames.insert(name)
            }
        case .enumcase:
            break
        case .initializer:
            let declaredTypes = try types(from: declaration)
            requiredTypeNames.formUnion(declaredTypes)
        case .methodClass:
            let declaredTypes = try types(from: declaration)
            requiredTypeNames.formUnion(declaredTypes)
        case .methodInstance:
            let declaredTypes = try types(from: declaration)
            requiredTypeNames.formUnion(declaredTypes)
        case .property:
            guard let name = sourceDeclaration.name
            else { throw SystemError.failedToParse(reason: "Misisng property name") }
            let typeWithoutName =
                declaration
                    .drop { $0 != ")" }
                    .dropFirst() // )
                    .dropLast(name.count)
            let declaredTypes = nestedTypes(from: String(typeWithoutName))
            requiredTypeNames.formUnion(declaredTypes)
        case .protocol:
            guard let name = sourceDeclaration.name
            else { throw SystemError.failedToParse(reason: "Missing protocol name") }
            definedTypeNames.insert(name)
            if let swiftName = sourceDeclaration.swiftName {
                definedTypeNames.insert(swiftName)
            }
        case .typedef:
            break
        case .function:
            let declaredTypes = try types(from: declaration)
            requiredTypeNames.formUnion(declaredTypes)
        case .mark:
            break
        case .struct:
            throw SystemError.unsupported
        case .field:
            let declaredTypes = try types(from: declaration)
            requiredTypeNames.formUnion(declaredTypes)
        case .ivar:
            guard let name = sourceDeclaration.name
            else { throw SystemError.failedToParse(reason: "Missing ivar name") }
            let typeWithoutName = declaration.dropLast(name.count)
            let declaredTypes = nestedTypes(from: String(typeWithoutName))
            requiredTypeNames.formUnion(declaredTypes)
        case .moduleImport:
            break
        case .unexposedDecl:
            break
        case .union:
            break
        case .staticAssert:
            break
        }
    }

    private func types(from declaration: String) throws -> [String] {
        let nsrange = NSRange(declaration.startIndex ..< declaration.endIndex, in: declaration)
        let stopIndex = declaration.firstIndex(of: "{")
        var types = [String]()
        typeRegex.enumerateMatches(in: declaration, options: [], range: nsrange) { match, _, stop in
            guard let match = match else { return }
            guard let range = Range(match.range, in: declaration) else {
                return
            }
            if let stopIndex = stopIndex, range.lowerBound > stopIndex {
                stop.pointee = true
                return
            }
            let rawType = declaration[range]
                .dropFirst() // (
                .dropLast() // )
            let newTypes = nestedTypes(from: String(rawType))
            types.append(contentsOf: newTypes)
        }
        return types
    }

    private func nestedTypes(from string: String) -> [String] {
        string
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: ">", with: "")
            .components(separatedBy: "<")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func parseSwift(_ filePath: String, fullPath: String) throws -> ParsedFile {
        guard let file = File(path: fullPath) else {
            throw SystemError.failedToParse(reason: "Missing file at \(fullPath)")
        }
        let structure = try Structure(file: file)
        let dictionary = SourceKittenDictionary(structure.dictionary)

        var definedTypeNames = Set<String>()
        var requiredTypeNames = Set<String>()
        var privateTypeNames = Set<String>()

        parseTypes(
            from: dictionary,
            parentType: "",
            definedTypeNames: &definedTypeNames,
            requiredTypeNames: &requiredTypeNames,
            privateTypeNames: &privateTypeNames
        )
        definedTypeNames = clean(types: definedTypeNames)
        requiredTypeNames = clean(types: requiredTypeNames)
        privateTypeNames = clean(types: privateTypeNames)

        requiredTypeNames.subtract(definedTypeNames)
        requiredTypeNames.subtract(privateTypeNames)
        requiredTypeNames.subtract(SystemTypeNames.swift)
        definedTypeNames.subtract(SystemTypeNames.swift)

        return ParsedFile(
            filePath: filePath,
            definedTypeNames: definedTypeNames.sorted(),
            requiredTypeNames: requiredTypeNames.sorted(),
            error: nil
        )
    }

    private func parseTypes(
        from dictionary: SourceKittenDictionary,
        parentType: String,
        definedTypeNames: inout Set<String>,
        requiredTypeNames: inout Set<String>,
        privateTypeNames: inout Set<String>
    ) {
        let kind = dictionary.declarationKind ?? .opaqueType

        let baseTypeName = (dictionary.typeName ?? dictionary.name ?? "").replacingOccurrences(of: "?", with: "")
        let typeName: String
        let childType: String
        if kind == .class || kind == .struct || kind == .enum {
            typeName = "\(parentType).\(baseTypeName)"
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .replacingOccurrences(of: dictionary.moduleName ?? "", with: "")
            childType = typeName
        } else {
            typeName = baseTypeName
            childType = ""
        }
        dictionary.substructure.forEach {
            parseTypes(
                from: $0,
                parentType: childType,
                definedTypeNames: &definedTypeNames,
                requiredTypeNames: &requiredTypeNames,
                privateTypeNames: &privateTypeNames
            )
        }
        guard !typeName.isEmpty else {
            LogVerbose("Missing typeName for \(kind)")
            return
        }

        let isPrivate = dictionary.accessibility?.isPrivate ?? false
        switch kind {
        case .protocol, .class, .struct, .enum:
            let hasObjcName = dictionary.enclosedSwiftAttributes.contains { $0 == .objcName }
            if isPrivate {
                if let objcName = dictionary.runtimeName, hasObjcName {
                    privateTypeNames.insert(objcName)
                }
                privateTypeNames.insert(typeName)
            } else {
                if let objcName = dictionary.runtimeName, hasObjcName {
                    definedTypeNames.insert(objcName)
                }
                definedTypeNames.insert(typeName)
            }
            requiredTypeNames.formUnion(dictionary.inheritedTypes)
        case .varInstance, .varParameter:
            requiredTypeNames.insert(typeName)
        default:
            LogVerbose("Skipping \(kind) \(typeName)")
        }
    }

    private func clean(types: Set<String>) -> Set<String> {
        guard !types.isEmpty else { return types }
        let cleanedTypes =
            types.flatMap {
                $0.components(separatedBy: CharacterSet(charactersIn: ", &\n<>()"))
            }
            .map {
                $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            }
            .filter {
                !$0.isEmpty && $0.first!.isUppercase
            }
            .filter {
                !SystemTypeNames.invalid.contains($0)
            }
            .filter {
                !$0.hasPrefix("NS")
                    && !$0.hasPrefix("UI")
                    && !$0.hasPrefix("CG")
                    && !$0.hasPrefix("CA")
                    && !$0.hasPrefix("AV")
                    && !$0.hasPrefix("WK")
            }
        return Set(cleanedTypes)
    }
}

enum SystemTypeNames {
    static let invalid = Set(
        [
            "nonnull",
            "nullable",
            "Nullable",
            "Nonnull",
            "_Nullable",
            "_Nonnull",
            "__weak",
            "weak",
            "unsigned",
            "SEL",
        ]
    )

    static let objc = Set(
        [
            "BOOL",
            "CGSize",
            "Class",
            "CLLocationCoordinate2D",
            "CMTime",
            "dispatch_queue_t",
            "double",
            "float",
            "id",
            "instancetype",
            "int",
            "int64_t",
            "NSArray",
            "NSDate",
            "NSDictionary",
            "NSError",
            "NSObject",
            "NSCache",
            "NSSet",
            "NSString",
            "NSStringEncoding",
            "NSTimeInterval",
            "UIBackgroundFetchResult",
            "UIImage",
            "UIInterfaceOrientationMask",
            "void",
        ]
    )

    static let swift = Set(
        [
            "Any",
            "AnyHashable",
            "Bool",
            "CaseIterable",
            "class",
            "Data",
            "Date",
            "Double",
            "Error",
            "Float",
            "Hasher",
            "Integer",
            "NSCache",
            "String",
            "UIBackgroundFetchResult",
            "UIImage",
            "UIInterfaceOrientationMask",
            "URL",
            "Void",
        ]
    )
}
