const target = "/SIDEY/privacy/";

export const prerender = true;

export function GET() {
  return new Response(`<!doctype html>
<html lang="ko">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SIDEY — Privacy Policy</title>
    <meta name="robots" content="noindex">
    <link rel="canonical" href="https://sidey-app.github.io${target}">
    <meta http-equiv="refresh" content="0; url=${target}">
    <script>const destination=new URL(${JSON.stringify(target)},window.location.origin);destination.search=window.location.search;destination.hash=window.location.hash;window.location.replace(destination.href);</script>
  </head>
  <body><p><a href="${target}">SIDEY 정책 페이지로 이동</a></p></body>
</html>`, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
