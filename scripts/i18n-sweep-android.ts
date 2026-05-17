/**
 * One-shot sweep that migrates Android source to use `L(...)` from
 * `com.wimg.app.i18n.Translations`. Idempotent — safe to re-run.
 *
 * Handles:
 *   Text("German known-key")              → Text(L("German known-key"))
 *   TText("German known-key", …)          → Text(L("German known-key"), …)
 *   TText(variable, …)                    → Text(L(variable), …)
 *   stringResource(R.string.foo)          → left alone (not used in this app)
 *
 * Adds `import com.wimg.app.i18n.L` when any change is made.
 *
 * Does NOT touch:
 *   - Text("…\$x…") with interpolation — pre-formatted strings, no useful key
 *   - Literals not in `en.ts` (presumed identifiers / dev-only)
 *
 * Usage: bun scripts/i18n-sweep-android.ts
 */
import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";
import { en } from "../wimg-web/src/lib/translations/en";

const ROOT = "wimg-android/app/src/main/java/com/wimg/app";
const SKIP_FILES = new Set(["Translations.kt"]);
const KNOWN_KEYS = new Set(Object.keys(en));

interface Stats {
  filesChanged: number;
  textLiteral: number;
  ttextLiteral: number;
  ttextVar: number;
  skippedInterpolation: number;
}

const stats: Stats = {
  filesChanged: 0,
  textLiteral: 0,
  ttextLiteral: 0,
  ttextVar: 0,
  skippedInterpolation: 0,
};

function transform(source: string): { code: string; changed: boolean } {
  let s = source;
  let changed = false;

  // 1. TText("X", …) → Text(L("X"), …)  — literal form. TText was already
  //    an explicit i18n opt-in, so wrap unconditionally even if the key isn't
  //    yet in en.ts (runtime fallback returns the German verbatim).
  s = s.replace(
    /\bTText\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*,/g,
    (_m, key) => {
      stats.ttextLiteral++;
      changed = true;
      return `Text(L("${key}"),`;
    },
  );
  s = s.replace(
    /\bTText\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*\)/g,
    (_m, key) => {
      stats.ttextLiteral++;
      changed = true;
      return `Text(L("${key}"))`;
    },
  );

  // 2. TText(variable, …) → Text(L(variable), …)
  s = s.replace(
    /\bTText\(\s*([a-zA-Z_][\w.]*)\s*,/g,
    (_m, expr) => {
      stats.ttextVar++;
      changed = true;
      return `Text(L(${expr}),`;
    },
  );
  s = s.replace(
    /\bTText\(\s*([a-zA-Z_][\w.]*)\s*\)/g,
    (_m, expr) => {
      stats.ttextVar++;
      changed = true;
      return `Text(L(${expr}))`;
    },
  );

  // 3. Text("X") → Text(L("X"))  — pure literal, no $ interpolation
  s = s.replace(
    /\bText\(\s*"([^"\\$]*(?:\\.[^"\\$]*)*)"\s*\)/g,
    (m, key) => {
      if (!KNOWN_KEYS.has(key)) return m;
      stats.textLiteral++;
      changed = true;
      return `Text(L("${key}"))`;
    },
  );

  // 4. Text("X", …) variants with trailing args
  s = s.replace(
    /\bText\(\s*"([^"\\$]*(?:\\.[^"\\$]*)*)"\s*,/g,
    (m, key) => {
      if (!KNOWN_KEYS.has(key)) return m;
      stats.textLiteral++;
      changed = true;
      return `Text(L("${key}"),`;
    },
  );

  // Count interpolation skips for report
  for (const _ of source.matchAll(/Text\("[^"]*\$\{/g)) stats.skippedInterpolation++;

  return { code: s, changed };
}

function ensureImport(source: string): string {
  if (source.includes("com.wimg.app.i18n.L")) return source;
  // Insert after package + first block of imports.
  const lines = source.split("\n");
  let lastImportIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/^import\s+\w/.test(lines[i])) lastImportIdx = i;
  }
  if (lastImportIdx === -1) {
    // No imports yet; insert after `package` line.
    const pkgIdx = lines.findIndex((l) => /^package\s+/.test(l));
    if (pkgIdx === -1) return `import com.wimg.app.i18n.L\n${source}`;
    lines.splice(pkgIdx + 1, 0, "", "import com.wimg.app.i18n.L");
    return lines.join("\n");
  }
  lines.splice(lastImportIdx + 1, 0, "import com.wimg.app.i18n.L");
  return lines.join("\n");
}

function walk(dir: string, files: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      walk(path, files);
    } else if (extname(path) === ".kt" && !SKIP_FILES.has(entry)) {
      files.push(path);
    }
  }
  return files;
}

const ktFiles = walk(ROOT);
for (const file of ktFiles) {
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
console.log(`  TText("…") → Text(L):     ${stats.ttextLiteral}`);
console.log(`  TText(expr) → Text(L):    ${stats.ttextVar}`);
console.log(`  Text with $-interp skipped: ${stats.skippedInterpolation}`);
