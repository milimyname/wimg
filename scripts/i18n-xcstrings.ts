/**
 * Generates iOS i18n files from the en.ts translation map:
 * 1. Localizable.xcstrings — Apple String Catalog (for Text("literal") views)
 * 2. Translations.swift — runtime lookup (for Text(variable) views)
 *
 * Usage: bun scripts/i18n-xcstrings.ts
 */
import { writeFileSync } from "node:fs";
import { en } from "../wimg-web/src/lib/translations/en";

// --- 1. Generate .xcstrings ---
const strings: Record<
  string,
  {
    localizations: Record<
      string,
      { stringUnit: { state: string; value: string } }
    >;
  }
> = {};

for (const [de, enValue] of Object.entries(en)) {
  strings[de] = {
    localizations: {
      de: { stringUnit: { state: "translated", value: de } },
      en: { stringUnit: { state: "translated", value: enValue } },
    },
  };
}

const xcstrings = { sourceLanguage: "de", version: "1.0", strings };
const xcstringsPath = "wimg-ios/wimg/Localizable.xcstrings";
writeFileSync(xcstringsPath, JSON.stringify(xcstrings, null, 2));

// --- 2. Generate Translations.swift ---
function escapeSwift(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

let swift = `// Auto-generated from en.ts — do not edit manually.
// Run: bun scripts/i18n-xcstrings.ts

import Foundation

enum Translations {
    private static let locale: String = UserDefaults.standard.string(forKey: "wimg_locale") ?? "de"

    private static let en: [String: String] = [
`;

for (const [de, enValue] of Object.entries(en)) {
  swift += `        "${escapeSwift(de)}": "${escapeSwift(enValue)}",\n`;
}

swift += `    ]

    /// Translate a German key. Returns English when locale is "en", German otherwise.
    static func t(_ key: String) -> String {
        if locale == "de" { return key }
        return en[key] ?? key
    }
}
`;

const swiftPath = "wimg-ios/wimg/Translations.swift";
writeFileSync(swiftPath, swift);

console.log(`Generated ${xcstringsPath} with ${Object.keys(strings).length} entries`);
console.log(`Generated ${swiftPath}`);
