<script lang="ts">
  import { accountStore } from "$lib/account.svelte";
  import {
    addAccount,
    updateAccount,
    deleteAccount,
    type Account,
  } from "$lib/wasm";

  let open = $state(false);
  let showAddForm = $state(false);
  let newName = $state("");
  let newColor = $state("#1A1A1A");

  // Edit state
  let editingAccount = $state<Account | null>(null);
  let editName = $state("");
  let editColor = $state("");

  // Delete confirmation
  let confirmDelete = $state<Account | null>(null);

  const presetColors = [
    "#1A1A1A",
    "#f5a623",
    "#6c5ce7",
    "#2dc653",
    "#ff6b6b",
    "#45b7d1",
    "#fd79a8",
    "#e17055",
  ];

  function close() {
    open = false;
    showAddForm = false;
    editingAccount = null;
    confirmDelete = null;
  }

  function select(id: string | null) {
    accountStore.select(id);
    close();
  }

  async function handleAdd() {
    const name = newName.trim();
    if (!name) return;
    const id = name.toLowerCase().replace(/[^a-z0-9]+/g, "_");
    await addAccount(id, name, newColor);
    accountStore.reload();
    newName = "";
    newColor = "#1A1A1A";
    showAddForm = false;
  }

  function startEdit(account: Account) {
    editingAccount = account;
    editName = account.name;
    editColor = account.color;
    showAddForm = false;
    confirmDelete = null;
  }

  async function handleEdit() {
    if (!editingAccount) return;
    const name = editName.trim();
    if (!name) return;
    await updateAccount(editingAccount.id, name, editColor);
    accountStore.reload();
    editingAccount = null;
  }

  function startDelete(account: Account) {
    confirmDelete = account;
    editingAccount = null;
    showAddForm = false;
  }

  async function handleDelete() {
    if (!confirmDelete) return;
    if (accountStore.selected === confirmDelete.id) {
      accountStore.select(null);
    }
    await deleteAccount(confirmDelete.id);
    accountStore.reload();
    confirmDelete = null;
  }

  let label = $derived(accountStore.selectedAccount?.name ?? "Alle Konten");
  let dotColor = $derived(accountStore.selectedAccount?.color ?? null);

  function clickOutside(element: HTMLElement) {
    function handleClick(e: MouseEvent) {
      if (open && !e.composedPath().includes(element)) {
        close();
      }
    }
    document.addEventListener("click", handleClick);
    return () => document.removeEventListener("click", handleClick);
  }
</script>

<div class="relative" {@attach clickOutside}>
  <button
    onclick={() => {
      open = !open;
      if (!open) {
        showAddForm = false;
        editingAccount = null;
        confirmDelete = null;
      }
    }}
    class="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold bg-white shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-soft)] transition-shadow cursor-pointer"
  >
    {#if dotColor}
      <span
        class="w-2 h-2 rounded-full shrink-0"
        style="background-color: {dotColor}"
      ></span>
    {/if}
    <span class="truncate max-w-[120px]">{label}</span>
    <svg
      class="w-3 h-3 text-(--color-text-secondary) shrink-0"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M19 9l-7 7-7-7"
      />
    </svg>
  </button>

  {#if open}
    <div
      class="absolute right-0 top-full mt-2 bg-white rounded-3xl shadow-[var(--shadow-soft)] py-2 z-30 min-w-[220px]"
    >
      <!-- Delete confirmation -->
      {#if confirmDelete}
        <div class="px-4 py-3">
          <p class="text-sm font-bold mb-1">Konto löschen?</p>
          <p class="text-xs text-(--color-text-secondary) mb-3">
            „{confirmDelete.name}" wird entfernt. Transaktionen bleiben erhalten.
          </p>
          <div class="flex gap-2">
            <button
              onclick={handleDelete}
              class="flex-1 text-xs font-bold py-2 rounded-full bg-red-500 text-white cursor-pointer"
            >
              Löschen
            </button>
            <button
              onclick={() => (confirmDelete = null)}
              class="text-xs text-(--color-text-secondary) px-3 cursor-pointer"
            >
              Abbrechen
            </button>
          </div>
        </div>

        <!-- Edit form -->
      {:else if editingAccount}
        <div class="px-4 py-3">
          <p class="text-[10px] font-bold uppercase text-(--color-text-secondary) mb-2 tracking-wider">
            Konto bearbeiten
          </p>
          <input
            type="text"
            bind:value={editName}
            class="w-full text-sm bg-gray-50 rounded-2xl px-3 py-2 mb-2 focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
            onkeydown={(e) => e.key === "Enter" && handleEdit()}
          />
          <div class="flex gap-1.5 mb-3">
            {#each presetColors as c}
              <button
                class="w-5 h-5 rounded-full cursor-pointer border-2 transition-all"
                style="background-color: {c}; border-color: {c === editColor ? '#333' : 'transparent'}"
                onclick={() => (editColor = c)}
              ></button>
            {/each}
          </div>
          <div class="flex gap-2">
            <button
              onclick={handleEdit}
              disabled={!editName.trim()}
              class="flex-1 text-xs font-bold py-2 rounded-full bg-(--color-text) text-white cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Speichern
            </button>
            <button
              onclick={() => startDelete(editingAccount!)}
              class="text-xs text-red-400 px-2 cursor-pointer"
            >
              Löschen
            </button>
            <button
              onclick={() => (editingAccount = null)}
              class="text-xs text-(--color-text-secondary) px-2 cursor-pointer"
            >
              Abbrechen
            </button>
          </div>
        </div>

        <!-- Normal dropdown -->
      {:else}
        <button
          class="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 flex items-center gap-2 cursor-pointer rounded-2xl mx-1"
          class:font-bold={accountStore.selected === null}
          onclick={() => select(null)}
        >
          <span class="w-2 h-2 rounded-full bg-gray-300 shrink-0"></span>
          Alle Konten
          {#if accountStore.selected === null}
            <svg class="w-4 h-4 text-(--color-text) ml-auto" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
            </svg>
          {/if}
        </button>

        {#each accountStore.accounts as account}
          <div class="flex items-center hover:bg-gray-50 group rounded-2xl mx-1">
            <button
              class="flex-1 text-left px-4 py-2.5 text-sm flex items-center gap-2 cursor-pointer"
              class:font-bold={accountStore.selected === account.id}
              onclick={() => select(account.id)}
            >
              <span
                class="w-2 h-2 rounded-full shrink-0"
                style="background-color: {account.color}"
              ></span>
              {account.name}
              {#if accountStore.selected === account.id}
                <svg class="w-4 h-4 text-(--color-text) ml-auto" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                </svg>
              {/if}
            </button>
            <button
              onclick={() => startEdit(account)}
              class="px-2 py-1 mr-2 text-gray-300 hover:text-gray-500 cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity"
              aria-label="Konto bearbeiten"
            >
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
              </svg>
            </button>
          </div>
        {/each}

        <div class="border-t border-gray-100 mt-1 pt-1 mx-2">
          {#if showAddForm}
            <div class="px-2 py-2">
              <input
                type="text"
                bind:value={newName}
                placeholder="Kontoname..."
                class="w-full text-sm bg-gray-50 rounded-2xl px-3 py-2 mb-2 focus:outline-none focus:ring-2 focus:ring-(--color-accent)"
                onkeydown={(e) => e.key === "Enter" && handleAdd()}
              />
              <div class="flex gap-1.5 mb-2">
                {#each presetColors as c}
                  <button
                    class="w-5 h-5 rounded-full cursor-pointer border-2 transition-all"
                    style="background-color: {c}; border-color: {c === newColor ? '#333' : 'transparent'}"
                    onclick={() => (newColor = c)}
                  ></button>
                {/each}
              </div>
              <div class="flex gap-2">
                <button
                  onclick={handleAdd}
                  disabled={!newName.trim()}
                  class="flex-1 text-xs font-bold py-2 rounded-full bg-(--color-text) text-white cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  Hinzufügen
                </button>
                <button
                  onclick={() => {
                    showAddForm = false;
                    newName = "";
                  }}
                  class="text-xs text-(--color-text-secondary) px-2 cursor-pointer"
                >
                  Abbrechen
                </button>
              </div>
            </div>
          {:else}
            <button
              class="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 flex items-center gap-2 cursor-pointer text-(--color-text-secondary) rounded-2xl"
              onclick={() => (showAddForm = true)}
            >
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Konto hinzufügen
            </button>
          {/if}
        </div>
      {/if}
    </div>
  {/if}
</div>
