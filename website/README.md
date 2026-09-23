# SIDEY website

The public SIDEY website is an Astro static site deployed under
`https://sidey-app.github.io/SIDEY/`.

```sh
cd website
pnpm install --frozen-lockfile
pnpm run dev
```

- `src/pages/`: page sources; localized public routes live under `/ko/`,
  `/en/`, `/ja/`, and `/zh-hant/` (`lang`/`hreflang` use `zh-Hant`). The root and every locale-neutral counterpart of a localized public
  route detect the browser language and redirect to the matching localized
  route.
- `src/styles/styles.scss`: shared SCSS entry point. Component-level rules are
  split into Sass partials in `src/styles/` and compiled together by Astro.
- `public/`: client-side JavaScript, images, and other files copied as-is.
- `dist/`: generated build output; do not commit it.

Run `pnpm build` before submitting website changes to validate the Astro build.
