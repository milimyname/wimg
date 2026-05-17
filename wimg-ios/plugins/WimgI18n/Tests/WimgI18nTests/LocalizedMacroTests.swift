import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WimgI18nMacros

final class LocalizedMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "L": LocalizedMacro.self,
    ]

    func testSimpleLiteral() {
        assertMacroExpansion(
            #"""
            let x = #L("Gesamtsaldo")
            """#,
            expandedSource: #"""
            let x = __t("Gesamtsaldo")
            """#,
            macros: testMacros
        )
    }

    func testInterpolation() {
        assertMacroExpansion(
            #"""
            let x = #L("\(count) Transaktionen")
            """#,
            expandedSource: #"""
            let x = __t("%@ Transaktionen", count)
            """#,
            macros: testMacros
        )
    }

    func testMultipleInterpolations() {
        assertMacroExpansion(
            #"""
            let x = #L("Du sparst \(a) von \(b)")
            """#,
            expandedSource: #"""
            let x = __t("Du sparst %@ von %@", a, b)
            """#,
            macros: testMacros
        )
    }

    func testEscapedQuotes() {
        // SwiftSyntaxBuilder emits a raw-string literal when the value contains
        // double quotes — both forms are semantically equivalent to the compiler.
        assertMacroExpansion(
            #"""
            let x = #L("Sag \"Hallo\"")
            """#,
            expandedSource: ##"""
            let x = __t(#"Sag \"Hallo\""#)
            """##,
            macros: testMacros
        )
    }
}
