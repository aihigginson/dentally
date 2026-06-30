/* Cookie consent + gated Google Analytics — Analytically marketing site.
 *
 * PECR/UK GDPR opt-in: Google Analytics (gtag.js) is NOT loaded and NO cookies
 * are set until the visitor clicks "Accept". The choice is stored in
 * localStorage so the banner shows only once; users can change it any time via
 * a "Cookie settings" link (window.anlyCookieSettings).
 */
(function () {
    'use strict';

    var GA_ID = 'G-VZ89XSHWQZ';
    var KEY   = 'anly_cookie_consent';   // 'granted' | 'denied'

    function read()  { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
    function store(v) { try { localStorage.setItem(KEY, v); } catch (e) {} }

    // Load and initialise GA4 — only ever called after explicit consent.
    function loadGA() {
        if (window.__anlyGA) return;
        window.__anlyGA = true;
        var s = document.createElement('script');
        s.async = true;
        s.src = 'https://www.googletagmanager.com/gtag/js?id=' + GA_ID;
        document.head.appendChild(s);
        window.dataLayer = window.dataLayer || [];
        window.gtag = function () { window.dataLayer.push(arguments); };
        window.gtag('js', new Date());
        window.gtag('config', GA_ID);
    }

    var bannerEl = null;
    function removeBanner() {
        if (bannerEl && bannerEl.parentNode) { bannerEl.parentNode.removeChild(bannerEl); }
        bannerEl = null;
    }

    function decide(v) {
        store(v);
        removeBanner();
        if (v === 'granted') { loadGA(); }
    }

    function injectStyles() {
        if (document.getElementById('anly-cc-style')) return;
        var css =
            '#anly-cookie-banner{position:fixed;left:0;right:0;bottom:0;z-index:2000;display:flex;justify-content:center;padding:16px;}' +
            '#anly-cookie-banner .anly-cc-card{background:#fff;border:1px solid #E4E8EE;border-radius:12px;box-shadow:0 8px 40px rgba(26,82,122,.18);max-width:680px;width:100%;padding:18px 20px;display:flex;align-items:center;gap:18px;flex-wrap:wrap;font-family:"Segoe UI",system-ui,-apple-system,sans-serif;}' +
            '#anly-cookie-banner .anly-cc-text{flex:1;min-width:240px;font-size:13.5px;line-height:1.55;color:#1F2937;}' +
            '#anly-cookie-banner .anly-cc-text a{color:#1A527A;font-weight:600;}' +
            '#anly-cookie-banner .anly-cc-actions{display:flex;gap:10px;flex-shrink:0;}' +
            '#anly-cookie-banner .anly-cc-btn{font-family:inherit;font-size:14px;font-weight:600;padding:10px 22px;border-radius:8px;cursor:pointer;border:1px solid #1A527A;}' +
            '#anly-cookie-banner .anly-cc-reject{background:#fff;color:#1A527A;}' +
            '#anly-cookie-banner .anly-cc-reject:hover{background:#F8FAFC;}' +
            '#anly-cookie-banner .anly-cc-accept{background:#1A527A;color:#fff;}' +
            '#anly-cookie-banner .anly-cc-accept:hover{background:#163f5e;}' +
            '@media(max-width:520px){#anly-cookie-banner .anly-cc-actions{width:100%;}#anly-cookie-banner .anly-cc-btn{flex:1;}}';
        var st = document.createElement('style');
        st.id = 'anly-cc-style';
        st.textContent = css;
        document.head.appendChild(st);
    }

    function buildBanner() {
        removeBanner();
        var wrap = document.createElement('div');
        wrap.id = 'anly-cookie-banner';
        wrap.setAttribute('role', 'dialog');
        wrap.setAttribute('aria-label', 'Cookie consent');
        wrap.innerHTML =
            '<div class="anly-cc-card">' +
                '<div class="anly-cc-text">' +
                    'We use <strong>Google Analytics</strong> cookies to understand how this ' +
                    'site is used — but only if you agree. No analytics cookies are set unless ' +
                    'you accept. See our <a href="/doc.html?doc=COOKIE_POLICY">Cookie Policy</a>.' +
                '</div>' +
                '<div class="anly-cc-actions">' +
                    '<button type="button" class="anly-cc-btn anly-cc-reject">Reject</button>' +
                    '<button type="button" class="anly-cc-btn anly-cc-accept">Accept</button>' +
                '</div>' +
            '</div>';
        document.body.appendChild(wrap);
        wrap.querySelector('.anly-cc-accept').addEventListener('click', function () { decide('granted'); });
        wrap.querySelector('.anly-cc-reject').addEventListener('click', function () { decide('denied'); });
        bannerEl = wrap;
    }

    function showBanner() { injectStyles(); buildBanner(); }

    // Footer "Cookie settings" link calls this to let users change their choice.
    window.anlyCookieSettings = function () { showBanner(); };

    // On load: honour a stored choice; otherwise prompt for consent.
    var choice = read();
    if (choice === 'granted') {
        loadGA();
    } else if (choice !== 'denied') {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', showBanner);
        } else {
            showBanner();
        }
    }
})();
