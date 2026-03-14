import { GITHUB_RELEASES_API, LS_CHANGELOG } from "./config";

interface Release {
  tag: string;
  title: string;
  body: string;
  date: string;
}

interface CacheEntry {
  releases: Release[];
  fetchedAt: number;
}

const CACHE_TTL = 60 * 60 * 1000; // 1 hour

function loadCache(): CacheEntry | null {
  try {
    const stored = localStorage.getItem(LS_CHANGELOG);
    if (stored) return JSON.parse(stored) as CacheEntry;
  } catch {
    // ignore
  }
  return null;
}

function saveCache(releases: Release[]) {
  localStorage.setItem(LS_CHANGELOG, JSON.stringify({ releases, fetchedAt: Date.now() }));
}

class ChangelogStore {
  #releases = $state<Release[]>([]);
  #loading = $state(false);
  #error = $state(false);

  get releases() {
    return this.#releases;
  }

  get loading() {
    return this.#loading;
  }

  get error() {
    return this.#error;
  }

  /** Returns all releases newer than the given version (e.g. "0.5.10") */
  releasesSince(version: string): Release[] {
    const tag = version.startsWith("v") ? version : `v${version}`;
    const idx = this.#releases.findIndex((r) => r.tag === tag);
    if (idx === -1) {
      // Current version not in GitHub releases yet (unreleased build).
      // Fall back to last known version from localStorage.
      const lastTag = localStorage.getItem("wimg-last-version");
      if (lastTag) {
        const lastIdx = this.#releases.findIndex(
          (r) => r.tag === `v${lastTag}` || r.tag === lastTag,
        );
        if (lastIdx !== -1) return this.#releases.slice(0, lastIdx);
      }
      // No reference point — show latest 3 releases as context
      return this.#releases.slice(0, 3);
    }
    // Return everything before the current version (releases are newest-first)
    return this.#releases.slice(0, idx);
  }

  async load() {
    const cache = loadCache();

    if (cache && Date.now() - cache.fetchedAt < CACHE_TTL) {
      this.#releases = cache.releases;
      return;
    }

    // Show cached data while fetching
    if (cache) this.#releases = cache.releases;

    this.#loading = true;
    this.#error = false;

    try {
      const res = await fetch(GITHUB_RELEASES_API);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      const data = await res.json();
      const releases: Release[] = data.map(
        (r: { tag_name: string; name: string; body: string; published_at: string }) => ({
          tag: r.tag_name,
          title: r.name || r.tag_name,
          body: r.body || "",
          date: r.published_at,
        }),
      );

      this.#releases = releases;
      saveCache(releases);
    } catch {
      this.#error = true;
      // Keep showing cached data if available
    } finally {
      this.#loading = false;
    }
  }
}

export const changelogStore = new ChangelogStore();
