import { commerceProducts } from "./commerce-products.js";

(() => {
  "use strict";

  const productionAPIBase = "https://whtejsviizgejauasqqt.supabase.co/functions/v1";
  const productNames = Object.fromEntries(Object.entries(commerceProducts).map(([id, product]) => [id, product.name]));
  const results = {
    success: (name) => ({
      icon: "✦",
      title: `${name} 구매가 완료됐어요.`,
      message: "SIDEY 상점에서 구매한 상품을 사용해보세요.",
    }),
    canceled: () => ({
      icon: "!", title: "결제를 완료하지 않았어요.",
      message: "SIDEY 상점에서 다시 시도할 수 있습니다.",
    }),
    error: () => ({
      icon: "!", title: "결제를 확인하는 중 문제가 생겼어요.",
      message: "중복 결제하지 말고 SIDEY 상점에서 보유 상태를 먼저 새로고침해 주세요.",
    }),
    invalid: () => ({
      icon: "!", title: "결제 정보를 확인할 수 없어요.",
      message: "SIDEY 상점에서 구매 상태를 확인해주세요.",
    }),
  };

  const icon = document.querySelector("#result-icon");
  const title = document.querySelector("#result-title");
  const message = document.querySelector("#result-message");

  function render(key, productID) {
    const name = productNames[productID] || "SIDEY 디지털 꾸미기";
    const result = (results[key] || results.invalid)(name);
    icon.textContent = result.icon;
    title.textContent = result.title;
    message.textContent = result.message;
    document.title = `${result.title} · SIDEY`;
  }

  async function completeRedirect(query, productID) {
    const token = new URLSearchParams(window.location.hash.slice(1)).get("token") ?? "";
    const paymentID = query.get("paymentId") ?? "";
    const apiBase = productionAPIBase;
    window.history.replaceState(null, "", window.location.pathname);
    if (!apiBase || !/^[A-Za-z0-9_-]{43}$/.test(token) || paymentID.length < 6 || query.get("code")) {
      render(query.get("code") ? "canceled" : "invalid", productID);
      return;
    }
    try {
      const response = await fetch(`${apiBase}/commerce-complete`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token, payment_id: paymentID }),
        cache: "no-store",
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok || payload?.completed !== true) throw new Error(payload?.error || "complete_failed");
      const resultURL = new URL(payload.result_url);
      if (resultURL.origin !== window.location.origin || !resultURL.pathname.endsWith("/checkout-result/")) {
        throw new Error("invalid_result_url");
      }
      window.location.replace(resultURL.toString());
    } catch (completionError) {
      console.error(completionError);
      render("error", productID);
    }
  }

  const query = new URLSearchParams(window.location.search);
  const productID = query.get("product") ?? "";
  const result = query.get("result") ?? "invalid";
  if (result === "complete") {
    completeRedirect(query, productID);
  } else {
    render(result, productID);
  }
})();
