<script lang="ts">
  let { visible, ondrop }: { visible: boolean; ondrop: (file: File) => void } =
    $props();
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="drop-overlay"
  data-hidden={!visible || undefined}
  ondragover={(e) => e.preventDefault()}
  ondrop={(e) => {
    e.preventDefault();
    const file = e.dataTransfer?.files[0];
    if (file) ondrop(file);
  }}
>
  <div class="drop-target flex flex-col items-center gap-5">
    <div
      class="w-32 h-32 rounded-full border-[3px] border-dashed border-white/70 flex items-center justify-center"
    >
      <svg
        class="w-12 h-12 text-white"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
        />
      </svg>
    </div>
    <p class="text-white text-lg font-display font-extrabold">
      CSV hier ablegen
    </p>
  </div>
</div>

<style>
  .drop-overlay {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.4);
    backdrop-filter: blur(4px);
    transition:
      opacity 0.2s ease,
      visibility 0.2s;
  }

  .drop-target {
    transition:
      transform 0.2s ease-out,
      opacity 0.2s ease-out;
  }

  .drop-overlay[data-hidden] {
    opacity: 0;
    visibility: hidden;
    pointer-events: none;
  }

  .drop-overlay[data-hidden] .drop-target {
    transform: scale(0.92);
    opacity: 0;
  }
</style>
