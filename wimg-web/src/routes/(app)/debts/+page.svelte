<script lang="ts">
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
      console.log("undo", undo);
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

<h2 class="text-lg font-bold text-center mb-4">Schulden</h2>

{#if error}
  <div
    class="bg-rose-50 border border-rose-200 rounded-xl p-4 mb-4 text-rose-700 text-sm"
  >
    {error}
  </div>
{/if}

<!-- Hero Card: Overall Progress -->
{#if debts.length > 0}
  <div
    class="bg-white rounded-xl shadow-sm border border-gray-100 p-6 mb-4 flex flex-col gap-5"
  >
    <div class="flex flex-col gap-1">
      <p
        class="font-semibold text-xs uppercase tracking-wider"
        style="color: var(--color-primary)"
      >
        Gesamtfortschritt
      </p>
      <p class="text-3xl font-bold tracking-tight">
        {formatEur(totalRemaining)}
      </p>
      <p class="text-sm text-gray-400">Verbleibende Schulden</p>
    </div>
    <div class="flex flex-col gap-2">
      <div class="flex justify-between items-end">
        <span class="text-sm font-medium text-gray-600">Fortschritt</span>
        <span class="text-sm font-bold" style="color: var(--color-primary)"
          >{overallPct}%</span
        >
      </div>
      <div
        class="h-3 w-full rounded-full overflow-hidden"
        style="background-color: var(--color-primary-light)"
      >
        <div
          class="h-full rounded-full transition-all"
          style="width: {overallPct}%; background-color: var(--color-primary)"
        ></div>
      </div>
    </div>
  </div>
{/if}

<!-- Section Title + Add Button -->
<div class="flex items-center justify-between mb-3">
  <h3 class="text-lg font-bold">Deine Schulden</h3>
  <div class="flex items-center gap-2">
    {#if debts.length > 0}
      <span
        class="text-xs font-medium px-2 py-1 rounded-full"
        style="color: var(--color-primary); background-color: var(--color-primary-light)"
      >
        {activeCount} Aktiv
      </span>
    {/if}
    <button
      onclick={() => (showForm = !showForm)}
      class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100 transition-colors cursor-pointer"
      aria-label="Schuld hinzufügen"
    >
      <svg
        class="w-5 h-5"
        style="color: var(--color-primary)"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 6v12m6-6H6"
        />
      </svg>
    </button>
  </div>
</div>

<!-- Add Debt Form -->
{#if showForm}
  <div class="bg-white rounded-xl border border-gray-100 shadow-sm p-4 mb-4">
    <h3 class="text-sm font-bold mb-3">Neue Schuld</h3>
    <div class="space-y-3">
      <input
        type="text"
        placeholder="Name (z.B. WSW Strom)"
        bind:value={formName}
        class="w-full px-3 py-2.5 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-200"
      />
      <input
        type="text"
        placeholder="Gesamtbetrag (z.B. 1234,56)"
        bind:value={formTotal}
        class="w-full px-3 py-2.5 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-200"
      />
      <input
        type="text"
        placeholder="Monatliche Rate (optional)"
        bind:value={formMonthly}
        class="w-full px-3 py-2.5 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-200"
      />
      <div class="flex gap-2">
        <button
          onclick={handleAddDebt}
          class="flex-1 text-white py-2.5 rounded-xl text-sm font-bold cursor-pointer hover:opacity-90 transition-opacity"
          style="background-color: var(--color-primary)"
        >
          Hinzufügen
        </button>
        <button
          onclick={() => (showForm = false)}
          class="px-4 py-2.5 border border-gray-200 rounded-xl text-sm cursor-pointer hover:bg-gray-50 transition-colors"
        >
          Abbrechen
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Debt Cards -->
{#if debts.length === 0 && !showForm}
  <div class="text-center py-16 text-gray-400">
    <p class="text-3xl mb-3">💳</p>
    <p class="font-medium">Keine Schulden</p>
    <p class="text-sm mt-1">
      Füge Schulden hinzu um den Fortschritt zu tracken
    </p>
  </div>
{:else}
  <div class="flex flex-col gap-3 mb-4">
    {#each debts as debt}
      {@const remaining = debt.total - debt.paid}
      {@const pct =
        debt.total > 0 ? Math.round((debt.paid / debt.total) * 100) : 0}
      {@const isPaidOff = remaining <= 0}

      <div
        class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 flex flex-col gap-4"
      >
        <!-- Top row: name + action -->
        <div class="flex justify-between items-start">
          <div>
            <h4 class="font-bold">{debt.name}</h4>
            {#if debt.monthly > 0}
              <p class="text-xs text-gray-400">
                Monatlich: {formatEur(debt.monthly)}
              </p>
            {/if}
          </div>
          <div class="flex items-center gap-1.5">
            {#if isPaidOff}
              <span
                class="flex items-center gap-1 px-3 py-1.5 bg-emerald-50 text-emerald-600 text-xs font-bold rounded-lg"
              >
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                    clip-rule="evenodd"
                  />
                </svg>
                Abbezahlt
              </span>
            {:else}
              <button
                onclick={() => handleMarkPaid(debt)}
                class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-lg cursor-pointer transition-colors"
                style="background-color: var(--color-primary-light); color: var(--color-primary)"
              >
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                    clip-rule="evenodd"
                  />
                </svg>
                Bezahlt
              </button>
            {/if}
          </div>
        </div>

        <!-- Progress row -->
        <div class="flex flex-col gap-1.5">
          <div
            class="flex justify-between text-[10px] font-bold uppercase tracking-wider text-gray-400"
          >
            <span>{formatEur(remaining)} übrig</span>
            <span>{pct}% erledigt</span>
          </div>
          <div class="h-1.5 w-full bg-gray-100 rounded-full overflow-hidden">
            <div
              class="h-full rounded-full transition-all"
              style="width: {pct}%; background-color: {isPaidOff
                ? 'var(--color-success)'
                : 'var(--color-primary)'}"
            ></div>
          </div>
        </div>

        <!-- Delete -->
        {#if deletingId === debt.id}
          <div class="flex gap-2 pt-2 border-t border-gray-50">
            <button
              onclick={() => handleDelete(debt)}
              class="flex-1 bg-rose-50 text-rose-600 py-2 rounded-lg text-xs font-bold cursor-pointer hover:bg-rose-100 transition-colors"
            >
              Endgültig löschen
            </button>
            <button
              onclick={() => (deletingId = null)}
              class="px-4 py-2 text-xs text-gray-400 cursor-pointer hover:text-gray-600 transition-colors"
            >
              Abbrechen
            </button>
          </div>
        {:else}
          <button
            onclick={() => (deletingId = debt.id)}
            class="flex items-center gap-1 text-xs text-gray-300 self-end cursor-pointer hover:text-rose-400 transition-colors"
          >
            <svg
              class="w-3.5 h-3.5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
            Entfernen
          </button>
        {/if}
      </div>
    {/each}
  </div>
{/if}
