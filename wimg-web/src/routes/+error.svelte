<script lang="ts">
  import { page } from "$app/state";

  let status = $derived(page.status);
  let isNotFound = $derived(status === 404);
  let heading = $derived(
    isNotFound ? "Ups! Seite nicht gefunden" : "Etwas ist schiefgelaufen",
  );
  let subtitle = $derived(
    isNotFound
      ? "Der digitale Pfad endet hier. Vielleicht wurde die Seite verschoben oder du hast dich vertippt."
      : "Wir konnten die Seite nicht laden. Bitte versuche es erneut.",
  );
  let badge = $derived(isNotFound ? "404 Error" : `${status} Fehler`);
</script>

<div
  class="min-h-screen flex items-center justify-center px-6 py-12 bg-(--color-bg)"
>
  <div class="max-w-md w-full text-center">
    <div
      class="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-(--color-accent) text-(--color-text) text-xs font-bold tracking-wider uppercase mb-8"
    >
      <span class="w-1.5 h-1.5 rounded-full bg-(--color-text)"></span>
      {badge}
    </div>

    <h1
      class="text-4xl sm:text-5xl font-display font-black text-(--color-text) mb-4 tracking-tight leading-tight"
    >
      {heading}
    </h1>

    <p
      class="text-base text-(--color-text-secondary) leading-relaxed font-medium mb-10"
    >
      {subtitle}
    </p>

    <div class="flex flex-col sm:flex-row gap-3 justify-center">
      <a
        href="/home"
        class="px-6 py-3 rounded-2xl bg-(--color-accent) hover:bg-(--color-accent-hover) text-(--color-text) font-bold text-sm transition-colors shadow-[var(--shadow-card)]"
      >
        Zurück zum Dashboard
      </a>
      <a
        href="https://github.com/milimyname/wimg/issues"
        target="_blank"
        rel="noopener noreferrer"
        class="px-6 py-3 rounded-2xl bg-white text-(--color-text) font-bold text-sm transition-colors border border-(--color-text)/10 hover:border-(--color-text)/30"
      >
        Support kontaktieren
      </a>
    </div>
  </div>
</div>
