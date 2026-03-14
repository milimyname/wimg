<script lang="ts">
  import { onMount } from "svelte";
  import { changelogStore } from "$lib/changelog.svelte";
  import { APP_VERSION } from "$lib/version";
  import { RELEASES_URL } from "$lib/config";

  onMount(() => {
    changelogStore.load();
  });

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString("de-DE", {
      day: "numeric",
      month: "short",
      year: "numeric",
    });
  }

  interface ChangeItem {
    type: string;
    text: string;
  }

  const TYPE_BADGES: Record<string, { label: string; class: string }> = {
    feat: { label: "Feature", class: "bg-emerald-100 text-emerald-700" },
    fix: { label: "Fix", class: "bg-rose-100 text-rose-600" },
    refactor: { label: "Refactor", class: "bg-sky-100 text-sky-700" },
    perf: { label: "Perf", class: "bg-amber-100 text-amber-700" },
    docs: { label: "Docs", class: "bg-slate-100 text-slate-600" },
    style: { label: "Style", class: "bg-purple-100 text-purple-600" },
    test: { label: "Test", class: "bg-indigo-100 text-indigo-600" },
  };

  function parseItems(body: string): ChangeItem[] {
    return body
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0)
      .filter((l) => !l.match(/^release:\s*v[\d.]+$/i))
      .filter((l) => !l.match(/^#{1,3}\s/))
      .map((l) => l.replace(/^[-*]\s*/, "").trim())
      .filter((l) => l.length > 0)
      .map((l) => {
        const match = l.match(/^(feat|fix|refactor|perf|docs|style|test)(?:\(.+?\))?:\s*(.+)$/i);
        if (match) {
          return { type: match[1].toLowerCase(), text: match[2].trim() };
        }
        return { type: "", text: l };
      });
  }

  function getBadge(type: string) {
    return TYPE_BADGES[type] ?? null;
  }
</script>

<main class="min-h-screen bg-(--color-bg)">
  <div class="max-w-lg mx-auto px-6 py-12 flex flex-col gap-8">
    <!-- Header -->
    <header class="space-y-2">
      <div class="flex items-center justify-between">
        <h1
          class="text-3xl font-display font-extrabold tracking-tight text-(--color-text)"
        >
          Was ist neu?
        </h1>
        <a
          href="/home"
          class="text-sm font-bold text-(--color-text-secondary) hover:text-(--color-text) transition-colors"
        >
          Zur App &rarr;
        </a>
      </div>
      <p class="text-(--color-text-secondary) text-lg">
        Die neuesten Updates für wimg
      </p>
    </header>

    {#if changelogStore.loading && changelogStore.releases.length === 0}
      <!-- Skeleton -->
      <div class="flex flex-col gap-4">
        {#each { length: 3 } as _}
          <div
            class="bg-white p-6 rounded-3xl shadow-[var(--shadow-card)] border border-(--color-border) animate-pulse"
          >
            <div class="flex items-center justify-between mb-4">
              <div class="w-16 h-6 bg-gray-200 rounded-full"></div>
              <div class="w-20 h-4 bg-gray-100 rounded"></div>
            </div>
            <div class="space-y-3">
              <div class="w-full h-4 bg-gray-100 rounded"></div>
              <div class="w-4/5 h-4 bg-gray-100 rounded"></div>
            </div>
          </div>
        {/each}
      </div>
    {:else if changelogStore.releases.length > 0}
      <!-- Release cards -->
      <section class="flex flex-col gap-4">
        {#each changelogStore.releases as release, i}
          {@const isCurrent = release.tag === `v${APP_VERSION}`}
          {@const items = parseItems(release.body)}

          <article
            class="bg-white p-6 rounded-3xl shadow-[var(--shadow-card)] border border-(--color-border) flex flex-col gap-4 {i >
            4
              ? 'opacity-70'
              : ''}"
          >
            <!-- Version + date -->
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span
                  class="text-xs font-bold px-3 py-1 rounded-full {isCurrent
                    ? 'bg-violet-100 text-violet-700'
                    : 'bg-(--color-primary-light) text-(--color-text-secondary)'}"
                >
                  {release.tag}
                </span>
                {#if isCurrent}
                  <span class="w-2 h-2 rounded-full bg-violet-500 animate-pulse"
                  ></span>
                {/if}
              </div>
              <time class="text-sm text-(--color-text-secondary)"
                >{formatDate(release.date)}</time
              >
            </div>

            <!-- Feature list -->
            {#if items.length > 0}
              <div class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-2 items-baseline">
                {#each items as item}
                  {@const badge = getBadge(item.type)}
                  {#if badge}
                    <span
                      class="text-[10px] font-bold px-2 py-0.5 rounded-md text-center min-w-[4rem] {badge.class}"
                    >
                      {badge.label}
                    </span>
                  {:else}
                    <span class="flex items-center justify-center min-w-[4rem]">
                      <span class="w-1.5 h-1.5 rounded-full bg-(--color-text-secondary)/30"></span>
                    </span>
                  {/if}
                  <p
                    class="text-sm font-medium text-(--color-text) leading-relaxed"
                  >
                    {item.text}
                  </p>
                {/each}
              </div>
            {:else}
              <p class="text-sm text-(--color-text-secondary) italic">
                Wartungsrelease.
              </p>
            {/if}
          </article>
        {/each}
      </section>

      <!-- Footer -->
      <footer class="flex flex-col items-center gap-4 mt-4">
        <a
          href="/home"
          class="w-full bg-(--color-accent) hover:bg-(--color-accent-hover) text-(--color-text) font-display font-extrabold py-4 rounded-2xl transition-colors shadow-[var(--shadow-card)] text-center"
        >
          Verstanden!
        </a>
        <a
          href={RELEASES_URL}
          target="_blank"
          rel="noopener noreferrer"
          class="text-(--color-text-secondary) text-xs hover:underline"
        >
          Alle Releases auf GitHub ansehen
        </a>
      </footer>
    {:else if changelogStore.error}
      <!-- Error -->
      <div
        class="bg-white p-6 rounded-3xl shadow-[var(--shadow-card)] border border-(--color-border) text-center"
      >
        <p class="text-sm text-(--color-text-secondary) mb-3">
          Changelog konnte nicht geladen werden.
        </p>
        <a
          href={RELEASES_URL}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 text-sm font-medium text-violet-600 hover:underline"
        >
          Auf GitHub ansehen
          <svg
            class="w-4 h-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
            />
          </svg>
        </a>
      </div>
    {/if}
  </div>
</main>
