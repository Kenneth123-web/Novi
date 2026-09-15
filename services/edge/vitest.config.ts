import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        // Runs the tests inside workerd itself, so the KV binding, the rate
        // limiter and `crypto.subtle.timingSafeEqual` are the real ones. A
        // mocked KV would not have caught the expirationTtl minimum.
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            PROVIDER_API_KEY: "sk-test-provider-key",
            EDGE_SHARED_SECRET: "test-shared-secret",
          },
        },
      },
    },
  },
});
