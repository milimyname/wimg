<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    getDebts,
    addDebt,
    markDebtPaid,
    deleteDebt,
    undo,
    type Debt,
  } from "$lib/wasm";
  import { formatEur } from "$lib/format";
  import { toastStore } from "$lib/toast.svelte";

  let debts = $state<Debt[]>(getDebts());

  function onSyncReceived() {
    debts = getDebts();
  }

  onMount(() => {
    window.addEventListener("wimg:sync-received", onSyncReceived);
  });

  onDestroy(() => {
    window.removeEventListener("wimg:sync-received", onSyncReceived);
  });
  let showForm = $state(false);
  let error = $state<string | null>(null);
  let deletingId = $state<string | null>(null);

  // Form state
  let formName = $state("");
  let formTotal = $state("");
  let formMonthly = $state("");

  let totalRemaining = $derived(
    debts.reduce((sum, d) => sum + (d.total - d.paid), 0),
  );
  let totalDebt = $derived(debts.reduce((sum, d) => sum + d.total, 0));
  let overallPct = $derived(
    totalDebt > 0
      ? Math.round(((totalDebt - totalRemaining) / totalDebt) * 100)
      : 0,
  );
  let activeCount = $derived(debts.filter((d) => d.total - d.paid > 0).length);

  async function handleAddDebt() {
    const total = parseFloat(formTotal.replace(",", "."));
    const monthly = parseFloat(formMonthly.replace(",", ".")) || 0;

    if (!formName.trim() || isNaN(total) || total <= 0) {
      error = "Bitte Name und gültigen Betrag eingeben";
      return;
    }

    try {
      error = null;
      const name = formName.trim();
      await addDebt(name, total, monthly);
      debts = getDebts();
      formName = "";
      formTotal = "";
      formMonthly = "";
      showForm = false;
      toastStore.show(`Schuld hinzugefügt: ${name}`, async () => {
        await undo();
        debts = getDebts();
      });
    } catch (e) {
      error = e instanceof Error ? e.message : "Fehler beim Hinzufügen";
    }
  }

  async function handleMarkPaid(debt: Debt) {
    try {
      error = null;
      const payAmount =
        debt.monthly > 0
          ? Math.min(debt.monthly, debt.total - debt.paid)
          : debt.total - debt.paid;
      const payCents = Math.round(payAmount * 100);
      await markDebtPaid(debt.id, payCents);
      debts = getDebts();
      toastStore.show(`${debt.name}: Zahlung verbucht`, async () => {
        await undo();
        debts = getDebts();
      });
    } catch (e) {
      error = e instanceof Error ? e.message : "Fehler beim Bezahlen";
    }
  }

  async function handleDelete(debt: Debt) {
    try {
      error = null;
      const name = debt.name;
      await deleteDebt(debt.id);
      debts = getDebts();
      deletingId = null;
      toastStore.show(`Schuld gelöscht: ${name}`, async () => {
        await undo();
        debts = getDebts();
      });
    } catch (e) {
      error = e instanceof Error ? e.message : "Fehler beim Löschen";
    }
  }
</script>

<h2 class="text-xl font-display font-extrabold text-center mb-5">Schulden</h2>

{#if error}
  <div class="bg-rose-50 rounded-3xl p-5 mb-4 text-rose-700 text-sm font-medium">
    {error}
  </div>
{/if}

<!-- Hero Card: Overall Progress -->
{#if debts.length > 0}
  <div class="bg-(--color-accent) rounded-[2rem] p-7 mb-5 shadow-[var(--shadow-soft)] relative overflow-hidden">
    <div class="absolute -right-10 -top-10 w-40 h-40 bg-white/20 rounded-full blur-2xl pointer-events-none"></div>
    <div class="flex flex-col gap-1 relative z-10">
      <p class="font-bold text-sm uppercase tracking-wide text-(--color-text)">
        Gesamtfortschritt
      </p>
      <p class="text-4xl font-display font-black tracking-tight text-(--color-text) mt-1">
        {formatEur(totalRemaining)}
      </p>
      <p class="text-(--color-text)/70 font-medium text-sm mt-1">Verbleibende Schulden</p>
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
<div class="flex items-center justify-between mb-4 px-1">
  <h3 class="text-2xl font-display font-extrabold">Deine Schulden</h3>
  <div class="flex items-center gap-2">
    {#if debts.length > 0}
      <span class="text-sm font-bold text-(--color-text) bg-(--color-accent) px-4 py-1.5 rounded-full shadow-sm">
        {activeCount} Aktiv
      </span>
    {/if}
    <button
      onclick={() => (showForm = !showForm)}
      class="w-8 h-8 flex items-center justify-center rounded-full bg-gray-200 hover:bg-gray-300 transition-colors cursor-pointer"
      aria-label="Schuld hinzufügen"
    >
      <svg class="w-5 h-5 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v12m6-6H6" />
      </svg>
    </button>
  </div>
</div>

<!-- Add Debt Form -->
{#if showForm}
  <div class="bg-white rounded-3xl shadow-[var(--shadow-soft)] p-5 mb-4">
    <h3 class="text-base font-display font-bold mb-4">Neue Schuld</h3>
    <div class="space-y-3">
      <input
        type="text"
        placeholder="Name (z.B. WSW Strom)"
        bind:value={formName}
        class="w-full px-4 py-3 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
      <input
        type="text"
        placeholder="Gesamtbetrag (z.B. 1234,56)"
        bind:value={formTotal}
        class="w-full px-4 py-3 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
      <input
        type="text"
        placeholder="Monatliche Rate (optional)"
        bind:value={formMonthly}
        class="w-full px-4 py-3 bg-gray-50 rounded-2xl text-sm focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
      <div class="flex gap-2">
        <button
          onclick={handleAddDebt}
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

<!-- Debt Cards -->
{#if debts.length === 0 && !showForm}
  <div class="text-center py-16 text-(--color-text-secondary)">
    <p class="text-4xl mb-3">💳</p>
    <p class="font-display font-bold text-lg">Keine Schulden</p>
    <p class="text-sm mt-1">Füge Schulden hinzu um den Fortschritt zu tracken</p>
  </div>
{:else}
  <div class="flex flex-col gap-4 mb-5">
    {#each debts as debt}
      {@const remaining = debt.total - debt.paid}
      {@const pct =
        debt.total > 0 ? Math.round((debt.paid / debt.total) * 100) : 0}
      {@const isPaidOff = remaining <= 0}

      <div class="bg-white p-5 rounded-3xl shadow-[var(--shadow-card)] flex flex-col gap-5">
        <!-- Top row: name + action -->
        <div class="flex justify-between items-start">
          <div>
            <h4 class="font-extrabold text-lg">{debt.name}</h4>
            {#if debt.monthly > 0}
              <p class="text-sm font-medium text-(--color-text-secondary) mt-0.5">
                Monatlich: {formatEur(debt.monthly)}
              </p>
            {/if}
          </div>
          <div class="flex items-center gap-1.5">
            {#if isPaidOff}
              <span class="flex items-center gap-1.5 px-4 py-2 bg-emerald-50 text-emerald-600 text-sm font-bold rounded-2xl">
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                </svg>
                Abbezahlt
              </span>
            {:else}
              <button
                onclick={() => handleMarkPaid(debt)}
                class="flex items-center gap-1.5 px-4 py-2 bg-(--color-accent) hover:bg-(--color-accent-hover) text-(--color-text) text-sm font-bold rounded-2xl cursor-pointer transition-colors shadow-sm"
              >
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                </svg>
                Bezahlt
              </button>
            {/if}
          </div>
        </div>

        <!-- Progress row -->
        <div class="flex flex-col gap-2">
          <div class="flex justify-between text-xs font-bold uppercase tracking-wider text-(--color-text-secondary)">
            <span>{formatEur(remaining)} übrig</span>
            <span class="text-(--color-text)">{pct}% erledigt</span>
          </div>
          <div class="h-3 w-full bg-gray-100 rounded-full overflow-hidden">
            <div
              class="h-full rounded-full transition-all"
              style="width: {pct}%; background-color: {isPaidOff ? 'var(--color-success)' : 'var(--color-text)'}"
            ></div>
          </div>
        </div>

        <!-- Delete -->
        {#if deletingId === debt.id}
          <div class="flex gap-2 pt-3 border-t border-gray-50">
            <button
              onclick={() => handleDelete(debt)}
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
            onclick={() => (deletingId = debt.id)}
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
