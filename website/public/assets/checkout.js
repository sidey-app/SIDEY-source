import { commerceProducts } from "./commerce-products.js";

(() => {
  "use strict";

  const productionAPIBase = "https://whtejsviizgejauasqqt.supabase.co/functions/v1";
  const products = commerceProducts;
  const loading = document.querySelector("#checkout-loading");
  const error = document.querySelector("#checkout-error");
  const errorMessage = document.querySelector("#checkout-error-message");
  const product = document.querySelector("#checkout-product");
  const productImage = document.querySelector("#checkout-product-image");
  const previewFrame = document.querySelector("#checkout-preview-frame");
  const orderName = document.querySelector("#checkout-order-name");
  const amount = document.querySelector("#checkout-amount");
  const consent = document.querySelector("#checkout-consent");
  const policyNotice = document.querySelector("#checkout-policy-notice");
  const payButton = document.querySelector("#checkout-pay");
  const status = document.querySelector("#checkout-status");
  let token = "";
  let apiBase = "";
  let prepared = null;
  let inFlight = false;
  let awaitingConfirmation = false;

  function updateControls() {
    payButton.disabled = inFlight || awaitingConfirmation || !prepared || !consent.checked;
    consent.disabled = inFlight || awaitingConfirmation;
  }

  function showError(message) {
    loading.hidden = true;
    product.hidden = true;
    errorMessage.textContent = message;
    error.hidden = false;
  }

  async function request(path, body) {
    const response = await fetch(`${apiBase}/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      cache: "no-store",
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      const requestError = new Error(payload?.error || "checkout_request_failed");
      requestError.status = response.status;
      throw requestError;
    }
    return payload;
  }

  function validPrepared(config) {
    return config
      && Object.hasOwn(products, config.product_id)
      && typeof config.order_name === "string"
      && Number.isSafeInteger(config.amount)
      && config.amount > 0
      && config.currency === "KRW"
      && typeof config.policy_version === "string"
      && typeof config.policy_notice === "string"
      && ["test", "live"].includes(config.payment_environment);
  }

  function validAuthorized(config) {
    try {
      const redirect = new URL(config.redirect_url);
      return validPrepared(config)
        && config.product_id === prepared.product_id
        && config.amount === prepared.amount
        && config.policy_version === prepared.policy_version
        && typeof config.store_id === "string"
        && typeof config.channel_key === "string"
        && typeof config.payment_id === "string"
        && config.pay_method === "CARD"
        && config.portone_currency === "CURRENCY_KRW"
        && redirect.origin === window.location.origin
        && redirect.pathname.endsWith("/checkout-result/");
    } catch {
      return false;
    }
  }

  async function completePayment(config, paymentID) {
    const completion = await request("commerce-complete", { token, payment_id: paymentID });
    const resultURL = new URL(completion.result_url);
    if (resultURL.origin !== window.location.origin || !resultURL.pathname.endsWith("/checkout-result/")) {
      throw new Error("invalid_result_url");
    }
    window.location.assign(resultURL.toString());
  }

  async function start() {
    token = new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "";
    apiBase = productionAPIBase;
    window.history.replaceState(null, "", window.location.pathname);
    if (!/^[A-Za-z0-9_-]{43}$/.test(token) || !apiBase) {
      showError("SIDEY 상점에서 구매할 상품을 선택해주세요.");
      return;
    }

    try {
      prepared = await request("commerce-checkout", { token, action: "prepare" });
      if (!validPrepared(prepared)) throw new Error("invalid_checkout_config");
      orderName.textContent = prepared.order_name;
      amount.textContent = new Intl.NumberFormat("ko-KR").format(prepared.amount);
      const preview = products[prepared.product_id];
      productImage.src = new URL(`../${preview.image}`, import.meta.url).href;
      productImage.alt = prepared.order_name;
      previewFrame.dataset.productKind = preview.kind;
      policyNotice.textContent = prepared.policy_notice;
      payButton.textContent = `${amount.textContent}원 결제하기`;
      updateControls();
      loading.hidden = true;
      product.hidden = false;
    } catch (requestError) {
      console.error(requestError);
      showError(requestError.status === 410
        ? "주문 링크가 만료되었거나 이미 처리되었습니다. SIDEY 앱 상점에서 다시 시도해 주세요."
        : "주문을 확인하지 못했습니다. SIDEY 상점에서 다시 시도해주세요.");
    }
  }

  payButton.addEventListener("click", async () => {
    if (inFlight || awaitingConfirmation || !prepared) return;
    if (!consent.checked) {
      status.textContent = "구매 조건과 환불 안내에 먼저 동의해 주세요.";
      consent.focus();
      return;
    }
    inFlight = true;
    updateControls();
    let phase = "authorize";
    status.textContent = "결제창을 준비하고 있어요…";
    try {
      const config = await request("commerce-checkout", {
        token,
        action: "authorize",
        policy_version: prepared.policy_version,
      });
      if (!validAuthorized(config) || typeof window.PortOne?.requestPayment !== "function") {
        throw new Error("portone_sdk_unavailable");
      }
      phase = "payment";
      const response = await window.PortOne.requestPayment({
        storeId: config.store_id,
        channelKey: config.channel_key,
        paymentId: config.payment_id,
        orderName: config.order_name,
        totalAmount: config.amount,
        currency: config.portone_currency,
        payMethod: config.pay_method,
        redirectUrl: config.redirect_url,
      });
      if (response?.code !== undefined) {
        status.textContent = response.message || "결제를 완료하지 않았습니다.";
        return;
      }
      phase = "confirm";
      awaitingConfirmation = true;
      if (response?.paymentId !== config.payment_id) throw new Error("payment_id_mismatch");
      status.textContent = "결제를 확인하고 있어요…";
      await completePayment(config, response.paymentId);
    } catch (paymentError) {
      console.error(paymentError);
      status.textContent = phase === "confirm"
        ? "결제 결과를 확인하지 못했습니다. 다시 결제하지 말고 SIDEY 상점에서 구매 상태를 확인해주세요."
        : phase === "payment"
          ? "결제창을 열거나 진행하지 못했습니다. 승인 알림을 받았다면 다시 결제하지 말고 SIDEY 상점에서 구매 상태를 확인해주세요."
          : "결제를 시작하지 못했습니다. SIDEY 상점에서 다시 시도해주세요.";
    } finally {
      inFlight = false;
      updateControls();
    }
  });

  consent.addEventListener("change", updateControls);

  start();
})();
