import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          PROVIDER_API_KEY: "sk-test-provider-key",
          EDGE_SHARED_SECRET: "test-shared-secret",
          DAILY_REQUEST_CAP: "2",
        },
      },
    }),
  ],
});
