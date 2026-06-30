/* First-touch marketing attribution capture — Analytically marketing site.
 *
 * Captures the campaign/channel signals present when a visitor first lands this
 * session (UTM params, gclid, referrer, landing page) into sessionStorage, so the
 * enquiry form can submit "how they arrived" next to "who they are" — the stitch
 * that lets a lead later be tied back to GA and downstream to a patient record.
 *
 * These are URL/navigation values (NOT cookies), so they are captured regardless
 * of cookie consent. The GA client_id (cookie-based, joins to GA BigQuery's
 * user_pseudo_id) is added separately by the form, and only exists once the
 * visitor has accepted analytics cookies.
 */
(function () {
    'use strict';

    var KEY = 'anly_first_touch';

    function readJSON(k)  { try { return JSON.parse(sessionStorage.getItem(k) || 'null'); } catch (e) { return null; } }
    function writeJSON(k, v) { try { sessionStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }

    var params = new URLSearchParams(location.search);
    function p(name) { return params.get(name) || ''; }

    // Capture first touch once per session — the entry URL is where the campaign
    // signals live, and they're lost as soon as the visitor navigates onward.
    if (!readJSON(KEY)) {
        writeJSON(KEY, {
            utm_source:   p('utm_source'),
            utm_medium:   p('utm_medium'),
            utm_campaign: p('utm_campaign'),
            utm_term:     p('utm_term'),
            utm_content:  p('utm_content'),
            gclid:        p('gclid'),
            referrer:     document.referrer || '',
            landing_page: location.pathname + location.search,
            captured_at:  new Date().toISOString()
        });
    }

    // Exposes the captured first-touch attribution to the enquiry form.
    window.anlyAttribution = function () {
        return readJSON(KEY) || {
            utm_source: '', utm_medium: '', utm_campaign: '', utm_term: '',
            utm_content: '', gclid: '', referrer: '', landing_page: '', captured_at: ''
        };
    };
})();
