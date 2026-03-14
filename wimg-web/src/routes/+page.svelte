<nav
  class="sticky top-0 z-10 bg-(--color-bg)/90 backdrop-blur-xl px-6 py-4 flex items-center justify-between max-w-4xl mx-auto"
>
  <span class="text-xl font-display font-extrabold text-(--color-text)"
    >wimg</span
  >
  <a
    href="/dashboard"
    class="text-sm font-bold text-(--color-text) bg-(--color-accent) px-5 py-2 rounded-full hover:bg-(--color-accent-hover) transition-colors"
  >
    App starten &rarr;
  </a>
</nav>

<div class="max-w-4xl mx-auto px-6">
  <!-- Hero -->
  <section class="py-24 text-center">
    <div
      class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-(--color-accent) mb-8"
    >
      <span class="text-4xl">&#128176;</span>
    </div>
    <h1
      class="text-5xl font-display font-black text-(--color-text) mb-5 tracking-tight leading-tight"
    >
      Deine Finanzen,<br />auf deinem Gerät.
    </h1>
    <p
      class="text-lg text-(--color-text-secondary) max-w-xl mx-auto leading-relaxed font-medium"
    >
      Lokale Finanzverwaltung. Keine Cloud, kein Konto, kein Tracking. Nur deine
      Bankdaten in deinem Browser.
    </p>
  </section>

  <!-- Features -->
  <section class="grid grid-cols-1 md:grid-cols-3 gap-5 pb-20">
    <div
      class="bg-white rounded-3xl p-7 shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div
        class="w-14 h-14 rounded-2xl bg-amber-50 flex items-center justify-center text-2xl mb-4"
      >
        &#128196;
      </div>
      <h3 class="font-display font-extrabold text-(--color-text) mb-2 text-lg">
        CSV-Import
      </h3>
      <p class="text-sm text-(--color-text-secondary) leading-relaxed">
        Bank-CSV hochladen und Transaktionen sofort sehen. Unterstützt
        Comdirect, Trade Republic und Scalable Capital.
      </p>
    </div>
    <div
      class="bg-white rounded-3xl p-7 shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div
        class="w-14 h-14 rounded-2xl bg-purple-50 flex items-center justify-center text-2xl mb-4"
      >
        &#129302;
      </div>
      <h3 class="font-display font-extrabold text-(--color-text) mb-2 text-lg">
        Auto-Kategorisierung
      </h3>
      <p class="text-sm text-(--color-text-secondary) leading-relaxed">
        Eingebaute Regeln sortieren deine Ausgaben. Optionale KI übernimmt den
        Rest. Kein manuelles Taggen.
      </p>
    </div>
    <div
      class="bg-white rounded-3xl p-7 shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-soft)] transition-shadow"
    >
      <div
        class="w-14 h-14 rounded-2xl bg-emerald-50 flex items-center justify-center text-2xl mb-4"
      >
        &#127974;
      </div>
      <h3 class="font-display font-extrabold text-(--color-text) mb-2 text-lg">
        Multi-Konto
      </h3>
      <p class="text-sm text-(--color-text-secondary) leading-relaxed">
        Giro-, Spar- und Anlagekonten an einem Ort. Filtern oder alles zusammen
        anzeigen.
      </p>
    </div>
  </section>

  <!-- Tech -->
  <section class="text-center pb-16">
    <p
      class="text-xs text-(--color-text-secondary) tracking-widest uppercase font-bold"
    >
      Powered by Zig + SQLite + Svelte
    </p>
  </section>

  <!-- CTA -->
  <section class="text-center pb-24">
    <a
      href="/dashboard"
      class="inline-block bg-(--color-accent) text-(--color-text) font-display font-extrabold text-lg px-10 py-4 rounded-full hover:bg-(--color-accent-hover) transition-colors shadow-[0_8px_20px_rgba(255,233,125,0.3)]"
    >
      wimg ausprobieren
    </a>
  </section>
</div>

<!-- Footer -->
<footer
  class="border-t border-(--color-border) py-8 px-6 text-center text-xs text-(--color-text-secondary) font-medium"
>
  <p>
    &copy; {new Date().getFullYear()} wimg &middot;
    <a
      href="https://github.com/milimyname"
      class="hover:underline font-bold"
      target="_blank"
      rel="noopener noreferrer"
    >
      GitHub
    </a>
  </p>
</footer>
