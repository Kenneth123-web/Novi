import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          ADMIN_PASSWORD: "test-admin-password",
          CONSOLE_ORIGIN_SECRET: "test-origin-secret",
          API_BASE_URL: "https://api.test",
        },
      },
    }),
  ],
});
