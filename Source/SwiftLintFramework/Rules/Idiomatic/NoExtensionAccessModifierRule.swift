import SourceKittenFramework

public struct NoExtensionAccessModifierRule: ASTRule, OptInRule, ConfigurationProviderRule, AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.error)

    public init() {}

    public static let description = RuleDescription(
        identifier: "no_extension_access_modifier",
        name: "No Extension Access Modifier",
        description: "Prefer not to use extension access modifiers",
        kind: .idiomatic,
        nonTriggeringExamples: [
            "extension String {}",
            "\n\n extension String {}"
        ],
        triggeringExamples: [
            "↓private extension String {}",
            "↓public \n extension String {}",
            "↓open extension String {}",
            "↓internal extension String {}",
            "↓fileprivate extension String {}"
        ]
    )

    public func validate(file: SwiftLintFile, kind: SwiftDeclarationKind,
                         dictionary: SourceKittenDictionary) -> [StyleViolation] {
        guard kind == .extension, let offset = dictionary.offset else {
            return []
        }

        let syntaxTokens = file.syntaxMap.tokens
        let parts = syntaxTokens.prefix(while: { offset > $0.offset })
        guard let aclToken = parts.last, file.isACL(token: aclToken) else {
            return []
        }

        return [
            StyleViolation(ruleDescription: type(of: self).description,
                           severity: configuration.severity,
                           location: Location(file: file, byteOffset: aclToken.offset))
        ]
    }
}
