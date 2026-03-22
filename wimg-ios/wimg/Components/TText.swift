import SwiftUI

/// Translated Text — like Text() but always does localization lookup.
/// Use instead of Text() when rendering strings from variables.
/// Text("literal") already auto-localizes; TText(variable) does too.
struct TText: View {
    private let key: LocalizedStringKey

    init(_ string: String) {
        self.key = LocalizedStringKey(string)
    }

    var body: some View {
        Text(key)
    }
}
