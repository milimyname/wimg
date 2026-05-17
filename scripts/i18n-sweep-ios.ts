/**
 * One-shot sweep that migrates iOS source to use `#L(...)` / `L(...)` from
 * the WimgI18n package. Idempotent — safe to re-run.
 *
 * Handles:
 *   Text("German known-key")    → Text(#L("German known-key"))
 *   TText("German known-key")   → Text(#L("German known-key"))
 *   TText(variable)             → Text(L(variable))
 *   Label("X", systemImage: …)  → Label(#L("X"), systemImage: …)
 *   String(localized: "X")      → #L("X")
 *   Translations.t(x)           → L(x)
 *
 * Adds `import WimgI18n` after `import SwiftUI` when any change is made.
 *
 * Does NOT touch:
 *   - Text with interpolation (Text("\(x) Foo"))
 *   - RecurringPattern.isEnglish ternaries — those need manual collapse
 *   - Literals not in `en.ts` (presumed code identifiers / SF Symbols / etc.)
 *
 * Usage: bun scripts/i18n-sweep-ios.ts
 */
import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";
import { en } from "../wimg-web/src/lib/translations/en";

const ROOT = "wimg-ios/wimg";
const SKIP_FILES = new Set(["Translations.swift"]);
const KNOWN_KEYS = new Set(Object.keys(en));

interface Stats {
  filesChanged: number;
  textLiteral: number;
  ttextLiteral: number;
  ttextVar: number;
  labelLiteral: number;
  stringLocalized: number;
  translationsT: number;
  skippedInterpolation: number;
  skippedIsEnglish: number;
}

const stats: Stats = {
  filesChanged: 0,
  textLiteral: 0,
  ttextLiteral: 0,
  ttextVar: 0,
  labelLiteral: 0,
  stringLocalized: 0,
  translationsT: 0,
  skippedInterpolation: 0,
  skippedIsEnglish: 0,
};

function escapeSwift(s: string): string {
  return s;
}

/**
 * Apply transformations to a single Swift source string. Returns the new
 * source + whether any change was made.
 */
function transform(source: string): { code: string; changed: boolean } {
  let s = source;
  let changed = false;

  // 1. String(localized: "X") → #L("X")
  s = s.replace(
    /String\(localized:\s*"([^"\\]*(?:\\.[^"\\]*)*)"\)/g,
    (m, key) => {
      if (!KNOWN_KEYS.has(key)) return m;
      stats.stringLocalized++;
      changed = true;
      return `#L("${key}")`;
    },
  );

  // 2. TText("X") → Text(#L("X")) — string-literal form, no interpolation
  s = s.replace(
    /\bTText\("([^"\\]*(?:\\.[^"\\]*)*)"\)/g,
    (m, key) => {
      if (!KNOWN_KEYS.has(key)) return m;
      stats.ttextLiteral++;
      changed = true;
      return `Text(#L("${key}"))`;
    },
  );

  // 3. TText(expr) → Text(L(expr)) — non-string-literal form
  //    Match TText(...) where ... doesn't start with a double-quote.
  s = s.replace(
    /\bTText\(([^"][^)]*)\)/g,
    (m, expr) => {
      // Skip ternaries containing string literals — manual review needed.
      if (expr.includes('"')) {
        // Could be a `cond ? "A" : "B"` — best handled manually unless
        // both branches are known keys.
        const ternaryMatch = expr.match(/^([^?]+)\s*\?\s*"([^"]+)"\s*:\s*"([^"]+)"\s*$/);
        if (ternaryMatch) {
          const [, cond, a, b] = ternaryMatch;
          if (KNOWN_KEYS.has(a) && KNOWN_KEYS.has(b)) {
            stats.ttextVar++;
            changed = true;
            return `Text(${cond.trim()} ? #L("${a}") : #L("${b}"))`;
          }
        }
        return m;
      }
      stats.ttextVar++;
      changed = true;
      return `Text(L(${expr}))`;
    },
  );

  // 4. Text("X") → Text(#L("X")) — pure literal, no interpolation
  s = s.replace(
    /\bText\("([^"\\]*(?:\\.[^"\\]*)*)"\)/g,
    (m, key) => {
      if (key.includes("\\(")) return m; // handled by step 4b
      if (!KNOWN_KEYS.has(key)) return m;
      stats.textLiteral++;
      changed = true;
      return `Text(#L("${key}"))`;
    },
  );

  // 4b. Text("...\(x)...") → Text(#L("...\(x)..."))
  //     Wraps interpolated literals only if the German text portion contains
  //     letters — skips pure number/percent formatting like Text("\(pct)%").
  s = s.replace(
    /\bText\("((?:[^"\\]|\\.|\\\([^)]*\))*)"\)/g,
    (m, raw) => {
      if (!raw.includes("\\(")) return m; // step 4 handles literals
      // Strip all interpolation segments to check the static text portion.
      const stripped = raw.replace(/\\\([^)]*\)/g, "");
      // Require at least one German-ish letter outside the interpolations.
      if (!/[a-zA-ZäöüÄÖÜß]/.test(stripped)) return m;
      // Skip if all the static text is punctuation/symbols.
      if (!/[a-zA-ZäöüÄÖÜß]{2,}/.test(stripped)) return m;
      stats.textLiteral++;
      changed = true;
      return `Text(#L("${raw}"))`;
    },
  );

  // 5. Label("X", systemImage: …) → Label(#L("X"), systemImage: …)
  s = s.replace(
    /\bLabel\("([^"\\]*(?:\\.[^"\\]*)*)",\s*systemImage:/g,
    (m, key) => {
      if (!KNOWN_KEYS.has(key)) return m;
      stats.labelLiteral++;
      changed = true;
      return `Label(#L("${key}"), systemImage:`;
    },
  );

  // 6. Translations.t(x) → L(x)
  s = s.replace(/\bTranslations\.t\(([^)]+)\)/g, (m, arg) => {
    stats.translationsT++;
    changed = true;
    return `L(${arg})`;
  });

  // 7. SwiftUI modifier strings — these previously auto-localized via the
  //    `.xcstrings` catalog; now we wrap with #L so the runtime table
  //    resolves them.
  const modifierWrap = (key: string): boolean => {
    // Same shape as Text(): only wrap if it has German content or is known.
    if (key.includes("\\(")) {
      const stripped = key.replace(/\\\([^)]*\)/g, "");
      return /[a-zA-ZäöüÄÖÜß]{2,}/.test(stripped);
    }
    return KNOWN_KEYS.has(key);
  };

  // .navigationTitle("X") / .navigationTitle("\(x) Y")
  s = s.replace(
    /\.navigationTitle\("((?:[^"\\]|\\.|\\\([^)]*\))*)"\)/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `.navigationTitle(#L("${raw}"))`;
    },
  );

  // .searchable(text: $x, prompt: "X")
  s = s.replace(
    /(searchable\([^)]*?prompt:\s*)"((?:[^"\\]|\\.|\\\([^)]*\))*)"/g,
    (m, prefix, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `${prefix}#L("${raw}")`;
    },
  );

  // .alert("X", …)
  s = s.replace(
    /\.alert\("((?:[^"\\]|\\.|\\\([^)]*\))*)"/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `.alert(#L("${raw}")`;
    },
  );

  // Button("X") and Button("X", role: …) — the first unlabeled argument.
  s = s.replace(
    /\bButton\("((?:[^"\\]|\\.|\\\([^)]*\))*)"(\s*[,)])/g,
    (m, raw, tail) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `Button(#L("${raw}")${tail}`;
    },
  );

  // InfoTooltip(text: "X")
  s = s.replace(
    /InfoTooltip\(text:\s*"((?:[^"\\]|\\.|\\\([^)]*\))*)"\)/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `InfoTooltip(text: #L("${raw}"))`;
    },
  );

  // actionButton("X", …) — local helper in SearchView
  s = s.replace(
    /\bactionButton\("((?:[^"\\]|\\.|\\\([^)]*\))*)",/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `actionButton(#L("${raw}"),`;
    },
  );

  // TextField("X", text: …) — placeholder is the first unlabeled arg.
  s = s.replace(
    /\bTextField\("((?:[^"\\]|\\.|\\\([^)]*\))*)",/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `TextField(#L("${raw}"),`;
    },
  );

  // .confirmationDialog("X", …)
  s = s.replace(
    /\.confirmationDialog\(\s*"((?:[^"\\]|\\.|\\\([^)]*\))*)",/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `.confirmationDialog(#L("${raw}"),`;
    },
  );

  // Picker("X", selection: …) and DatePicker("X", …) — first unlabeled arg.
  s = s.replace(
    /\b(DatePicker|Picker)\("((?:[^"\\]|\\.|\\\([^)]*\))*)",/g,
    (m, callee, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `${callee}(#L("${raw}"),`;
    },
  );

  // Section("X") { … }  — Form/List section header.
  s = s.replace(
    /\bSection\("((?:[^"\\]|\\.|\\\([^)]*\))*)"\)\s*\{/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `Section(#L("${raw}")) {`;
    },
  );

  // actionSection("X") { … } — local helper in SearchView
  s = s.replace(
    /\bactionSection\("((?:[^"\\]|\\.|\\\([^)]*\))*)"\)\s*\{/g,
    (m, raw) => {
      if (!modifierWrap(raw)) return m;
      stats.textLiteral++;
      changed = true;
      return `actionSection(#L("${raw}")) {`;
    },
  );

  // 7. Detect skipped sites for report
  for (const match of source.matchAll(/Text\("([^"]*\\\([^)]+\)[^"]*)"\)/g)) {
    if (match[1].includes("\\(")) stats.skippedInterpolation++;
  }
  for (const _ of source.matchAll(/RecurringPattern\.isEnglish/g)) {
    stats.skippedIsEnglish++;
  }

  return { code: s, changed };
}

function ensureImport(source: string): string {
  if (source.includes("import WimgI18n")) return source;
  // Insert after the last `import SwiftUI` line.
  const lines = source.split("\n");
  let lastImportIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/^import\s+\w/.test(lines[i])) lastImportIdx = i;
  }
  if (lastImportIdx === -1) return `import WimgI18n\n${source}`;
  lines.splice(lastImportIdx + 1, 0, "import WimgI18n");
  return lines.join("\n");
}

function walk(dir: string, files: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      walk(path, files);
    } else if (extname(path) === ".swift" && !SKIP_FILES.has(entry)) {
      files.push(path);
    }
  }
  return files;
}

const swiftFiles = walk(ROOT);
for (const file of swiftFiles) {
  const original = readFileSync(file, "utf8");
  const { code, changed } = transform(original);
  if (!changed) continue;
  const final = ensureImport(code);
  writeFileSync(file, final);
  stats.filesChanged++;
  console.log(`  ${file}`);
}

console.log(`\nDone. ${stats.filesChanged} files changed.`);
console.log(`  Text("…") wrapped:        ${stats.textLiteral}`);
console.log(`  TText("…") → Text(#L):    ${stats.ttextLiteral}`);
console.log(`  TText(expr) → Text(L):    ${stats.ttextVar}`);
console.log(`  Label("…", systemImage:): ${stats.labelLiteral}`);
console.log(`  String(localized:):       ${stats.stringLocalized}`);
console.log(`  Translations.t(x):        ${stats.translationsT}`);
console.log(`\nSkipped (needs manual review):`);
console.log(`  Text(...) with interpolation: ${stats.skippedInterpolation}`);
console.log(`  RecurringPattern.isEnglish:   ${stats.skippedIsEnglish}`);
