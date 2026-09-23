import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://sidey-app.github.io",
  base: "/SIDEY",
  output: "static",
  trailingSlash: "always",
  i18n: {
    locales: ["ko", "en", "ja", "zh-hant"],
    defaultLocale: "ko",
    routing: {
      prefixDefaultLocale: true,
    },
  },
  build: {
    format: "directory",
  },
  compressHTML: false,
  devToolbar: {
    enabled: false,
  },
});
