import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const catalog = JSON.parse(readFileSync(new URL("../../assets/v1/commerce-catalog.json", import.meta.url)));
const read = (path) => readFileSync(new URL(`../dist/${path}`, import.meta.url), "utf8");
const manifest = JSON.parse(readFileSync(new URL("../../assets/v1/manifest.json", import.meta.url)));
const root = new URL("../../", import.meta.url);
const included = { characters: 5, throwables: 1, bubbles: 1 };

const checkoutPrepared = {
  product_id: "fixture-product",
  order_name: "Fixture product",
  amount: 1100,
  currency: "KRW",
  policy_version: "fixture-policy",
  policy_notice: "Fixture purchase policy",
  payment_environment: "test",
};

const checkoutAuthorized = {
  ...checkoutPrepared,
  store_id: "store-fixture",
  channel_key: "channel-fixture",
  payment_id: "payment-fixture",
  pay_method: "CARD",
  portone_currency: "CURRENCY_KRW",
  redirect_url: "https://sidey-app.github.io/SIDEY/checkout-result/",
};

const jsonResponse = (payload, status = 200) => ({
  ok: status >= 200 && status < 300,
  status,
  json: async () => payload,
});

async function waitFor(predicate, message) {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (predicate()) return;
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail(message);
}

async function createCheckoutHarness({ fetchResponse, requestPayment } = {}) {
  const { runInNewContext } = await import("node:vm");
  let source = readFileSync(new URL("../public/assets/checkout.js", import.meta.url), "utf8");
  source = source.replace(/^import .*;\r?\n/, `const commerceProducts = ${JSON.stringify({
    "fixture-product": { name: "Fixture product", image: "assets/store/fixture.png", kind: "character" },
    "other-fixture-product": { name: "Other fixture product", image: "assets/store/other-fixture.png", kind: "character" },
  })};\n`);
  source = source.replaceAll("import.meta.url", '"https://sidey-app.github.io/SIDEY/assets/checkout.js"');

  class Element {
    constructor(values = {}) { Object.assign(this, values); }
    listeners = {};
    dataset = {};
    hidden = false;
    disabled = false;
    checked = false;
    value = "";
    textContent = "";
    focused = 0;
    addEventListener(name, listener) { this.listeners[name] = listener; }
    focus() { this.focused++; }
  }

  const elements = Object.fromEntries([
    "loading", "error", "error-message", "product", "product-image", "preview-frame",
    "order-name", "amount", "meta", "consent", "policy-notice", "pay", "status",
  ].map(id => [`#checkout-${id}`, new Element()]));
  elements["#checkout-error"].hidden = true;
  elements["#checkout-product"].hidden = true;

  const requests = [];
  const paymentRequests = [];
  const assigned = [];
  const defaultFetchResponse = async (url, init, body) => {
    if (url.endsWith("/commerce-checkout") && body.action === "prepare") return jsonResponse(checkoutPrepared);
    if (url.endsWith("/commerce-checkout") && body.action === "authorize") return jsonResponse(checkoutAuthorized);
    if (url.endsWith("/commerce-complete")) {
      return jsonResponse({ result_url: "https://sidey-app.github.io/SIDEY/checkout-result/?result=success" });
    }
    return jsonResponse({ error: "unexpected_request" }, 500);
  };
  const location = {
    hash: `#token=${"a".repeat(43)}`,
    pathname: "/SIDEY/checkout/",
    origin: "https://sidey-app.github.io",
    assign(url) { assigned.push(url); },
  };
  const sdkRequest = requestPayment ?? (async () => ({ code: "USER_CANCEL", message: "결제가 취소되었습니다." }));

  runInNewContext(source, {
    URL,
    URLSearchParams,
    Intl,
    document: { querySelector: selector => elements[selector] },
    window: {
      location,
      history: { replaceState() {} },
      PortOne: {
        async requestPayment(request) {
          paymentRequests.push(request);
          return sdkRequest(request);
        },
      },
    },
    console: { error() {} },
    fetch: async (url, init) => {
      const body = JSON.parse(init.body);
      requests.push({ url, body });
      return (fetchResponse ?? defaultFetchResponse)(url, init, body);
    },
  });

  await waitFor(() => elements["#checkout-product"].hidden === false || elements["#checkout-error"].hidden === false, "checkout did not finish preparing");
  return { elements, requests, paymentRequests, assigned };
}

for (const locale of ["ko", "en", "ja"]) {
  for (const category of Object.keys(included)) {
    test(`${locale}/${category}: complete catalog, exact reference prices, assets, separate keepsakes`, () => {
      const html = read(`${locale}/store/${category}/index.html`);
      const cards = [...html.matchAll(/<button class="store-product-card"[^>]*>[\s\S]*?<\/button>/g)].map(([card]) => card);
      const paid = catalog.filter((entry) => entry.kind === category.slice(0, -1));
      assert.equal(cards.length, paid.length + included[category]);
      assert.match(html, /store-price-basis/);
      assert.match(html, /reference prices|참고 가격|参考価格/);
      assert.doesNotMatch(html, /Windows direct-purchase|Windows 직접 결제|Windows版の直接決済/);
      assert.doesNotMatch(html, /direct macOS edition|macOS 직배포판|macOS直接配布版/);
      for (const entry of paid) {
        const card = cards.find((candidate) => candidate.includes(`data-product-id="${entry.id}"`));
        assert.ok(card, entry.id);
        const price = locale === "ko" ? `${entry.direct_price.toLocaleString("ko-KR")}원` : `₩${entry.direct_price.toLocaleString("en-US")}`;
        assert.ok(card.includes(`<strong>${price}</strong>`), `${entry.id}: ${price}`);
        if (locale === "ko") assert.ok(card.includes(entry.name));
        const keepsake = catalog.find((candidate) => candidate.related_character_product_id === entry.id);
        if (keepsake) {
          assert.match(card, /store-keepsake-summary/);
          assert.match(card, /store-keepsake-badge/);
          assert.ok(html.includes(`id="details-${keepsake.item_id}"`), "keepsake transition retains its price details");
        }
        if (entry.related_character_product_id) assert.match(card, /store-keepsake-badge/);
      }
      for (const [, path] of html.matchAll(/(?:src|data-preview-src|data-preview-emitter|data-preview-sound)="\/SIDEY\/([^"?#]+)"/g)) {
        assert.ok(existsSync(new URL(`../dist/${path}`, import.meta.url)), path);
      }
      assert.doesNotMatch(html, /production|staging|Sidey-dev|출시 예정|준비 중|checkout\?token=/);
      if (category === "throwables") {
        for (const card of cards) assert.match(card, /data-preview-sound="[^"]+\.wav"/);
        const soundButton = html.match(/<button[^>]*data-store-preview-sound-toggle[^>]*>[\s\S]*?<\/button>/)?.[0];
        assert.ok(soundButton);
        assert.match(soundButton, /aria-pressed="false"/);
        assert.match(soundButton, /<svg[^>]*viewBox="0 0 24 24"/);
        assert.doesNotMatch(soundButton, /material-symbols|volume_off|volume_up/);
      }
      if (category === "characters") {
        assert.equal(html.match(/class="store-keepsake-summary"/g)?.length, catalog.filter(entry => entry.related_character_product_id).length);
        if (locale === "ko") assert.match(html, /우클릭하면 멈추고/);
      }
    });
  }
  test(`${locale}: store entry and character tab show the same products`, () => {
    const ids = (html) => [...html.matchAll(/<button class="store-product-card"[^>]*data-product-id="([^"]+)"/g)].map((match) => match[1]);
    assert.deepEqual(ids(read(`${locale}/store/index.html`)), ids(read(`${locale}/store/characters/index.html`)));
  });
}

test("public sheets and sounds exactly match the approved canonical assets", () => {
  for (const entry of catalog.filter((entry) => entry.kind !== "bubble")) {
    const id = entry.render_asset_id ?? entry.item_id;
    const source = entry.kind === "character" ? `characters/${id}/base.png` : `throwables/${id}/sprite.png`;
    assert.deepEqual(readFileSync(new URL(`website/public/assets/store/${id}.png`, root)), readFileSync(new URL(`assets/v1/${source}`, root)));
  }
  const throwableIDs = ["patch_soft_ball", ...catalog.filter(entry => entry.kind === "throwable").map(entry => entry.render_asset_id ?? entry.item_id)];
  for (const id of throwableIDs) {
    const path = `impact-${id}.wav`;
    const publicAudio = readFileSync(new URL(`website/public/assets/store/${path}`, root));
    const asset = manifest.throwables.find(entry => entry.id === id);
    if (asset.supported_platforms.includes("macos")) {
      assert.deepEqual(publicAudio, readFileSync(new URL(`macos/SIDEY/Resources/DirectImpactAudio/${path}`, root)));
    }
    const canonical = new URL(`assets/v1/audio/${path}`, root);
    if (existsSync(canonical)) assert.deepEqual(publicAudio, readFileSync(canonical));
    assert.ok(read("ko/store/throwables/index.html").includes(`data-preview-sound="/SIDEY/assets/store/${path}"`));
  }
});

test("checkout and store share all current products and correct base-relative image URLs", async () => {
  const { commerceProducts } = await import("../public/assets/commerce-products.js");
  assert.deepEqual(Object.keys(commerceProducts).sort(), catalog.map(p => p.id).sort());
  for (const entry of catalog) {
    const product = commerceProducts[entry.id];
    assert.equal(product.name, entry.name);
    assert.ok(existsSync(new URL(`website/public/${product.image}`, root)), product.image);
    for (const base of ["https://example.test/SIDEY/", "https://example.test/"]) {
      const url = new URL(`../${product.image}`, `${base}assets/checkout.js`);
      assert.equal(url.href, base + product.image);
    }
  }
  for (const page of ["checkout", "checkout-result"]) {
    assert.match(read(`${page}/index.html`), new RegExp(`type="module"[^>]*src="[^\"]*${page}\\.js"|src="[^\"]*${page}\\.js"[^>]*type="module"`));
  }
});

test("preview sound responds to clicks, motion preference, product changes and dismissal", async () => {
  const { runInNewContext } = await import("node:vm");
  class Element {
    dataset = {}; listeners = {}; attributes = {}; children = [];
    classList = { add() {}, toggle() {} };
    addEventListener(name, fn) { this.listeners[name] = fn; }
    setAttribute(name, value) { this.attributes[name] = value; }
    appendChild(child) { this.children.push(child); }
    append(...children) { this.children.push(...children); }
    replaceChildren(...children) { this.children = children; }
    closest() { return this; }
    focus() {}
  }
  class Dialog extends Element {
    open = false;
    showModal() { this.open = true; }
    close() { this.open = false; this.listeners.close(); }
  }
  const dialog = new Dialog();
  const controls = Object.fromEntries(["stage", "title", "description", "close", "details", "sound-toggle"].map(key => [`[data-store-preview-${key}]`, new Element()]));
  dialog.querySelector = selector => controls[selector];
  const sound = controls["[data-store-preview-sound-toggle]"];
  const stage = controls["[data-store-preview-stage]"];
  const document = {
    hidden: false, documentElement: { dataset: { baseUrl: "/SIDEY/" } }, listeners: {},
    querySelectorAll: () => [], getElementById: id => id === "store-preview-dialog" ? dialog : null,
    createElement: () => new Element(), addEventListener(name, fn) { this.listeners[name] = fn; },
  };
  const players = [];
  class Audio {
    plays = 0; pauses = 0;
    constructor(source) { this.source = source; players.push(this); }
    play() { this.plays++; return new Promise((resolve, reject) => { this.reject = reject; }); }
    pause() { this.pauses++; }
  }
  const timers = new Map();
  let timerID = 0;
  let reducedMotion = true;
  const window = {
    matchMedia: () => ({ matches: reducedMotion }),
    setTimeout: fn => { timers.set(++timerID, fn); return timerID; },
    clearTimeout: id => timers.delete(id),
  };
  runInNewContext(readFileSync(new URL("../public/assets/store.js", import.meta.url), "utf8"), {
    document, window, Element, HTMLDialogElement: Dialog, HTMLTemplateElement: class {}, Audio,
  });
  const open = (soundPath, kind = "throwable") => {
    const target = new Element();
    target.dataset = { previewKind: kind, previewSrc: "sprite.png", previewSound: soundPath };
    document.listeners.click({ target });
  };
  open("ball.wav");
  assert.equal(sound.hidden, false);
  assert.equal(players[0].plays, 0, "default is silent");
  sound.listeners.click();
  assert.equal(players[0].plays, 1, "explicit click works even with reduced motion");
  assert.equal(sound.attributes["aria-pressed"], "true");
  open("duck.wav");
  assert.equal(players[0].pauses, 1, "switching products stops the previous sound");
  players[0].reject(new Error("old playback interrupted"));
  await Promise.resolve();
  assert.equal(sound.attributes["aria-pressed"], "true", "old audio failure cannot mute the new product");
  reducedMotion = false;
  const projectile = stage.children[1];
  projectile.listeners.animationiteration({ target: projectile, animationName: "preview-throw-arc" });
  [...timers.values()].at(-1)();
  assert.equal(players[1].plays, 1, "subsequent collisions play the selected sound");
  sound.listeners.click();
  assert.equal(players[1].pauses, 1);
  assert.equal(sound.attributes["aria-pressed"], "false");
  sound.listeners.click();
  document.hidden = true;
  document.listeners.visibilitychange();
  assert.equal(players[1].pauses, 2);
  document.hidden = false;
  controls["[data-store-preview-close]"].listeners.click();
  assert.equal(players[1].pauses, 3);
  [...timers.values()].at(-1)();
  assert.equal(dialog.open, false);
  open(undefined, "character");
  assert.equal(sound.hidden, true, "characters do not expose a sound toggle");
});

test("checkout sends the server-authorized amount as a fixed CARD request without easy-pay options", async () => {
  const harness = await createCheckoutHarness();
  const consent = harness.elements["#checkout-consent"];
  const pay = harness.elements["#checkout-pay"];
  consent.checked = true;
  consent.listeners.change();
  await pay.listeners.click();

  assert.equal(harness.paymentRequests.length, 1);
  assert.equal(harness.paymentRequests[0].payMethod, "CARD");
  assert.equal(harness.paymentRequests[0].totalAmount, checkoutPrepared.amount, "authorized server amount is authoritative");
  assert.equal(Object.hasOwn(harness.paymentRequests[0], "easyPay"), false);
});

test("checkout blocks missing consent before authorization", async () => {
  const harness = await createCheckoutHarness();
  await harness.elements["#checkout-pay"].listeners.click();
  assert.match(harness.elements["#checkout-status"].textContent, /먼저 동의/);
  assert.equal(harness.elements["#checkout-consent"].focused, 1);
  assert.equal(harness.requests.filter(request => request.body.action === "authorize").length, 0);
  assert.equal(harness.paymentRequests.length, 0);
});

test("checkout rejects unsupported server payment methods before invoking PortOne", async () => {
  for (const payMethod of ["EASY_PAY", "TRANSFER", undefined]) {
    const harness = await createCheckoutHarness({
      fetchResponse: async (url, init, body) => {
        if (body.action === "prepare") return jsonResponse(checkoutPrepared);
        return jsonResponse({ ...checkoutAuthorized, pay_method: payMethod });
      },
    });
    harness.elements["#checkout-consent"].checked = true;
    await harness.elements["#checkout-pay"].listeners.click();
    assert.match(harness.elements["#checkout-status"].textContent, /결제 요청을 준비하지 못했습니다/, String(payMethod));
    assert.equal(harness.paymentRequests.length, 0, String(payMethod));
  }
});

test("checkout rejects authorization details that differ from the prepared order", async () => {
  for (const [field, value] of [
    ["product_id", "other-fixture-product"],
    ["amount", 2200],
    ["policy_version", "different-policy"],
  ]) {
    const harness = await createCheckoutHarness({
      fetchResponse: async (url, init, body) => {
        if (body.action === "prepare") return jsonResponse(checkoutPrepared);
        return jsonResponse({ ...checkoutAuthorized, [field]: value });
      },
    });
    harness.elements["#checkout-consent"].checked = true;
    await harness.elements["#checkout-pay"].listeners.click();
    assert.match(harness.elements["#checkout-status"].textContent, /결제 요청을 준비하지 못했습니다/, field);
    assert.equal(harness.paymentRequests.length, 0, field);
  }
});

test("checkout distinguishes authorization failures from payment SDK failures", async () => {
  const authorizationFailure = await createCheckoutHarness({
    fetchResponse: async (url, init, body) => {
      if (body.action === "prepare") return jsonResponse(checkoutPrepared);
      return jsonResponse({ error: "authorize_failed" }, 500);
    },
  });
  authorizationFailure.elements["#checkout-consent"].checked = true;
  await authorizationFailure.elements["#checkout-pay"].listeners.click();
  assert.match(authorizationFailure.elements["#checkout-status"].textContent, /결제 요청을 준비하지 못했습니다/);

  const sdkFailure = await createCheckoutHarness({
    requestPayment: async () => { throw new Error("sdk_fixture_failure"); },
  });
  sdkFailure.elements["#checkout-consent"].checked = true;
  await sdkFailure.elements["#checkout-pay"].listeners.click();
  assert.match(sdkFailure.elements["#checkout-status"].textContent, /결제창을 열거나 진행하지 못했습니다/);
  assert.match(sdkFailure.elements["#checkout-status"].textContent, /sdk_fixture_failure/);
});

test("checkout locks controls and ignores duplicate clicks and consent changes while authorizing", async () => {
  let releaseAuthorization;
  const authorization = new Promise(resolve => { releaseAuthorization = resolve; });
  const harness = await createCheckoutHarness({
    fetchResponse: async (url, init, body) => {
      if (body.action === "prepare") return jsonResponse(checkoutPrepared);
      if (body.action === "authorize") return authorization;
      return jsonResponse({ error: "unexpected_request" }, 500);
    },
  });
  const consent = harness.elements["#checkout-consent"];
  const pay = harness.elements["#checkout-pay"];
  consent.checked = true;

  const firstClick = pay.listeners.click();
  await waitFor(() => harness.requests.some(request => request.body.action === "authorize"), "authorization did not start");
  assert.equal(pay.disabled, true);
  assert.equal(consent.disabled, true);
  consent.listeners.change();
  await pay.listeners.click();
  assert.equal(harness.requests.filter(request => request.body.action === "authorize").length, 1);
  assert.equal(pay.disabled, true, "change events cannot unlock an active request");

  releaseAuthorization(jsonResponse(checkoutAuthorized));
  await firstClick;
  assert.equal(harness.paymentRequests.length, 1);
});

test("checkout re-enables valid controls after an SDK cancellation response", async () => {
  const harness = await createCheckoutHarness();
  const consent = harness.elements["#checkout-consent"];
  const pay = harness.elements["#checkout-pay"];
  consent.checked = true;

  await pay.listeners.click();
  assert.equal(harness.elements["#checkout-status"].textContent, "결제가 취소되었습니다.");
  assert.equal(pay.disabled, false);
  assert.equal(consent.disabled, false);
});

test("checkout prevents retries after an accepted SDK result cannot be confirmed", async () => {
  for (const failure of ["payment ID mismatch", "completion failure"]) {
    const harness = await createCheckoutHarness({
      requestPayment: async () => ({
        paymentId: failure === "payment ID mismatch" ? "different-payment" : checkoutAuthorized.payment_id,
      }),
      fetchResponse: async (url, init, body) => {
        if (body.action === "prepare") return jsonResponse(checkoutPrepared);
        if (body.action === "authorize") return jsonResponse(checkoutAuthorized);
        return jsonResponse({ error: "complete_fixture_failure" }, 500);
      },
    });
    harness.elements["#checkout-consent"].checked = true;
    await harness.elements["#checkout-pay"].listeners.click();
    assert.match(harness.elements["#checkout-status"].textContent, /다시 결제하지 말고 SIDEY 상점에서 구매 상태를 확인/);
    assert.equal(harness.elements["#checkout-pay"].disabled, true, failure);
    assert.equal(harness.elements["#checkout-consent"].disabled, true, failure);
    await harness.elements["#checkout-pay"].listeners.click();
    assert.equal(harness.requests.filter(request => request.body.action === "authorize").length, 1, failure);
    assert.equal(harness.paymentRequests.length, 1, failure);
  }
});

test("checkout redirects only after successful server completion", async () => {
  const harness = await createCheckoutHarness({
    requestPayment: async () => ({ paymentId: checkoutAuthorized.payment_id }),
  });
  harness.elements["#checkout-consent"].checked = true;
  await harness.elements["#checkout-pay"].listeners.click();
  assert.deepEqual(harness.assigned, ["https://sidey-app.github.io/SIDEY/checkout-result/?result=success"]);
  assert.equal(harness.elements["#checkout-pay"].disabled, true);
});
test("checkout ignores injected API origins and sends tokens only to SIDEY production", async () => {
  const { runInNewContext } = await import("node:vm");
  for (const name of ["checkout", "checkout-result"]) {
    let source = readFileSync(new URL(`../public/assets/${name}.js`, import.meta.url), "utf8");
    source = source.replace(/^import .*;\r?\n/, "const commerceProducts = {};\n");
    source = source.replaceAll("import.meta.url", '"https://sidey-app.github.io/SIDEY/assets/checkout.js"');
    const requests = [];
    const element = () => ({ addEventListener() {}, dataset: {} });
    runInNewContext(source, {
      URL, URLSearchParams, Intl,
      document: { querySelector: element },
      window: {
        location: {
          search: "?api=https://attacker.supabase.co/functions/v1&result=complete&paymentId=payment-test",
          hash: `#token=${"a".repeat(43)}`,
          pathname: `/SIDEY/${name}/`, origin: "https://sidey-app.github.io",
        },
        history: { replaceState() {} },
      },
      console: { error() {} },
      fetch: async (url) => {
        requests.push(url);
        return { ok: false, status: 410, json: async () => ({ error: "checkout_expired" }) };
      },
    });
    assert.equal(requests.length, 1);
    assert.equal(requests[0], `https://whtejsviizgejauasqqt.supabase.co/functions/v1/${name === "checkout" ? "commerce-checkout" : "commerce-complete"}`);
  }
});

test("checkout CSP permits PortOne preparation and its hosted payment frame", () => {
  const page = readFileSync(new URL("../src/pages/checkout.astro", import.meta.url), "utf8");
  const policy = page.match(/content="(default-src[^"]+)"/)[1];
  const directives = Object.fromEntries(policy.split(";").map((part) => {
    const [name, ...values] = part.trim().split(/\s+/);
    return [name, values];
  }));
  for (const directive of ["connect-src", "frame-src"]) {
    assert.ok(directives[directive].includes("https://checkout-service.prod.iamport.co"));
  }
  assert.ok(directives["connect-src"].includes("https://whtejsviizgejauasqqt.supabase.co"));
  assert.ok(!directives["connect-src"].includes("https://*.supabase.co"));
});

test("generated checkout pages use external executable scripts under strict CSP", () => {
  for (const page of ["checkout", "checkout-result"]) {
    const html = read(`${page}/index.html`);
    const policy = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)?.[1];
    assert.ok(policy, `${page}: CSP is present`);
    assert.doesNotMatch(policy, /'unsafe-inline'/, `${page}: inline script execution stays disabled`);
    assert.match(html, /<script[^>]+src="\/SIDEY\/assets\/site-theme\.js"[^>]*><\/script>/);
    assert.match(html, /<script[^>]+src="\/SIDEY\/assets\/site-header\.js"[^>]*><\/script>/);
    assert.match(html, new RegExp(`<script[^>]+src="(?:/SIDEY/|\\.\\./)assets/${page}\\.js"[^>]*></script>`));
    for (const [, attributes, body] of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
      assert.match(attributes, /\bsrc="[^"]+"/, `${page}: every executable script has an external source`);
      assert.equal(body.trim(), "", `${page}: executable script body is empty`);
    }
  }
});
