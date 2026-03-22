/**
 * wimg i18n Vite plugin — compile-time string replacement.
 *
 * Handles TWO scopes in .svelte files:
 *
 * 1. TEMPLATE: Text nodes + translatable attributes (placeholder, title, aria-label, alt)
 *    → `>German text<` becomes `>{__t$("German text")}<`
 *
 * 2. SCRIPT: String literals inside object property values (label, description, title, q, a, subtitle, text)
 *    → `label: "Schulden"` becomes `label: __t$("Schulden")`
 *    Does NOT touch: variable assignments, function args, SQL, imports, conditions
 *
 * Source stays German. The plugin handles the rest.
 */
import { parse } from "svelte/compiler";
import MagicString from "magic-string";
import type { Plugin } from "vite";

/** Template attributes worth translating */
const I18N_ATTRS = new Set(["placeholder", "title", "aria-label", "alt"]);

/** Object property names to wrap when accessed in template expressions like {item.label} */
const I18N_EXPR_PROPS = new Set([
  "name",
  "label",
  "description",
  "title",
  "q",
  "a",
  "subtitle",
  "text",
  "group",
]);

/** Minimum text length to consider */
const MIN_LENGTH = 2;

/** Strings to never translate */
const SKIP = new Set([
  "OK",
  "K",
  "CD",
  "TR",
  "SC",
  "wimg",
  "DevTools",
  "GitHub",
  "Claude",
  "MCP",
  "WASM",
  "SQLite",
  "OPFS",
  "CSV",
  "JSON",
  "NULL",
  "Home",
  "Import",
  "Sync",
  "Data",
  "Memory",
  "Icon",
  "Escape",
  "Bug",
  "Feedback",
  "Feature",
  "Fix",
  "Refactor",
  "Perf",
  "Docs",
  "Style",
  "Test",
  "Changelog",
  "Dashboard",
  "Total",
  "Details",
  "Offline",
]);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ASTNode = Record<string, any>;

function walkTemplate(node: ASTNode, visitor: (n: ASTNode) => void) {
  visitor(node);
  // Walk all child collections used in Svelte's AST
  for (const key of [
    "nodes",
    "fragment",
    "body",
    "consequent",
    "alternate",
    "pending",
    "then",
    "catch",
    "attributes",
  ]) {
    const child = node[key];
    if (Array.isArray(child)) {
      for (const c of child) if (c && typeof c === "object") walkTemplate(c, visitor);
    } else if (child && typeof child === "object" && child.type) {
      walkTemplate(child, visitor);
    }
  }
}

/** Walk an ESTree-like AST (for script blocks) */
function walkEstree(
  node: ASTNode,
  visitor: (n: ASTNode, parent?: ASTNode) => void,
  parent?: ASTNode,
) {
  if (!node || typeof node !== "object") return;
  visitor(node, parent);
  for (const key of Object.keys(node)) {
    const child = node[key];
    if (Array.isArray(child)) {
      for (const item of child) {
        if (item && typeof item === "object" && item.type) walkEstree(item, visitor, node);
      }
    } else if (child && typeof child === "object" && child.type) {
      walkEstree(child, visitor, node);
    }
  }
}

function isTranslatable(text: string): boolean {
  if (text.length < MIN_LENGTH) return false;
  if (SKIP.has(text)) return false;
  if (/^[\d.,:%€$+\-*/=<>()[\]{}|&!?@#^~`\\;'"]+$/.test(text)) return false;
  if (/^https?:\/\//.test(text)) return false;
  if (/^\/[a-z]/.test(text)) return false; // URL paths like /about
  // Skip lowercase identifiers, but NOT known German words
  const GERMAN_WORDS = new Set([
    "von",
    "und",
    "oder",
    "aus",
    "für",
    "mit",
    "bis",
    "bei",
    "nach",
    "gespart",
    "übrig",
    "erkannt",
    "erledigt",
    "gestiegen",
  ]);
  if (/^[a-z][\w-]*$/.test(text) && !GERMAN_WORDS.has(text)) return false;
  if (/^T\d|^\d+[a-z]/i.test(text)) return false; // date fragments like T00:00:00
  if (!/[a-zA-ZäöüÄÖÜß]/.test(text)) return false;
  return true;
}

function escapeQuotes(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

/** Transform script-level strings (shared between .svelte and .svelte.ts) */
function transformScript(scriptAst: ASTNode, code: string, s: MagicString): boolean {
  let replaced = false;
  walkEstree(scriptAst, (node: ASTNode, parent?: ASTNode) => {
    // String literals in return/argument/assignment/ternary contexts
    if (
      node.type === "Literal" &&
      typeof node.value === "string" &&
      isTranslatable(node.value) &&
      parent?.type !== "Property" &&
      parent?.type !== "ImportDeclaration" &&
      parent?.type !== "ImportExpression" &&
      parent?.type !== "BinaryExpression"
    ) {
      const text = node.value;
      if (/^SELECT |^DELETE |^INSERT |^UPDATE |^CREATE /i.test(text)) return;
      if (/^\.|^#|^--|^var\(/.test(text)) return;
      if (/^bg-|^text-|^opacity|^transform|^border/.test(text)) return;
      if (/^[a-z_][\w.]*$/i.test(text)) return;
      s.overwrite(node.start, node.end, `__t$("${escapeQuotes(text)}")`);
      replaced = true;
      return;
    }

    // Template literal quasis
    if (node.type === "TemplateLiteral" && node.quasis) {
      for (const quasi of node.quasis) {
        const raw = quasi.value?.raw || quasi.value?.cooked || "";
        const trimmed = raw.trim();
        if (!isTranslatable(trimmed)) continue;
        const key = trimmed.replace(/\s+/g, " ");
        const leadWs = raw.slice(0, raw.indexOf(trimmed.charAt(0)));
        const trailWs = raw.slice(raw.lastIndexOf(trimmed.charAt(trimmed.length - 1)) + 1);
        s.overwrite(quasi.start, quasi.end, `${leadWs}\${__t$("${escapeQuotes(key)}")}${trailWs}`);
        replaced = true;
      }
    }
  });
  return replaced;
}

export function i18nPlugin(): Plugin {
  return {
    name: "wimg-i18n",
    enforce: "pre",

    transform(code: string, id: string) {
      if (id.includes("node_modules")) return null;

      // --- .svelte.ts / .svelte.js files: script-only transform ---
      if (id.match(/\.svelte\.[tj]s$/) && !id.includes("i18n.svelte")) {
        // Parse as plain JS/TS with acorn (via Svelte's parser won't work for .ts)
        // Instead, use a simple regex-based approach to find the AST
        try {
          // Use Svelte's parse trick: wrap in a dummy component
          const prefix = '<script lang="ts">\n';
          const wrapped = `${prefix}${code}\n${"<"}${"/"}script>`;
          const ast = parse(wrapped, { modern: true, filename: "_.svelte" }) as unknown as ASTNode;
          if (!ast.instance) return null;

          const s = new MagicString(code);
          const offset = prefix.length;
          const scriptAst = ast.instance.content || ast.instance;

          // Walk and transform, adjusting positions by offset
          let replaced = false;
          walkEstree(scriptAst, (node: ASTNode, parent?: ASTNode) => {
            if (
              node.type === "Literal" &&
              typeof node.value === "string" &&
              isTranslatable(node.value) &&
              parent?.type !== "Property" &&
              parent?.type !== "ImportDeclaration" &&
              parent?.type !== "ImportExpression" &&
              parent?.type !== "BinaryExpression"
            ) {
              const text = node.value;
              if (/^SELECT |^DELETE |^INSERT |^UPDATE |^CREATE /i.test(text)) return;
              if (/^\.|^#|^--|^var\(/.test(text)) return;
              if (/^bg-|^text-|^opacity|^transform|^border/.test(text)) return;
              if (/^[a-z_][\w.]*$/i.test(text)) return;
              s.overwrite(node.start - offset, node.end - offset, `__t$("${escapeQuotes(text)}")`);
              replaced = true;
            }

            if (node.type === "TemplateLiteral" && node.quasis) {
              for (const quasi of node.quasis) {
                const raw = quasi.value?.raw || quasi.value?.cooked || "";
                const trimmed = raw.trim();
                if (!isTranslatable(trimmed)) continue;
                const key = trimmed.replace(/\s+/g, " ");
                const leadWs = raw.slice(0, raw.indexOf(trimmed.charAt(0)));
                const trailWs = raw.slice(raw.lastIndexOf(trimmed.charAt(trimmed.length - 1)) + 1);
                s.overwrite(
                  quasi.start - offset,
                  quasi.end - offset,
                  `${leadWs}\${__t$("${escapeQuotes(key)}")}${trailWs}`,
                );
                replaced = true;
              }
            }
          });

          if (!replaced) return null;

          // Inject import at top of file
          s.prepend(
            'import { i18n as __i18n$ } from "$lib/i18n.svelte";\nconst __t$ = __i18n$.$;\n',
          );

          return { code: s.toString(), map: s.generateMap({ hires: true }) };
        } catch {
          return null;
        }
      }

      if (!id.endsWith(".svelte")) return null;

      let ast: ASTNode;
      try {
        ast = parse(code, { modern: true }) as unknown as ASTNode;
      } catch {
        return null;
      }

      const s = new MagicString(code);
      let replaced = false;

      // --- 1. Template: Text nodes ---
      if (ast.fragment) {
        walkTemplate(ast.fragment, (node: ASTNode) => {
          if (node.type === "Text" && node.data) {
            const raw = node.data;
            const trimmed = raw.trim();
            if (!isTranslatable(trimmed)) return;
            const key = trimmed.replace(/\s+/g, " ");
            // Preserve leading/trailing whitespace (e.g. " Aktiv" after {count})
            const leadIdx = raw.indexOf(trimmed.charAt(0));
            const leadWs = raw.slice(0, leadIdx);
            const trailIdx = raw.lastIndexOf(trimmed.charAt(trimmed.length - 1)) + 1;
            const trailWs = raw.slice(trailIdx);
            s.overwrite(node.start, node.end, `${leadWs}{__t$("${escapeQuotes(key)}")}${trailWs}`);
            replaced = true;
          }

          // Template expressions: {cat.name}, {CATEGORIES[x]?.name}, ternaries with German strings
          if (node.type === "ExpressionTag" && node.expression) {
            const expr = code.slice(node.expression.start, node.expression.end);

            // {*.label}, {*.name}, {*.description} etc. → wrap with __t$
            const propMatch = expr.match(/\.(\w+)\s*(?:\?\?\s*"[^"]*"\s*)?$/);
            if (propMatch && I18N_EXPR_PROPS.has(propMatch[1])) {
              s.overwrite(node.start, node.end, `{__t$(${expr})}`);
              replaced = true;
              return; // skip further processing of this node
            }

            // String literals inside template expressions (ternaries, etc.)
            // e.g. {cond ? "Erkennung..." : "Erkennen"}
            walkEstree(node.expression, (n: ASTNode) => {
              if (n.type === "Literal" && typeof n.value === "string" && isTranslatable(n.value)) {
                s.overwrite(n.start, n.end, `__t$("${escapeQuotes(n.value)}")`);
                replaced = true;
              }
            });
          }

          if (node.type === "Attribute" && node.name && I18N_ATTRS.has(node.name)) {
            const val = node.value;
            if (!Array.isArray(val) || val.length !== 1) return;
            const textNode = val[0];
            if (textNode.type !== "Text" || !textNode.data) return;
            const text = textNode.data.trim();
            if (!isTranslatable(text)) return;
            const attrStr = code.slice(node.start, node.end);
            const eqIdx = attrStr.indexOf("=");
            if (eqIdx === -1) return;
            s.overwrite(node.start + eqIdx, node.end, `={__t$("${escapeQuotes(text)}")}`);
            replaced = true;
          }
        });
      }

      // --- 2. Script: translatable strings ---
      if (ast.instance) {
        const scriptAst = ast.instance.content || ast.instance;
        if (transformScript(scriptAst, code, s)) replaced = true;
      }

      if (!replaced) return null;

      // Inject import into <script> block (create one if missing)
      const scriptMatch = code.match(/<script[^>]*>/);
      if (scriptMatch) {
        const insertPos = scriptMatch.index! + scriptMatch[0].length;
        s.appendLeft(
          insertPos,
          `\n  import { i18n as __i18n$ } from "$lib/i18n.svelte";\n  const __t$ = __i18n$.$;\n`,
        );
      } else {
        s.prepend(
          `<script>\n  import { i18n as __i18n$ } from "$lib/i18n.svelte";\n  const __t$ = __i18n$.$;\n${"<"}/script>\n`,
        );
      }

      return {
        code: s.toString(),
        map: s.generateMap({ hires: true }),
      };
    },
  };
}
