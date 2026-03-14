<script lang="ts">
  import {
    addGoal,
    contributeGoal,
    deleteGoal,
    undo,
    type Goal,
  } from "$lib/wasm";
  import { formatEur } from "$lib/format";
  import { data } from "$lib/data.svelte";
  import { toastStore } from "$lib/toast.svelte";
  import EmptyState from "../../../components/EmptyState.svelte";

  const ICONS = ["🎯", "🏠", "✈️", "🚗", "💻", "🎓", "💍", "🏖️", "🎸", "📱", "🏋️", "🎮"];

  let goals = $derived(data.goals());
  let showForm = $state(false);
  let error = $state<string | null>(null);
  let deletingId = $state<string | null>(null);
  let contributingId = $state<string | null>(null);
  let contributeAmount = $state("");

  // Form state
  let formName = $state("");
  let formIcon = $state("🎯");
  let formTarget = $state("");
  let formDeadline = $state("");

  let totalSaved = $derived(goals.reduce((sum, g) => sum + g.current, 0));
  let totalTarget = $derived(goals.reduce((sum, g) => sum + g.target, 0));
  let overallPct = $derived(
    totalTarget > 0 ? Math.round((totalSaved / totalTarget) * 100) : 0,
  );

  async function handleAddGoal() {
    const target = parseFloat(formTarget.replace(",", "."));

    if (!formName.trim() || isNaN(target) || target <= 0) {
      error = "Bitte Name und gültigen Zielbetrag eingeben";
      return;
    }

    try {
      error = null;
      const name = formName.trim();
      const targetCents = Math.round(target * 100);
      const deadline = formDeadline || null;
      await addGoal(name, formIcon, targetCents, deadline);
      data.bump();
      formName = "";
      formIcon = "🎯";
      formTarget = "";
      formDeadline = "";
      showForm = false;
      toastStore.show(`Sparziel hinzugefügt: ${name}`, async () => {
        await undo();
        data.bump();
      });
    } catch (e) {
      error = e instanceof Error ? e.message : "Fehler beim Hinzufügen";
    }
  }

  async function handleContribute(goal: Goal) {
    const amount = parseFloat(contributeAmount.replace(",", "."));
    if (isNaN(amount) || amount <= 0) {
      error = "Bitte einen gültigen Betrag eingeben";
      return;
    }

    try {
      error = null;
      const amountCents = Math.round(amount * 100);
      await contributeGoal(goal.id, amountCents);
      data.bump();
      contributingId = null;
      contributeAmount = "";
      toastStore.show(`${goal.name}: ${formatEur(amount)} gespart`, async () => {
        await undo();
        data.bump();
      });
    } catch (e) {
      error = e instanceof Error ? e.message : "Fehler beim Einzahlen";
    }
  }

  async function handleDelete(goal: Goal) {
    try {
      error = null;
      const name = goal.name;
      await deleteGoal(goal.id);
      data.bump();
      deletingId = null;
      toastStore.show(`Sparziel gelöscht: ${name}`, async () => {
        await undo();
        data.bump();
      });
    } catch (e) {
      error = e instanceof Error ? e.message : "Fehler beim Löschen";
    }
  }
</script>

<div class="flex items-center gap-3 mb-5">
    <a
      href="/more"
      class="w-10 h-10 rounded-2xl bg-white flex items-center justify-center shadow-sm"
      aria-label="Zurück"
    >
      <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
    </a>
    <h2 class="text-2xl font-display font-extrabold text-(--color-text)">Sparziele</h2>
  </div>

{#if error}
  <div class="bg-rose-50 rounded-3xl p-5 mb-4 text-rose-700 text-sm font-medium">
    {error}
  </div>
{/if}

<!-- Hero Card: Overall Progress -->
{#if goals.length > 0}
  <div id="progress" class="bg-(--color-accent) rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden">
    <div class="absolute -right-10 -top-10 w-40 h-40 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>
    <div class="flex flex-col gap-1 relative z-10">
      <p class="font-bold text-sm uppercase tracking-wide text-(--color-text)">
        Gesamtfortschritt
      </p>
      <p class="text-4xl font-display font-black tracking-tight text-(--color-text) mt-1">
        {formatEur(totalSaved)}
      </p>
      <p class="text-(--color-text)/70 font-medium text-sm mt-1">von {formatEur(totalTarget)} gespart</p>
    </div>
    <div class="flex flex-col gap-3 mt-5 relative z-10">
      <div class="flex justify-between items-end">
        <span class="text-sm font-bold text-(--color-text)/80">Fortschritt</span>
        <span class="text-base font-extrabold text-(--color-text)">{overallPct}%</span>
      </div>
      <div class="h-4 w-full bg-white/50 rounded-full overflow-hidden">
        <div
          class="h-full bg-(--color-text) rounded-full transition-all"
          style="width: {overallPct}%"
        ></div>
      </div>
    </div>
  </div>
{/if}

<!-- Section Title + Add Button -->
<div class="flex items-center justify-between gap-3 mb-4 px-1">
  <h3 class="text-xl font-display font-extrabold">Deine Sparziele</h3>
  <div class="flex items-center gap-2 shrink-0">
    {#if goals.length > 0}
      <span class="text-sm font-bold text-(--color-text) bg-(--color-accent) px-4 py-1.5 rounded-full shadow-sm">
        {goals.length} {goals.length === 1 ? "Ziel" : "Ziele"}
      </span>
    {/if}
    <button
      onclick={() => (showForm = !showForm)}
      class="w-8 h-8 flex items-center justify-center rounded-full bg-gray-200 hover:bg-gray-300 transition-colors cursor-pointer"
      aria-label="Sparziel hinzufügen"
    >
      <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v12m6-6H6" />
      </svg>
    </button>
  </div>
</div>

<!-- Add Goal Form -->
{#if showForm}
  <div class="bg-white rounded-3xl shadow-[var(--shadow-soft)] p-5 mb-4">
    <h3 class="text-base font-display font-bold mb-4">Neues Sparziel</h3>
    <div class="space-y-3">
      <input
        type="text"
        placeholder="Name (z.B. Urlaub 2027)"
        bind:value={formName}
        class="w-full px-4 py-3 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
      <!-- Icon Picker -->
      <div>
        <p class="text-xs font-semibold text-(--color-text-secondary) mb-2 px-1">Icon</p>
        <div class="flex flex-wrap gap-2">
          {#each ICONS as icon}
            <button
              onclick={() => (formIcon = icon)}
              class="w-10 h-10 rounded-xl text-lg flex items-center justify-center cursor-pointer transition-all {formIcon === icon ? 'bg-(--color-accent) ring-2 ring-(--color-text) scale-110' : 'bg-gray-50 hover:bg-gray-100'}"
            >
              {icon}
            </button>
          {/each}
        </div>
      </div>
      <input
        type="text"
        placeholder="Zielbetrag (z.B. 5000)"
        bind:value={formTarget}
        class="w-full px-4 py-3 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
      <input
        type="date"
        placeholder="Deadline (optional)"
        bind:value={formDeadline}
        class="w-full px-4 py-3 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
      <div class="flex gap-2">
        <button
          onclick={handleAddGoal}
          class="flex-1 bg-(--color-accent) text-(--color-text) py-3 rounded-2xl text-sm font-bold cursor-pointer hover:bg-(--color-accent-hover) transition-colors"
        >
          Hinzufügen
        </button>
        <button
          onclick={() => (showForm = false)}
          class="px-5 py-3 rounded-2xl text-sm font-medium text-(--color-text-secondary) cursor-pointer hover:bg-gray-100 transition-colors"
        >
          Abbrechen
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Goal Cards -->
{#if goals.length === 0 && !showForm}
  <EmptyState
    title="Keine Sparziele"
    subtitle="Setze dir Sparziele und verfolge deinen Fortschritt."
  >
    {#snippet icon()}
      <svg class="w-10 h-10 text-(--color-text)/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
      </svg>
    {/snippet}
    {#snippet actions()}
      <button
        onclick={() => (showForm = true)}
        class="px-6 py-3 rounded-2xl bg-(--color-accent) text-(--color-text) font-bold text-sm transition-transform active:scale-[0.98]"
      >
        Sparziel hinzufügen
      </button>
    {/snippet}
  </EmptyState>
{:else}
  <div class="flex flex-col gap-4 mb-5">
    {#each goals as goal}
      {@const remaining = goal.target - goal.current}
      {@const pct =
        goal.target > 0 ? Math.round((goal.current / goal.target) * 100) : 0}
      {@const isComplete = remaining <= 0}

      <div id={goal.id} class="bg-white p-5 rounded-3xl shadow-[var(--shadow-card)] flex flex-col gap-5">
        <!-- Top row: icon + name + action -->
        <div class="flex justify-between items-start">
          <div class="flex items-center gap-3">
            <span class="text-2xl">{goal.icon}</span>
            <div>
              <h4 class="font-extrabold text-lg">{goal.name}</h4>
              {#if goal.deadline}
                <p class="text-sm font-medium text-(--color-text-secondary) mt-0.5">
                  Bis {new Date(goal.deadline).toLocaleDateString("de-DE", { day: "numeric", month: "short", year: "numeric" })}
                </p>
              {/if}
            </div>
          </div>
          <div class="flex items-center gap-1.5">
            {#if isComplete}
              <span class="flex items-center gap-1.5 px-4 py-2 bg-emerald-50 text-emerald-600 text-sm font-bold rounded-2xl">
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                </svg>
                Erreicht
              </span>
            {:else}
              <button
                onclick={() => { contributingId = contributingId === goal.id ? null : goal.id; contributeAmount = ""; }}
                class="flex items-center gap-1.5 px-4 py-2 bg-(--color-accent) hover:bg-(--color-accent-hover) text-(--color-text) text-sm font-bold rounded-2xl cursor-pointer transition-colors shadow-sm"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v12m6-6H6" />
                </svg>
                Einzahlen
              </button>
            {/if}
          </div>
        </div>

        <!-- Contribute inline input -->
        {#if contributingId === goal.id}
          <div class="flex gap-2">
            <input
              type="text"
              placeholder="Betrag (z.B. 50)"
              bind:value={contributeAmount}
              class="flex-1 px-4 py-2.5 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
            />
            <button
              onclick={() => handleContribute(goal)}
              class="px-5 py-2.5 bg-(--color-accent) text-(--color-text) rounded-2xl text-sm font-bold cursor-pointer hover:bg-(--color-accent-hover) transition-colors"
            >
              Sparen
            </button>
          </div>
        {/if}

        <!-- Progress row -->
        <div class="flex flex-col gap-2">
          <div class="flex justify-between text-xs font-bold uppercase tracking-wider text-(--color-text-secondary)">
            <span>{formatEur(goal.current)} von {formatEur(goal.target)}</span>
            <span class="text-(--color-text)">{pct}%</span>
          </div>
          <div class="h-3 w-full bg-gray-100 rounded-full overflow-hidden">
            <div
              class="h-full rounded-full transition-all"
              style="width: {pct}%; background-color: {isComplete ? 'var(--color-success)' : 'var(--color-text)'}"
            ></div>
          </div>
        </div>

        <!-- Delete -->
        {#if deletingId === goal.id}
          <div class="flex gap-2 pt-3 border-t border-gray-50">
            <button
              onclick={() => handleDelete(goal)}
              class="flex-1 bg-rose-50 text-rose-600 py-2.5 rounded-2xl text-sm font-bold cursor-pointer hover:bg-rose-100 transition-colors"
            >
              Endgültig löschen
            </button>
            <button
              onclick={() => (deletingId = null)}
              class="px-4 py-2.5 text-sm text-(--color-text-secondary) cursor-pointer hover:text-(--color-text) transition-colors"
            >
              Abbrechen
            </button>
          </div>
        {:else}
          <button
            onclick={() => (deletingId = goal.id)}
            class="flex items-center gap-1 text-xs text-gray-300 self-end cursor-pointer hover:text-rose-400 transition-colors"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            Entfernen
          </button>
        {/if}
      </div>
    {/each}
  </div>
{/if}
