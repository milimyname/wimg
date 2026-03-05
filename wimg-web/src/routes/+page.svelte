<nav
  class="sticky top-0 z-10 bg-white/80 backdrop-blur-sm border-b border-(--color-border) px-6 py-4 flex items-center justify-between max-w-4xl mx-auto"
>
  <span class="text-xl font-bold text-(--color-primary)">wimg</span>
  <a
    href="/dashboard"
    class="text-sm font-medium text-(--color-primary) hover:underline"
  >
    Open App &rarr;
  </a>
</nav>

<div class="max-w-4xl mx-auto px-6">
  <!-- Hero -->
  <section class="py-20 text-center">
    <div class="text-6xl mb-6">&#128176;</div>
    <h1 class="text-4xl font-bold text-(--color-text) mb-4">
      Your finances, on your device.
    </h1>
    <p class="text-lg text-(--color-text-secondary) max-w-xl mx-auto">
      Local-first personal finance. No cloud, no account, no tracking. Just your
      bank data on your browser.
    </p>
  </section>

  <!-- Features -->
  <section class="grid grid-cols-1 md:grid-cols-3 gap-6 pb-16">
    <div class="bg-white rounded-2xl border border-(--color-border) p-6">
      <div class="text-3xl mb-3">&#128196;</div>
      <h3 class="font-semibold text-(--color-text) mb-2">CSV Import</h3>
      <p class="text-sm text-(--color-text-secondary)">
        Drop your bank CSV and see transactions instantly. Supports Comdirect,
        Trade Republic, and Scalable Capital.
      </p>
    </div>
    <div class="bg-white rounded-2xl border border-(--color-border) p-6">
      <div class="text-3xl mb-3">&#129302;</div>
      <h3 class="font-semibold text-(--color-text) mb-2">Auto-Categorize</h3>
      <p class="text-sm text-(--color-text-secondary)">
        Built-in rules sort your spending. Optional AI fallback catches the
        rest. No manual tagging.
      </p>
    </div>
    <div class="bg-white rounded-2xl border border-(--color-border) p-6">
      <div class="text-3xl mb-3">&#127974;</div>
      <h3 class="font-semibold text-(--color-text) mb-2">Multi-Account</h3>
      <p class="text-sm text-(--color-text-secondary)">
        Track checking, savings, and investment accounts in one place. Filter or
        view everything together.
      </p>
    </div>
  </section>

  <!-- Tech -->
  <section class="text-center pb-16">
    <p class="text-xs text-(--color-text-secondary) tracking-wide uppercase">
      Powered by Zig + SQLite + Svelte
    </p>
  </section>

  <!-- CTA -->
  <section class="text-center pb-20">
    <a
      href="/dashboard"
      class="inline-block bg-(--color-primary) text-white font-semibold px-8 py-3 rounded-full hover:opacity-90 transition-opacity"
    >
      Try wimg
    </a>
  </section>
</div>

<!-- Footer -->
<footer
  class="border-t border-(--color-border) py-6 px-6 text-center text-xs text-(--color-text-secondary)"
>
  <p>
    &copy; {new Date().getFullYear()} wimg &middot;
    <a
      href="https://github.com/komiljonmaksudov/wimg"
      class="hover:underline"
      target="_blank"
      rel="noopener noreferrer"
    >
      GitHub
    </a>
  </p>
</footer>
