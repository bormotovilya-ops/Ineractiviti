;(function () {
  var COOKIE_KEY = "ia_cookie_consent_v1";
  var VISITOR_KEY = "ia_visitor_id";
  var UTM_KEY = "ia_utm_data_v1";
  var LAST_PATH_KEY = "ia_last_path_v1";

  var SUPABASE_URL =
    typeof window !== "undefined" && window.__IA_SUPABASE_URL
      ? window.__IA_SUPABASE_URL
      : "";
  var SUPABASE_ANON_KEY =
    typeof window !== "undefined" && window.__IA_SUPABASE_ANON_KEY
      ? window.__IA_SUPABASE_ANON_KEY
      : "";

  function nowIso() {
    try {
      return new Date().toISOString();
    } catch (_) {
      return "";
    }
  }

  function safeJsonParse(v) {
    try {
      return JSON.parse(v);
    } catch (_) {
      return null;
    }
  }

  function getOrCreateVisitorId() {
    var existing = localStorage.getItem(VISITOR_KEY);
    if (existing) return existing;
    var id = "";
    try {
      id =
        "v_" +
        Date.now().toString(36) +
        "_" +
        Math.random().toString(36).slice(2, 10);
    } catch (_) {
      id = "v_fallback";
    }
    localStorage.setItem(VISITOR_KEY, id);
    return id;
  }

  function collectUtm() {
    var qp = new URLSearchParams(window.location.search || "");
    var keys = [
      "utm_source",
      "utm_medium",
      "utm_campaign",
      "utm_term",
      "utm_content",
      "utm_id",
      "gclid",
      "fbclid",
      "yclid",
    ];
    var utm = {};
    var has = false;
    for (var i = 0; i < keys.length; i += 1) {
      var k = keys[i];
      var val = qp.get(k);
      if (val) {
        utm[k] = val;
        has = true;
      }
    }
    if (!has) return null;
    return utm;
  }

  function updateUtmSnapshot() {
    var existing = safeJsonParse(localStorage.getItem(UTM_KEY)) || {};
    var incoming = collectUtm();
    var path = window.location.pathname || "/";
    localStorage.setItem(LAST_PATH_KEY, path);

    if (!existing.first_seen_at) existing.first_seen_at = nowIso();
    if (!existing.first_path) existing.first_path = path;
    if (!existing.first_referrer && document.referrer) {
      existing.first_referrer = document.referrer;
    }
    existing.last_seen_at = nowIso();
    existing.last_path = path;

    if (incoming) {
      for (var k in incoming) {
        if (Object.prototype.hasOwnProperty.call(incoming, k)) {
          existing[k] = incoming[k];
        }
      }
    }
    localStorage.setItem(UTM_KEY, JSON.stringify(existing));
    return existing;
  }

  function ensureStyles() {
    if (document.getElementById("ia-cookie-style")) return;
    var style = document.createElement("style");
    style.id = "ia-cookie-style";
    style.textContent =
      ".ia-cookie-consent{position:fixed;right:1rem;bottom:1rem;max-width:320px;z-index:9999;padding:.8rem .9rem;border-radius:12px;border:1px solid rgba(255,255,255,.14);background:rgba(10,10,18,.96);color:#e5e7eb;box-shadow:0 8px 24px rgba(0,0,0,.35);font:14px/1.35 system-ui,-apple-system,Segoe UI,sans-serif}" +
      ".ia-cookie-consent.hidden{display:none}" +
      ".ia-cookie-consent p{margin:0 0 .55rem;color:#cbd5e1}" +
      ".ia-cookie-consent button{width:100%;border:0;border-radius:999px;padding:.45rem .75rem;background:#6366f1;color:#fff;font-weight:700;cursor:pointer}" +
      ".ia-cookie-consent button:hover{filter:brightness(1.08)}";
    document.head.appendChild(style);
  }

  function ensureBanner() {
    var existing = document.getElementById("iaCookieConsent");
    if (existing) return existing;
    var box = document.createElement("div");
    box.id = "iaCookieConsent";
    box.className = "ia-cookie-consent hidden";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", "Согласие на использование cookie");
    box.innerHTML =
      '<p>Мы используем cookies.</p>' +
      '<button type="button" id="iaCookieAccept">Принять</button>';
    document.body.appendChild(box);
    return box;
  }

  function getConsent() {
    return safeJsonParse(localStorage.getItem(COOKIE_KEY));
  }

  async function sendConsentToSupabase(payload) {
    try {
      var res = await fetch(
        SUPABASE_URL + "/rest/v1/rpc/upsert_cookie_consent",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: SUPABASE_ANON_KEY,
            Authorization: "Bearer " + SUPABASE_ANON_KEY,
          },
          body: JSON.stringify(payload),
        }
      );
      if (!res.ok) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  function buildPayload(visitorId) {
    var utm = safeJsonParse(localStorage.getItem(UTM_KEY)) || {};
    return {
      p_visitor_id: visitorId,
      p_landing_path: utm.last_path || localStorage.getItem(LAST_PATH_KEY) || window.location.pathname || "/",
      p_referrer: utm.first_referrer || document.referrer || null,
      p_utm_source: utm.utm_source || null,
      p_utm_medium: utm.utm_medium || null,
      p_utm_campaign: utm.utm_campaign || null,
      p_utm_term: utm.utm_term || null,
      p_utm_content: utm.utm_content || null,
      p_utm_id: utm.utm_id || null,
      p_gclid: utm.gclid || null,
      p_fbclid: utm.fbclid || null,
      p_yclid: utm.yclid || null,
      p_consent_accepted: true,
      p_consented_at: nowIso(),
    };
  }

  async function acceptConsent() {
    var visitorId = getOrCreateVisitorId();
    var consent = {
      accepted: true,
      accepted_at: nowIso(),
      visitor_id: visitorId,
    };
    localStorage.setItem(COOKIE_KEY, JSON.stringify(consent));
    await sendConsentToSupabase(buildPayload(visitorId));
  }

  async function init() {
    getOrCreateVisitorId();
    updateUtmSnapshot();

    var consent = getConsent();
    if (consent && consent.accepted) {
      return;
    }

    ensureStyles();
    var banner = ensureBanner();
    var btn = document.getElementById("iaCookieAccept");
    banner.classList.remove("hidden");
    if (btn) {
      btn.addEventListener("click", async function () {
        btn.disabled = true;
        await acceptConsent();
        banner.classList.add("hidden");
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

