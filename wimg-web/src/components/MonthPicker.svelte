<script lang="ts">
  let { year = $bindable(), month = $bindable() }: { year: number; month: number } = $props();

  const monthNames = [
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
  ];

  function prev() {
    if (month === 1) {
      month = 12;
      year -= 1;
    } else {
      month -= 1;
    }
  }

  function next() {
    if (month === 12) {
      month = 1;
      year += 1;
    } else {
      month += 1;
    }
  }
</script>

<div class="flex items-center justify-between bg-white rounded-xl px-4 py-3 border border-(--color-border) mb-4">
  <button
    onclick={prev}
    aria-label="Previous month"
    class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100 transition-colors cursor-pointer"
  >
    <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
    </svg>
  </button>
  <span class="font-semibold text-(--color-text)">
    {monthNames[month - 1]} {year}
  </span>
  <button
    onclick={next}
    aria-label="Next month"
    class="w-8 h-8 flex items-center justify-center rounded-full hover:bg-gray-100 transition-colors cursor-pointer"
  >
    <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
    </svg>
  </button>
</div>
