<script lang="ts">
  import { SYNC_API_URL } from "$lib/config";
  import { feedbackStore } from "$lib/feedback.svelte";
  import Drawer from "./Drawer.svelte";

  type FeedbackType = "bug" | "feature" | "feedback";

  let fbType = $state<FeedbackType>("feedback");
  let fbMessage = $state("");
  let fbSending = $state(false);
  let fbResult = $state<{ number: number; url: string } | null>(null);
  let fbError = $state("");

  function onClose() {
    feedbackStore.hide();
  }

  // Persisted feedback history
  interface FeedbackEntry {
    number: number;
    url: string;
    type: string;
    message: string;
    date: string;
  }

  const FB_HISTORY_KEY = "wimg_feedback_history";

  function getHistory(): FeedbackEntry[] {
    try {
      return JSON.parse(localStorage.getItem(FB_HISTORY_KEY) || "[]");
    } catch {
      return [];
    }
  }

  function saveToHistory(entry: FeedbackEntry) {
    const h = getHistory();
    h.unshift(entry);
    localStorage.setItem(FB_HISTORY_KEY, JSON.stringify(h.slice(0, 20)));
  }

  let feedbackHistory = $state<FeedbackEntry[]>([]);

  async function submitFeedback() {
    if (fbMessage.trim().length < 3) return;
    fbSending = true;
    fbError = "";
    fbResult = null;

    try {
      const res = await fetch(`${SYNC_API_URL}/feedback`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: fbType, message: fbMessage.trim(), platform: "web" }),
      });
      if (res.status === 429) throw new Error("Zu viele Anfragen. Bitte warte eine Stunde.");
      if (!res.ok) throw new Error("Feedback konnte nicht gesendet werden");
      fbResult = await res.json();
      saveToHistory({
        ...fbResult!,
        type: fbType,
        message: fbMessage.trim(),
        date: new Date().toISOString().slice(0, 10),
      });
      feedbackHistory = getHistory();
      fbMessage = "";
    } catch (e: unknown) {
      fbError = e instanceof Error ? e.message : "Unbekannter Fehler";
    } finally {
      fbSending = false;
    }
  }

  function reset() {
    fbType = "feedback";
    fbMessage = "";
    fbSending = false;
    fbResult = null;
    fbError = "";
  }

  $effect(() => {
    if (feedbackStore.open) {
      reset();
      feedbackHistory = getHistory();
    }
  });

  const types: { value: FeedbackType; label: string; icon: string }[] = [
    { value: "bug", label: "Bug", icon: "🐛" },
    { value: "feature", label: "Wunsch", icon: "✨" },
    { value: "feedback", label: "Feedback", icon: "💬" },
  ];
</script>

<Drawer open={feedbackStore.open} onclose={onClose} snaps={[0.55, 0.92]}>
  {#snippet children({ handle, content })}
    <div class="pt-3 pb-2 shrink-0" {@attach handle}>
      <div class="w-12 h-1.5 bg-gray-200 rounded-full mx-auto mb-3"></div>
      <div class="flex items-center justify-between px-6">
        <h3 class="text-lg font-display font-extrabold flex items-center gap-2">
          <svg class="w-5 h-5 text-(--color-text-secondary)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
          </svg>
          Feedback
        </h3>
        <button
          onclick={onClose}
          class="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center hover:bg-gray-200 transition-colors"
          aria-label="Schließen"
        >
          <svg class="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>

    <div class="px-6 pt-2 pb-6" {@attach content}>
      {#if fbResult}
        <div class="bg-emerald-50 border border-emerald-200 rounded-2xl p-4 flex gap-3 items-start">
          <svg class="w-5 h-5 text-emerald-600 shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <p class="font-bold text-sm text-emerald-800">Danke!</p>
            <p class="text-xs text-emerald-700 mt-0.5">
              Issue <a href={fbResult.url} target="_blank" rel="noopener noreferrer" class="underline font-bold">#{fbResult.number}</a> wurde erstellt.
            </p>
          </div>
        </div>
      {:else}
        <div class="flex gap-2 mb-4">
          {#each types as opt}
            <button
              class="flex-1 py-2.5 rounded-xl text-sm font-bold transition-colors"
              class:bg-(--color-accent)={fbType === opt.value}
              class:text-(--color-text)={fbType === opt.value}
              class:bg-gray-50={fbType !== opt.value}
              class:text-gray-500={fbType !== opt.value}
              onclick={() => (fbType = opt.value)}
            >
              {#if fbType === opt.value}
                <span class="inline-block w-4 h-4 align-middle mr-0.5">
                  <svg class="w-4 h-4 inline" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" />
                  </svg>
                </span>
              {:else}
                {opt.icon}
              {/if}
              {opt.label}
            </button>
          {/each}
        </div>

        <textarea
          bind:value={fbMessage}
          placeholder="Beschreibe dein Feedback..."
          rows="4"
          class="w-full rounded-xl border border-gray-200 p-3 text-sm resize-none focus:outline-none focus:border-indigo-300 focus:ring-1 focus:ring-indigo-200 mb-3"
        ></textarea>

        {#if fbError}
          <p class="text-xs text-rose-500 font-medium mb-3">{fbError}</p>
        {/if}

        <button
          onclick={submitFeedback}
          disabled={fbSending || fbMessage.trim().length < 3}
          class="w-full py-3 rounded-xl text-sm font-bold transition-colors disabled:opacity-40 bg-(--color-text) text-white"
        >
          {fbSending ? "Sende..." : "Feedback senden"}
        </button>

        <p class="text-[10px] text-(--color-text-secondary) text-center mt-2">
          Erstellt ein GitHub Issue — kein Account nötig
        </p>
      {/if}

      {#if feedbackHistory.length > 0}
        <div class="mt-6 pt-4 border-t border-gray-100">
          <p class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-wide mb-3">Deine Feedbacks</p>
          <div class="space-y-2">
            {#each feedbackHistory.slice(0, 5) as entry}
              <a
                href={entry.url}
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-3 p-3 rounded-xl bg-gray-50 hover:bg-gray-100 transition-colors"
              >
                <span class="text-sm">
                  {entry.type === "bug" ? "🐛" : entry.type === "feature" ? "✨" : "💬"}
                </span>
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-medium truncate">{entry.message}</p>
                  <p class="text-[10px] text-(--color-text-secondary)">#{entry.number} · {entry.date}</p>
                </div>
                <svg class="w-3.5 h-3.5 text-(--color-text-secondary) shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                </svg>
              </a>
            {/each}
          </div>
        </div>
      {/if}
    </div>
  {/snippet}
</Drawer>
