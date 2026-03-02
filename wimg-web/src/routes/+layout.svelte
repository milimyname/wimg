<script lang="ts">
	import '../app.css';
	let { children } = $props();
</script>

<div class="min-h-screen bg-(--color-bg)">
	<header class="sticky top-0 z-10 bg-white/80 backdrop-blur-sm border-b border-(--color-border) px-4 py-3">
		<h1 class="text-xl font-bold text-(--color-primary)">wimg</h1>
	</header>
	<main class="max-w-2xl mx-auto px-4 py-6">
		{@render children()}
	</main>
</div>
