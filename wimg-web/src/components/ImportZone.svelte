<script lang="ts">
  import { importCsv, type ImportResult } from "$lib/wasm";

  let {
    onImported,
  }: {
    onImported?: (result: ImportResult) => void;
  } = $props();

  let dragging = $state(false);
  let importResult = $state<ImportResult | null>(null);
  let error = $state<string | null>(null);
  let importing = $state(false);

  function handleDragOver(e: DragEvent) {
    e.preventDefault();
    dragging = true;
  }

  function handleDragLeave() {
    dragging = false;
  }

  async function handleDrop(e: DragEvent) {
    e.preventDefault();
    dragging = false;
    const file = e.dataTransfer?.files[0];
    if (file) await processFile(file);
  }

  async function handleFileInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    await processFile(file);
    input.value = "";
  }

  async function processFile(file: File) {
    try {
      error = null;
      importing = true;
      const buffer = await file.arrayBuffer();
      importResult = await importCsv(buffer);
      onImported?.(importResult);
    } catch (e) {
      error = e instanceof Error ? e.message : "Import failed";
    } finally {
      importing = false;
    }
  }
</script>

<div
  class="border-2 border-dashed rounded-xl p-8 text-center cursor-pointer transition-all mb-4"
  style="border-color: {dragging ? 'var(--color-primary)' : '#d1d5db'}; background-color: {dragging ? 'var(--color-primary-light)' : 'transparent'}"
  role="button"
  tabindex="0"
  ondragover={handleDragOver}
  ondragleave={handleDragLeave}
  ondrop={handleDrop}
  onclick={() => document.getElementById("file-input")?.click()}
  onkeydown={(e) => e.key === "Enter" && document.getElementById("file-input")?.click()}
>
  <input
    id="file-input"
    type="file"
    accept=".csv"
    class="hidden"
    onchange={handleFileInput}
  />
  {#if importing}
    <div class="animate-spin w-8 h-8 mx-auto border-4 border-(--color-primary) border-t-transparent rounded-full"></div>
    <p class="text-(--color-text-secondary) mt-2">Importing...</p>
  {:else}
    <div class="text-3xl mb-2 text-(--color-text-secondary)">
      {#if dragging}
        <svg class="w-10 h-10 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
      {:else}
        <svg class="w-10 h-10 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
        </svg>
      {/if}
    </div>
    <p class="text-(--color-text-secondary)">
      Drop a CSV here, or click to browse
    </p>
    <p class="text-xs text-gray-400 mt-1">
      Comdirect, Trade Republic, Scalable Capital
    </p>
  {/if}
</div>

{#if error}
  <div class="bg-red-50 border border-red-200 rounded-xl p-4 mb-4 text-red-700">
    {error}
  </div>
{/if}

{#if importResult}
  <div class="bg-green-50 border border-green-200 rounded-xl p-4 mb-4">
    <p class="font-medium text-green-800">Import complete</p>
    <div class="text-sm text-green-700 mt-1">
      {importResult.imported} imported,
      {importResult.skipped_duplicates} duplicates skipped
      {#if importResult.categorized > 0}
        , {importResult.categorized} auto-categorized
      {/if}
      {#if importResult.errors > 0}
        , {importResult.errors} errors
      {/if}
    </div>
    {#if importResult.format && importResult.format !== "unknown"}
      <div class="mt-2">
        <span class="inline-block px-2 py-0.5 bg-blue-100 text-blue-700 text-xs rounded-full font-medium">
          {importResult.format}
        </span>
      </div>
    {/if}
  </div>
{/if}
