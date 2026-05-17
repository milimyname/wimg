import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WimgI18nMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LocalizedMacro.self,
    ]
}
