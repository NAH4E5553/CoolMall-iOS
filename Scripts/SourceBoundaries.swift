import Foundation
import SwiftParser
import SwiftSyntax

struct SourceJob: Decodable {
    let path: String
    let target: String
    let imports: [String]
    let testable: [String]
    let restricted: Bool
}

final class BoundaryVisitor: SyntaxVisitor {
    let job: SourceJob
    var failures: [String] = []
    init(job: SourceJob) { self.job = job; super.init(viewMode: .all) }
    func fail(_ rule: String, _ message: String) {
        failures.append("\(rule): \(job.path): \(message)")
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let module = node.path.first?.name.text ?? ""
        if !job.imports.contains(module) {
            fail("MOD-01", "forbidden import \(module) in \(job.target)")
        }
        for attribute in node.attributes {
            guard let value = attribute.as(AttributeSyntax.self) else { continue }
            if value.attributeName.trimmedDescription == "testable", !job.testable.contains(module)
            {
                fail("MOD-02", "forbidden @testable import \(module)")
            }
        }
        return .visitChildren
    }
    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.attributeName.trimmedDescription
        if ["_spi", "_exported", "_implementationOnly", "preconcurrency"].contains(name) {
            fail("MOD-02", "forbidden attribute @\(name)")
        }
        return .visitChildren
    }
    override func visit(_ node: DeclModifierSyntax) -> SyntaxVisitorContinueKind {
        if ["package", "open"].contains(node.name.text) {
            fail("MOD-02", "forbidden \(node.name.text) access")
        }
        if node.name.text == "nonisolated", node.detail?.detail.text == "unsafe" {
            fail("MOD-02", "nonisolated(unsafe)")
        }
        return .visitChildren
    }
    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        // Inspect identifier tokens only: string segments may also equal an API name.
        // All conditional-compilation branches are visited.
        guard case .identifier = node.tokenKind else { return .visitChildren }
        let dangerous: Set<String> = [
            "URLSession", "URLRequest", "URLProtocol", "UserDefaults", "AppStorage", "FileManager",
            "ModelContext", "ModelContainer", "PersistentContainer", "NSPersistentContainer",
            "SecItemAdd", "SecItemCopyMatching", "SecItemUpdate", "SecItemDelete",
            "NotificationCenter",
        ]
        if job.restricted, dangerous.contains(node.text) {
            fail("MOD-05", "direct API \(node.text)")
        }
        if node.text == "unchecked" { fail("MOD-02", "unchecked concurrency conformance") }
        return .visitChildren
    }
    /// Registered Feature public entries. Each name is a user-approved public
    /// View entry: the original composition entry per target, plus
    /// CatalogFeature.HomeEntryView (ENGINEERING 4.6.1 H0 v0.2, DEC-008 /
    /// APPROVAL-HOME-01-H0-20261009). Anything else stays rejected.
    static let registeredFeatureEntries: [String: [String]] = [
        "CatalogFeature": ["CatalogEntryView", "HomeEntryView"],
        "CartFeature": ["CartEntryView"],
    ]

    func checkType(_ name: String, _ modifiers: DeclModifierListSyntax) {
        let exported = modifiers.contains { ["public", "open", "package"].contains($0.name.text) }
        if exported && (name.hasSuffix("ViewModel") || name.hasSuffix("DTO")) {
            fail("MOD-02", "implementation type must remain internal: \(name)")
        }
        if exported, job.target.hasSuffix("Feature"),
            !(Self.registeredFeatureEntries[job.target] ?? []).contains(name)
        {
            fail("MOD-02", "unregistered Feature public type \(name)")
        }
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(node.name.text, node.modifiers); return .visitChildren
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(node.name.text, node.modifiers); return .visitChildren
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(node.name.text, node.modifiers); return .visitChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(node.name.text, node.modifiers); return .visitChildren
    }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(node.name.text, node.modifiers); return .visitChildren
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        checkType(node.name.text, node.modifiers); return .visitChildren
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
    let jobs = try JSONDecoder().decode(
        [SourceJob].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    guard !jobs.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    var failures: [String] = []
    for job in jobs {
        let tree = Parser.parse(source: try String(contentsOfFile: job.path, encoding: .utf8))
        if tree.hasError { failures.append("MOD-02: Swift parse error: \(job.path)") }
        let visitor = BoundaryVisitor(job: job)
        visitor.walk(tree)
        failures += visitor.failures
    }
    for failure in failures { print(failure) }
    if !failures.isEmpty { exit(1) }
    print(
        "PASS: SwiftSyntax imports/access/known API checks (\(jobs.count) files); semantic review still required."
    )
} catch { print("FAIL: source checker: \(error)"); exit(1) }
