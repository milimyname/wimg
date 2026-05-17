/**
 * libwimg WASM loader for Cloudflare Workers.
 *
 * Surfaces only what wimg-sync actually uses today:
 *   - Lifecycle: `WasmInstance.create()`, `close()`
 *   - Read:      `query(sql)`        — raw SQL for the Code Mode `query` tool
 *   - Write:     `setCategory(...)`  — the only mutation exposed via MCP
 *   - Sync:      `applyChanges`, `getChanges`, `decryptRows` (pull + push paths in McpSession)
 *   - Crypto:    `deriveEncryptionKey`, `encryptField`, `decryptField`
 *   - Metadata:  `categories` (loaded once from `wimg_get_categories` at init)
 *
 * Other libwimg exports (get_transactions/get_summary/get_accounts/get_recurring/
 * undo/redo/etc.) used to be needed by the old 14-tool MCP surface and are
 * intentionally not wrapped here. Code Mode composes any read access via `query`
 * over the SQLite tables those exports used to wrap.
 */

// Cloudflare bundles .wasm files as WebAssembly.Module via [[rules]]
// Uses compact build (smaller memory buffers) to fit CF Workers 128MB limit.
import wasmModule from "../libwimg-compact.wasm";

// --- Types ---

export interface CategoryInfo {
  id: number;
  name: string;
  color: string;
  icon: string;
}

export interface SyncRow {
  table: string;
  id: string;
  data: Record<string, unknown> | string;
  updated_at: number;
}

export interface QueryResult {
  columns: string[];
  rows: unknown[][];
  count: number;
  truncated: boolean;
}

interface WasmExports {
  memory: WebAssembly.Memory;

  // Lifecycle
  wimg_init: (path: number) => number;
  wimg_close: () => void;
  wimg_free: (ptr: number, len: number) => void;
  wimg_alloc: (size: number) => number;
  wimg_get_error: () => number;

  // Metadata (called once at init)
  wimg_get_categories: () => number;

  // The only write tool
  wimg_set_category: (id: number, id_len: number, category: number) => number;

  // Sync — pull + push paths in McpSession
  wimg_get_changes: (since_ts: bigint) => number;
  wimg_apply_changes: (data: number, len: number) => number;

  // E2E encryption
  wimg_derive_key: (sync_key: number, sync_key_len: number) => number;
  wimg_encrypt_field: (pt: number, pt_len: number, key: number, nonce: number) => number;
  wimg_decrypt_field: (ct: number, ct_len: number, key: number) => number;

  // Raw SQL — backs the Code Mode `query` tool
  wimg_query: (sql: number, sql_len: number) => number;
}

// --- WasmInstance ---

export class WasmInstance {
  private wasm: WasmExports;
  categories: Record<number, CategoryInfo> = {};

  private constructor(wasm: WasmExports) {
    this.wasm = wasm;
  }

  static async create(): Promise<WasmInstance> {
    let resultExports: WasmExports;

    const importObject: Record<string, Record<string, unknown>> = {
      env: {
        js_console_log: (ptr: number, len: number) => {
          try {
            const mem = new Uint8Array(resultExports.memory.buffer);
            const msg = new TextDecoder().decode(mem.slice(ptr, ptr + len));
            console.log("[wimg-wasm]", msg);
          } catch {
            // ignore
          }
        },
        js_time_ms: () => BigInt(Date.now()),
      },
    };

    // Fill in any other imports the WASM declares with no-op stubs.
    const neededImports = WebAssembly.Module.imports(wasmModule);
    for (const imp of neededImports) {
      if (!importObject[imp.module]) importObject[imp.module] = {};
      if (!(imp.name in importObject[imp.module])) {
        if (imp.kind === "function") {
          importObject[imp.module][imp.name] = () => 0;
        }
      }
    }

    const instance = await WebAssembly.instantiate(wasmModule, importObject as WebAssembly.Imports);
    resultExports = instance.exports as unknown as WasmExports;

    const w = new WasmInstance(resultExports);

    // Init database (in-memory VFS path doesn't actually touch disk in WASM)
    const pathPtr = w.writeString("/mcp.db");
    const rc = resultExports.wimg_init(pathPtr);
    if (rc !== 0) {
      throw new Error(w.getLastError("Failed to initialize wimg database"));
    }

    // Load categories (static Zig-side constants — not a SQLite table)
    const catPtr = resultExports.wimg_get_categories();
    if (catPtr !== 0) {
      const catJson = w.readLengthPrefixedString(catPtr);
      resultExports.wimg_free(catPtr, 0);
      const catArray = JSON.parse(catJson) as CategoryInfo[];
      for (const cat of catArray) {
        w.categories[cat.id] = cat;
      }
    }

    return w;
  }

  // --- Internal helpers ---

  private readLengthPrefixedString(ptr: number): string {
    const mem = new Uint8Array(this.wasm.memory.buffer);
    const len = mem[ptr] | (mem[ptr + 1] << 8) | (mem[ptr + 2] << 16) | (mem[ptr + 3] << 24);
    return new TextDecoder().decode(mem.slice(ptr + 4, ptr + 4 + len));
  }

  private getLastError(fallback: string): string {
    try {
      const ptr = this.wasm.wimg_get_error();
      if (ptr !== 0) return this.readLengthPrefixedString(ptr);
    } catch {
      // ignore
    }
    return fallback;
  }

  private writeString(s: string): number {
    const encoded = new TextEncoder().encode(s + "\0");
    const ptr = this.wasm.wimg_alloc(encoded.length);
    if (ptr === 0) throw new Error("WASM allocation failed");
    const mem = new Uint8Array(this.wasm.memory.buffer);
    mem.set(encoded, ptr);
    return ptr;
  }

  private writeBytes(data: Uint8Array): number {
    const ptr = this.wasm.wimg_alloc(data.length);
    if (ptr === 0) throw new Error("WASM allocation failed");
    const mem = new Uint8Array(this.wasm.memory.buffer);
    mem.set(data, ptr);
    return ptr;
  }

  // --- Public API ---

  /**
   * Run arbitrary SQL via libwimg's `wimg_query` C ABI.
   * Caller is responsible for any safety enforcement (read-only, etc).
   * Result shape: `{ columns, rows, count, truncated }`.
   */
  query(sql: string): QueryResult {
    const encoded = new TextEncoder().encode(sql);
    const ptr = this.writeBytes(encoded);
    const resultPtr = this.wasm.wimg_query(ptr, encoded.length);
    if (resultPtr === 0) {
      throw new Error(this.getLastError("wimg_query: failed"));
    }
    const json = this.readLengthPrefixedString(resultPtr);
    this.wasm.wimg_free(resultPtr, 0);
    return JSON.parse(json) as QueryResult;
  }

  setCategory(id: string, category: number): void {
    const idPtr = this.writeString(id);
    const rc = this.wasm.wimg_set_category(idPtr, id.length, category);
    if (rc !== 0) throw new Error(this.getLastError("Failed to set category"));
  }

  // --- Sync ---

  getChanges(sinceTs: number): SyncRow[] {
    const ptr = this.wasm.wimg_get_changes(BigInt(sinceTs));
    if (ptr === 0) return [];
    const json = this.readLengthPrefixedString(ptr);
    this.wasm.wimg_free(ptr, 0);
    const result = JSON.parse(json) as { rows: SyncRow[] };
    return result.rows;
  }

  applyChanges(rows: SyncRow[]): number {
    const json = JSON.stringify({ rows });
    const encoded = new TextEncoder().encode(json);
    const ptr = this.writeBytes(encoded);
    const rc = this.wasm.wimg_apply_changes(ptr, encoded.length);
    if (rc < 0) throw new Error(this.getLastError("Failed to apply sync changes"));
    return rc;
  }

  decryptRows(rows: SyncRow[], key: Uint8Array): SyncRow[] {
    return rows.map((row) => {
      if (typeof row.data === "string") {
        const plaintext = this.decryptField(row.data, key);
        return { ...row, data: JSON.parse(plaintext) as Record<string, unknown> };
      }
      return row;
    });
  }

  // --- E2E encryption ---

  deriveEncryptionKey(syncKey: string): Uint8Array {
    const encoded = new TextEncoder().encode(syncKey);
    const ptr = this.writeBytes(encoded);
    const resultPtr = this.wasm.wimg_derive_key(ptr, encoded.length);
    if (resultPtr === 0) throw new Error(this.getLastError("Failed to derive encryption key"));
    const mem = new Uint8Array(this.wasm.memory.buffer);
    const len =
      mem[resultPtr] |
      (mem[resultPtr + 1] << 8) |
      (mem[resultPtr + 2] << 16) |
      (mem[resultPtr + 3] << 24);
    const key = new Uint8Array(len);
    key.set(mem.slice(resultPtr + 4, resultPtr + 4 + len));
    this.wasm.wimg_free(resultPtr, 0);
    return key;
  }

  encryptField(plaintext: string, key: Uint8Array): string {
    const ptEncoded = new TextEncoder().encode(plaintext);
    const ptPtr = this.writeBytes(ptEncoded);
    const keyPtr = this.writeBytes(key);
    const nonce = crypto.getRandomValues(new Uint8Array(24));
    const noncePtr = this.writeBytes(nonce);
    const resultPtr = this.wasm.wimg_encrypt_field(ptPtr, ptEncoded.length, keyPtr, noncePtr);
    if (resultPtr === 0) throw new Error(this.getLastError("Encryption failed"));
    const result = this.readLengthPrefixedString(resultPtr);
    this.wasm.wimg_free(resultPtr, 0);
    return result;
  }

  decryptField(ciphertext: string, key: Uint8Array): string {
    const ctEncoded = new TextEncoder().encode(ciphertext);
    const ctPtr = this.writeBytes(ctEncoded);
    const keyPtr = this.writeBytes(key);
    const resultPtr = this.wasm.wimg_decrypt_field(ctPtr, ctEncoded.length, keyPtr);
    if (resultPtr === 0) throw new Error(this.getLastError("Decryption failed"));
    const result = this.readLengthPrefixedString(resultPtr);
    this.wasm.wimg_free(resultPtr, 0);
    return result;
  }

  close(): void {
    this.wasm.wimg_close();
  }
}
