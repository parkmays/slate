/**
 * Minimal authenticated call to Frame.io V4: GET https://api.frame.io/v4/me
 * See docs/ADOBE_INTEGRATION.md for token handling and rate limits.
 */

const ME_URL = "https://api.frame.io/v4/me";

function init() {
  const tokenEl = document.getElementById("token");
  const outEl = document.getElementById("out");
  const probeBtn = document.getElementById("probe");

  probeBtn.addEventListener("click", async () => {
    const token = tokenEl.value.trim();
    if (!token) {
      outEl.textContent = "Paste an access token first.";
      return;
    }
    outEl.textContent = "Requesting…";
    try {
      const res = await fetch(ME_URL, {
        method: "GET",
        headers: {
          Authorization: "Bearer " + token,
          Accept: "application/json",
        },
      });
      const bodyText = await res.text();
      const limit = res.headers.get("x-ratelimit-limit");
      const remaining = res.headers.get("x-ratelimit-remaining");
      const windowMs = res.headers.get("x-ratelimit-window");
      let extra = "";
      if (limit || remaining || windowMs) {
        extra =
          "\n--- rate limit headers ---\nx-ratelimit-limit: " +
          (limit ?? "") +
          "\nx-ratelimit-remaining: " +
          (remaining ?? "") +
          "\nx-ratelimit-window: " +
          (windowMs ?? "");
      }
      outEl.textContent =
        res.status +
        " " +
        res.statusText +
        extra +
        "\n\n" +
        bodyText;
      if (res.status === 429) {
        outEl.textContent +=
          "\n\n(429: back off exponentially; see docs/ADOBE_INTEGRATION.md)";
      }
    } catch (err) {
      outEl.textContent = String(err);
    }
  });
}

document.addEventListener("DOMContentLoaded", init);
