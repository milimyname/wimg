/**
 * code-runner.ts — Cloudflare-bound boundary for Code Mode.
 *
 * Only file in wimg-sync that imports `@cloudflare/codemode`. Wraps an upstream
 * MCP server with the Code Mode `code` tool, executing LLM-generated TypeScript
 * inside a Dynamic Worker isolate.
 *
 * If you ever move off Cloudflare Workers (deno deploy, node, etc.), this is
 * the only file that needs to be replaced. The upstream tool surface in
 * `mcp-tools.ts` and the WASM binding in `mcp-wasm.ts` are portable.
 */

import { DynamicWorkerExecutor } from "@cloudflare/codemode";
import { codeMcpServer } from "@cloudflare/codemode/mcp";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

export interface WrapWithCodeModeOptions {
  /** Upstream McpServer with all wimg tools already registered. */
  server: McpServer;
  /** The `LOADER` binding from wrangler.toml's `worker_loaders`. */
  loader: WorkerLoader;
  /** Optional sandbox timeout in ms (default 30s). */
  timeoutMs?: number;
}

/**
 * Wrap the upstream MCP server with a single `code` tool that runs LLM-written
 * TypeScript in an isolated Worker.
 *
 * Sandbox guarantees (from `DynamicWorkerExecutor` defaults):
 * - No file system access
 * - No environment variables
 * - `fetch()` and `connect()` throw (no outbound network)
 * - Tool calls dispatched back to upstream handlers via Workers RPC
 *
 * Writes performed by sandboxed code reach `mcp-tools.ts` handlers
 * unchanged, so the `onWrite` callback configured on the upstream server
 * still fires and the DO can coalesce push-back-to-sync as usual.
 */
export async function wrapWithCodeMode(options: WrapWithCodeModeOptions): Promise<McpServer> {
  const executor = new DynamicWorkerExecutor({
    loader: options.loader,
    timeout: options.timeoutMs ?? 30_000,
    // globalOutbound: null is the default — sandbox cannot reach external network.
  });
  return await codeMcpServer({ server: options.server, executor });
}
