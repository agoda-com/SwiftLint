import Foundation
import SourceKittenFramework

public struct DeploymentTargetRule: ConfigurationProviderRule {
    private typealias Version = DeploymentTargetConfiguration.Version
    public var configuration = DeploymentTargetConfiguration()

    public init() {}

    public static let description = RuleDescription(
        identifier: "deployment_target",
        name: "Deployment Target",
        description: "Availability checks or attributes shouldn't be using older versions " +
                     "that are satisfied by the deployment target.",
        kind: .lint,
        minSwiftVersion: .fourDotOne,
        nonTriggeringExamples: [
            "@available(iOS 12.0, *)\nclass A {}",
            "@available(watchOS 4.0, *)\nclass A {}",
            "@available(swift 3.0.2)\nclass A {}",
            "class A {}",
            "if #available(iOS 10.0, *) {}",
            "if #available(iOS 10, *) {}",
            "guard #available(iOS 12.0, *) else { return }"
        ],
        triggeringExamples: [
            "↓@available(iOS 6.0, *)\nclass A {}",
            "↓@available(iOS 7.0, *)\nclass A {}",
            "↓@available(iOS 6, *)\nclass A {}",
            "↓@available(iOS 6.0, macOS 10.12, *)\n class A {}",
            "↓@available(macOS 10.12, iOS 6.0, *)\n class A {}",
            "↓@available(macOS 10.7, *)\nclass A {}",
            "↓@available(OSX 10.7, *)\nclass A {}",
            "↓@available(watchOS 0.9, *)\nclass A {}",
            "↓@available(tvOS 8, *)\nclass A {}",
            "if ↓#available(iOS 6.0, *) {}",
            "if ↓#available(iOS 6, *) {}",
            "guard ↓#available(iOS 6.0, *) else { return }"
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        var violations = validateAttributes(file: file, dictionary: file.structureDictionary)
        violations += validateConditions(file: file)
        violations.sort(by: { $0.location < $1.location })

        return violations
    }

    private func validateConditions(file: SwiftLintFile) -> [StyleViolation] {
        let pattern = "#available\\s*\\([^\\(]+\\)"

        return file.rangesAndTokens(matching: pattern).flatMap { range, tokens -> [StyleViolation] in
            guard let availabilityToken = tokens.first,
                availabilityToken.kind == .keyword,
                let tokenRange = file.stringView.byteRangeToNSRange(start: availabilityToken.offset,
                                                                    length: availabilityToken.length) else {
                    return []
            }

            let rangeToSearch = NSRange(location: tokenRange.upperBound, length: range.length - tokenRange.length)
            return validate(range: rangeToSearch, file: file, violationType: "condition",
                            byteOffsetToReport: availabilityToken.offset)
        }
    }

    private func validateAttributes(file: SwiftLintFile, dictionary: SourceKittenDictionary) -> [StyleViolation] {
        return dictionary.traverseDepthFirst { subDict in
            guard let kind = subDict.declarationKind else { return nil }
            return validateAttributes(file: file, kind: kind, dictionary: subDict)
        }
    }

    private func validateAttributes(file: SwiftLintFile,
                                    kind: SwiftDeclarationKind,
                                    dictionary: SourceKittenDictionary) -> [StyleViolation] {
        let attributes = dictionary.swiftAttributes.filter {
            $0.attribute.flatMap(SwiftDeclarationAttributeKind.init) == .available
        }
        guard !attributes.isEmpty else {
            return []
        }

        let contents = file.stringView
        return attributes.flatMap { dictionary -> [StyleViolation] in
            guard let offset = dictionary.offset, let length = dictionary.length,
                let range = contents.byteRangeToNSRange(start: offset, length: length) else {
                    return []
            }

            return validate(range: range, file: file, violationType: "attribute", byteOffsetToReport: offset)
        }.unique
    }

    private func validate(range: NSRange, file: SwiftLintFile, violationType: String,
                          byteOffsetToReport: Int) -> [StyleViolation] {
        let platformToConfiguredMinVersion = self.platformToConfiguredMinVersion
        let allPlatforms = "(?:" + platformToConfiguredMinVersion.keys.joined(separator: "|") + ")"
        let pattern = "\(allPlatforms) [\\d\\.]+"

        return file.rangesAndTokens(matching: pattern, range: range).compactMap { _, tokens -> StyleViolation? in
            guard tokens.count == 2,
                tokens.kinds == [.keyword, .number],
                let platform = file.contents(for: tokens[0]),
                let minVersion = platformToConfiguredMinVersion[platform],
                let versionString = file.contents(for: tokens[1]) else {
                    return nil
            }

            guard let version = try? Version(rawValue: versionString),
                version <= minVersion else {
                    return nil
            }

            let reason = """
            Availability \(violationType) is using a version (\(versionString)) that is \
            satisfied by the deployment target (\(minVersion.stringValue)) for platform \(platform).
            """
            return StyleViolation(ruleDescription: type(of: self).description,
                                  severity: configuration.severityConfiguration.severity,
                                  location: Location(file: file, byteOffset: byteOffsetToReport),
                                  reason: reason)
        }
    }

    private var platformToConfiguredMinVersion: [String: Version] {
        return [
            "iOS": configuration.iOSDeploymentTarget,
            "macOS": configuration.macOSDeploymentTarget,
            "OSX": configuration.macOSDeploymentTarget,
            "tvOS": configuration.tvOSDeploymentTarget,
            "watchOS": configuration.watchOSDeploymentTarget
        ]
    }
}
