import { describe, it, expect, beforeEach, vi } from "vitest";

// Mock localStorage
const storage: Record<string, string> = {};
vi.stubGlobal("localStorage", {
  getItem: (key: string) => storage[key] ?? null,
  setItem: (key: string, value: string) => {
    storage[key] = value;
  },
  removeItem: (key: string) => {
    delete storage[key];
  },
});

// We can't import the Svelte store directly (uses $state rune),
// so we test the pure logic by reimplementing releasesSince.
interface Release {
  tag: string;
  body: string;
}

function releasesSince(releases: Release[], version: string): Release[] {
  const tag = version.startsWith("v") ? version : `v${version}`;
  const idx = releases.findIndex((r) => r.tag === tag);
  if (idx === -1) {
    const lastTag = localStorage.getItem("wimg-last-version");
    if (lastTag) {
      const lastIdx = releases.findIndex((r) => r.tag === `v${lastTag}` || r.tag === lastTag);
      if (lastIdx !== -1) return releases.slice(0, lastIdx);
    }
    return releases.slice(0, 3);
  }
  return releases.slice(0, Math.max(idx, 1));
}

const MOCK_RELEASES: Release[] = [
  { tag: "v0.6.2", body: "feat: new feature" },
  { tag: "v0.6.1", body: "fix: bug fix" },
  { tag: "v0.6.0", body: "feat: big release" },
  { tag: "v0.5.23", body: "fix: small fix" },
  { tag: "v0.5.22", body: "feat: another feature" },
];

describe("releasesSince", () => {
  beforeEach(() => {
    for (const key of Object.keys(storage)) delete storage[key];
  });

  it("returns releases newer than current version", () => {
    const result = releasesSince(MOCK_RELEASES, "0.6.0");
    expect(result.map((r) => r.tag)).toEqual(["v0.6.2", "v0.6.1"]);
  });

  it("returns at least current release when version is latest (idx 0)", () => {
    const result = releasesSince(MOCK_RELEASES, "0.6.2");
    expect(result.length).toBe(1);
    expect(result[0].tag).toBe("v0.6.2");
  });

  it("returns all newer releases for old version", () => {
    const result = releasesSince(MOCK_RELEASES, "0.5.22");
    expect(result.length).toBe(4);
  });

  it("falls back to localStorage last-version when tag not found", () => {
    storage["wimg-last-version"] = "0.5.23";
    const result = releasesSince(MOCK_RELEASES, "0.7.0");
    // Should return everything before v0.5.23 (idx 3)
    expect(result.map((r) => r.tag)).toEqual(["v0.6.2", "v0.6.1", "v0.6.0"]);
  });

  it("falls back to latest 3 when no reference point", () => {
    const result = releasesSince(MOCK_RELEASES, "0.7.0");
    expect(result.length).toBe(3);
  });

  it("handles v-prefixed input", () => {
    const result = releasesSince(MOCK_RELEASES, "v0.6.0");
    expect(result.map((r) => r.tag)).toEqual(["v0.6.2", "v0.6.1"]);
  });
});
