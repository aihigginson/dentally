/* Marketing attribution capture — Analytically marketing site.
 *
 * Captures the campaign/channel signals from the URL (UTM params, gclid) plus
 * referrer and landing page into sessionStorage, so the enquiry form can submit
 * "how they arrived" next to "who they are" — the stitch that lets a lead later
 * be tied back to GA and downstream to a patient record.
 *
 * Capture rule:
 *   - A URL carrying campaign params (any utm_* or gclid) is ALWAYS recorded
 *     (last campaign touch wins) — so a param-less page seen earlier in the
 *     session can't lock out a later ad click.
 *   - Otherwise, if nothing is stored yet, record a baseline (direct / referrer).
 *   - Otherwise keep the existing campaign touch.
 *
 * These are URL/navigation values (NOT cookies), captured regardless of cookie
 * consent. The GA client_id (cookie-based, joins to GA BigQuery's user_pseudo_id)
 * is added separately by the form, and only once analytics cookies are accepted.
 */
(function () {
    'use strict';

    var KEY = 'anly_attribution';

    function readJSON(k)    { try { return JSON.parse(sessionStorage.getItem(k) || 'null'); } catch (e) { return null; } }
    function writeJSON(k, v) { try { sessionStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }

    var params = new URLSearchParams(location.search);
    function p(name) { return params.get(name) || ''; }

    var current = {
        utm_source:   p('utm_source'),
        utm_medium:   p('utm_medium'),
        utm_campaign: p('utm_campaign'),
        utm_term:     p('utm_term'),
        utm_content:  p('utm_content'),
        gclid:        p('gclid'),
        referrer:     document.referrer || '',
        landing_page: location.pathname + location.search,
        captured_at:  new Date().toISOString()
    };

    var hasCampaign = !!(current.utm_source || current.utm_medium || current.utm_campaign ||
                         current.utm_term || current.utm_content || current.gclid);

    if (hasCampaign) {
        writeJSON(KEY, current);            // campaign touch — always record it
    } else if (!readJSON(KEY)) {
        writeJSON(KEY, current);            // first visit of the session — baseline
    }                                        // else keep the stored campaign touch

    // Exposes the captured attribution to the enquiry form.
    window.anlyAttribution = function () {
        return readJSON(KEY) || {
            utm_source: '', utm_medium: '', utm_campaign: '', utm_term: '',
            utm_content: '', gclid: '', referrer: '', landing_page: '', captured_at: ''
        };
    };
})();
