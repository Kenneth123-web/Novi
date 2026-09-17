import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            ADMIN_PASSWORD: "test-admin-password",
            CONSOLE_ORIGIN_SECRET: "test-origin-secret",
            API_BASE_URL: "",
            TURNSTILE_SITEKEY: "",
            TURNSTILE_SITEVERIFY_URL: "",
          },
        },
      },
    },
  },
});
