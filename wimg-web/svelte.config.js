import adapter from "@sveltejs/adapter-cloudflare";

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    adapter: adapter({
      routes: {
        include: ["/*"],
        exclude: ["<all>"],
      },
    }),
    // version: {
    //   pollInterval: typeof import.meta.env !== 'undefined' && import.meta.env.DEV ? 1 * 1000 : 5 * 60 * 1000, // check for new deployment every 5 minutes
    // },
  },
};

export default config;
