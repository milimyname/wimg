<script lang="ts">
  interface Props {
    bankName?: string;
    challengeImage?: string;
    oncancel?: () => void;
    onsubmit?: (tan: string) => void;
  }

  let { bankName = "Bank", challengeImage, oncancel, onsubmit }: Props = $props();

  let tanInput = $state("");
  let submitting = $state(false);

  function handleSubmit() {
    if (!tanInput.trim() || submitting) return;
    submitting = true;
    onsubmit?.(tanInput.trim());
  }
</script>

<div class="flex flex-col min-h-[100dvh] max-w-md mx-auto">
  <!-- Header -->
  <header class="flex flex-col items-center pt-14 pb-5 px-6">
    <div class="w-16 h-16 rounded-[20px] bg-white shadow-[var(--shadow-card)] flex items-center justify-center mb-5">
      <svg class="w-8 h-8 text-(--color-text)" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 14v3m4-3v3m4-3v3M3 21h18M3 10h18M3 7l9-4 9 4M4 10h16v11H4V10z" />
      </svg>
    </div>
    <h1 class="text-2xl font-display font-extrabold tracking-tight mb-3.5">Bank-Verbindung</h1>
    <div class="flex items-center gap-2.5 bg-amber-100 px-4 py-2 rounded-full">
      <div class="w-2.5 h-2.5 rounded-full bg-amber-600 pulse-dot"></div>
      <p class="text-[13px] font-bold text-amber-700 uppercase tracking-wide">Warte auf Freigabe</p>
    </div>
  </header>

  <!-- QR / photoTAN image -->
  <main class="flex-1 px-7 flex flex-col items-center justify-center mt-1 mb-6">
    <div class="w-full bg-white rounded-3xl p-7 shadow-[var(--shadow-card)] aspect-square flex items-center justify-center relative">
      <!-- Corner markers -->
      <div class="absolute top-5 left-5 w-8 h-8 border-t-[3px] border-l-[3px] border-(--color-accent) rounded-tl-xl"></div>
      <div class="absolute top-5 right-5 w-8 h-8 border-t-[3px] border-r-[3px] border-(--color-accent) rounded-tr-xl"></div>
      <div class="absolute bottom-5 left-5 w-8 h-8 border-b-[3px] border-l-[3px] border-(--color-accent) rounded-bl-xl"></div>
      <div class="absolute bottom-5 right-5 w-8 h-8 border-b-[3px] border-r-[3px] border-(--color-accent) rounded-br-xl"></div>

      {#if challengeImage}
        <img src={challengeImage} alt="photoTAN challenge" class="w-full h-full object-contain z-10 p-1" />
      {:else}
        <!-- Placeholder QR pattern -->
        <svg class="w-full h-full text-(--color-text) z-10 p-2" fill="currentColor" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
          <rect height="20" rx="2" width="20" x="10" y="10" />
          <rect height="20" rx="2" width="20" x="70" y="10" />
          <rect height="20" rx="2" width="20" x="10" y="70" />
          <rect fill="white" height="10" width="10" x="15" y="15" />
          <rect fill="white" height="10" width="10" x="75" y="15" />
          <rect fill="white" height="10" width="10" x="15" y="75" />
          <rect height="5" width="5" x="17.5" y="17.5" />
          <rect height="5" width="5" x="77.5" y="17.5" />
          <rect height="5" width="5" x="17.5" y="77.5" />
          <rect height="5" rx="1" width="5" x="40" y="10" />
          <rect height="5" rx="1" width="15" x="50" y="10" />
          <rect height="5" rx="1" width="10" x="40" y="20" />
          <rect height="10" rx="1" width="5" x="55" y="20" />
          <rect height="15" rx="1" width="5" x="45" y="30" />
          <rect height="5" rx="1" width="15" x="65" y="35" />
          <rect height="15" rx="1" width="5" x="85" y="35" />
          <rect height="5" rx="1" width="15" x="10" y="40" />
          <rect height="15" rx="1" width="5" x="30" y="40" />
          <rect height="5" rx="1" width="10" x="10" y="50" />
          <rect height="5" rx="1" width="15" x="25" y="50" />
          <rect height="5" rx="1" width="20" x="45" y="50" />
          <rect height="15" rx="1" width="5" x="50" y="60" />
          <rect height="5" rx="1" width="15" x="60" y="55" />
          <rect height="10" rx="1" width="5" x="70" y="65" />
          <rect height="5" rx="1" width="10" x="40" y="75" />
          <rect height="5" rx="1" width="15" x="55" y="80" />
          <rect height="5" rx="1" width="5" x="45" y="85" />
          <rect height="5" rx="1" width="15" x="75" y="75" />
          <rect height="5" rx="1" width="10" x="80" y="85" />
        </svg>
      {/if}
    </div>

    <div class="mt-6 text-center px-4">
      <p class="text-[15px] text-(--color-text-secondary) leading-relaxed">
        Scanne diesen Code mit deiner<br />
        <strong class="font-bold text-(--color-text)">{bankName} photoTAN App</strong>
      </p>
    </div>

    <!-- TAN Input -->
    <div class="w-full mt-6">
      <input
        type="text"
        inputmode="numeric"
        bind:value={tanInput}
        placeholder="TAN eingeben"
        class="w-full bg-white rounded-2xl px-5 py-4 text-center text-lg font-mono font-bold tracking-[0.3em] shadow-[var(--shadow-card)] text-(--color-text) placeholder:text-(--color-text-secondary)/40 placeholder:tracking-normal placeholder:font-normal outline-none focus:ring-2 focus:ring-(--color-accent)"
      />
    </div>
  </main>

  <!-- Footer -->
  <footer class="mt-auto px-6 pb-8 space-y-4">
    <!-- Waiting indicator -->
    <div class="flex flex-col items-center justify-center gap-2.5">
      <svg class="w-8 h-8 text-(--color-accent) spin-slow" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
      </svg>
      <p class="text-xs font-bold text-(--color-text-secondary) uppercase tracking-widest">Warte auf Bank</p>
    </div>

    <!-- Submit TAN -->
    <button
      onclick={handleSubmit}
      disabled={!tanInput.trim() || submitting}
      class="w-full bg-(--color-accent) text-(--color-text) font-display font-extrabold text-lg py-4 rounded-2xl transition-all active:scale-[0.98] hover:bg-(--color-accent-hover) shadow-[0_8px_20px_rgba(255,233,125,0.25)] disabled:opacity-40 disabled:shadow-none"
    >
      {submitting ? "Sende..." : "TAN bestätigen"}
    </button>

    <!-- Cancel -->
    <button
      onclick={() => oncancel?.()}
      class="w-full py-3.5 rounded-2xl font-bold text-sm text-(--color-text-secondary) bg-(--color-primary-light) hover:bg-gray-200 active:scale-[0.98] transition-all"
    >
      Abbrechen
    </button>
  </footer>
</div>

<style>
  @keyframes pulse-dot {
    0% { box-shadow: 0 0 0 0 rgba(217, 119, 6, 0.4); }
    70% { box-shadow: 0 0 0 8px rgba(217, 119, 6, 0); }
    100% { box-shadow: 0 0 0 0 rgba(217, 119, 6, 0); }
  }
  .pulse-dot {
    animation: pulse-dot 2s infinite;
  }
  @keyframes spin-slow {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
  .spin-slow {
    animation: spin-slow 2.5s linear infinite;
  }
</style>
