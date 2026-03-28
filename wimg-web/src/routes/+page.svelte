<nav
  class="sticky top-0 z-10 bg-(--color-bg)/90 backdrop-blur-xl px-6 py-4 flex items-center justify-between max-w-4xl mx-auto"
>
  <span class="text-xl font-display font-extrabold text-(--color-text)"
    >wimg</span
  >
  <a
    href="/home"
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
  <section class="text-center pb-16">
    <a
      href="/home"
      class="inline-block bg-(--color-accent) text-(--color-text) font-display font-extrabold text-lg px-10 py-4 rounded-full hover:bg-(--color-accent-hover) transition-colors shadow-[0_8px_20px_rgba(255,233,125,0.3)]"
    >
      wimg ausprobieren
    </a>
  </section>

  <!-- Mobile Apps -->
  <section class="pb-24">
    <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
      <div
        class="bg-white rounded-3xl p-7 shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-soft)] transition-shadow"
      >
        <div
          class="w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center text-2xl mb-4"
        >
          &#63743;
        </div>
        <h3
          class="font-display font-extrabold text-(--color-text) mb-2 text-lg"
        >
          iOS (TestFlight)
        </h3>
        <p class="text-sm text-(--color-text-secondary) leading-relaxed mb-4">
          Native SwiftUI-App. Teste die Beta via TestFlight.
        </p>
        <a
          href="https://testflight.apple.com/join/wimg"
          class="text-sm font-bold text-(--color-text) bg-(--color-accent) px-5 py-2 rounded-full hover:bg-(--color-accent-hover) transition-colors inline-block"
          target="_blank"
          rel="noopener noreferrer"
        >
          TestFlight beitreten
        </a>
      </div>
      <div
        class="bg-white rounded-3xl p-7 shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-soft)] transition-shadow"
      >
        <div
          class="w-14 h-14 rounded-2xl bg-green-50 flex items-center justify-center mb-4"
        >
          <svg class="w-7 h-7 text-green-600" viewBox="0 0 256 256" fill="currentColor">
            <path d="M191.83,51.48l13.83-13.82a8,8,0,0,0-11.32-11.32L179.79,40.9a87.81,87.81,0,0,0-103.58,0L61.66,26.34A8,8,0,0,0,50.34,37.66L64.17,51.48A87.72,87.72,0,0,0,40,112v40a88,88,0,0,0,176,0V112A87.72,87.72,0,0,0,191.83,51.48ZM128,40a72.08,72.08,0,0,1,72,72v8H56v-8A72.08,72.08,0,0,1,128,40Zm0,184a72.08,72.08,0,0,1-72-72V136H200v16A72.08,72.08,0,0,1,128,224ZM144,92a12,12,0,1,1,12,12A12,12,0,0,1,144,92ZM88,92a12,12,0,1,1,12,12A12,12,0,0,1,88,92Z"/>
          </svg>
        </div>
        <h3
          class="font-display font-extrabold text-(--color-text) mb-2 text-lg"
        >
          Android (APK)
        </h3>
        <p class="text-sm text-(--color-text-secondary) leading-relaxed mb-4">
          Native Kotlin-App. APK herunterladen und installieren.
        </p>
        <a
          href="https://github.com/milimyname/wimg/releases/latest/download/wimg.apk"
          class="text-sm font-bold text-(--color-text) bg-(--color-accent) px-5 py-2 rounded-full hover:bg-(--color-accent-hover) transition-colors inline-block"
        >
          APK herunterladen
        </a>
        <p class="text-xs text-(--color-text-secondary) mt-3 leading-relaxed">
          Einstellungen &rarr; Apps &rarr; Unbekannte Quellen erlauben, dann APK
          antippen.
        </p>
      </div>
    </div>
  </section>
</div>

<!-- Footer -->
<footer
  class="border-t border-(--color-border) py-8 px-6 text-center text-xs text-(--color-text-secondary) font-medium"
>
  <p>
    &copy; {new Date().getFullYear()} wimg &middot;
    <a href="/changelog" class="hover:underline font-bold">Was ist neu?</a>
    &middot;
    <a
      href="https://github.com/milimyname/wimg"
      class="hover:underline font-bold"
      target="_blank"
      rel="noopener noreferrer"
    >
      GitHub
    </a>
  </p>
</footer>
