const CACHE_NAME = "wimg-v0.2.0";

const PRECACHE_URLS = [
	"/",
	"/libwimg.wasm",
	"/manifest.webmanifest",
	"/icon-192.png",
	"/icon-512.png",
];

self.addEventListener("install", (event) => {
	event.waitUntil(
		caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)),
	);
});

self.addEventListener("message", (event) => {
	if (event.data?.type === "SKIP_WAITING") {
		self.skipWaiting();
	}
});

self.addEventListener("activate", (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((names) =>
				Promise.all(
					names
						.filter((name) => name !== CACHE_NAME)
						.map((name) => caches.delete(name)),
				),
			)
			.then(() => self.clients.claim()),
	);
});

self.addEventListener("fetch", (event) => {
	const url = new URL(event.request.url);

	// Skip non-GET and cross-origin requests
	if (event.request.method !== "GET" || url.origin !== self.location.origin) {
		return;
	}

	// Network-first for HTML pages (to get fresh app shell)
	// Cache-first for assets (WASM, JS, CSS, images)
	if (
		event.request.mode === "navigate" ||
		event.request.headers.get("accept")?.includes("text/html")
	) {
		event.respondWith(
			fetch(event.request)
				.then((response) => {
					const clone = response.clone();
					caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
					return response;
				})
				.catch(() => caches.match(event.request).then((r) => r || caches.match("/"))),
		);
	} else {
		event.respondWith(
			caches.match(event.request).then(
				(cached) =>
					cached ||
					fetch(event.request).then((response) => {
						const clone = response.clone();
						caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
						return response;
					}),
			),
		);
	}
});
