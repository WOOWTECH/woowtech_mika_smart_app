# Open Apporo Assistant from a browser

Apporo .7 adds the browser entry from WOOWTECH commit `3d419172`, using Apporo's own package and English web page. It retains the .6 offline speech guidance and persistent composer draft fixes.

Release URI: `com.apporo.assistant://open`. The dev variant uses `com.apporo.assistant.dev://open`; the manifest derives it from the installed application ID. Only Apporo has this entry in this change; it does not register WOOWTECH or upstream Mika schemes.

The exported, no-display activity checks ACTION_VIEW, the exact installed package scheme, authority `open` (no port or user info), and an empty or `/` path. It creates a fresh launcher intent. It does not forward URI queries, fragments, extras, ClipData, selectors or URI permissions. A link cannot select a conversation, send text, approve an action, run a task, grant accessibility access or unlock the phone. Invalid explicit component requests also finish without opening MainActivity.

## Web and LINE integration

The public entry is the Odoo page at https://www.apporo.ai/open-apporo-assistant. Its [Odoo view source](../apporo/web/open-apporo-assistant.odoo.xml) is kept with this repository (Odoo `ir.ui.view` 5203, website 1). Its button pins `package=com.apporo.assistant` and uses a fallback on the same page. Fallback displays recovery instructions without automatically retrying. Its download link points at the latest public Apporo release; Apporo .7 or later supports this entry. [The English standalone template](../apporo/web/open-apporo-assistant.html) keeps the same download destination. When changing the Odoo page, verify both the public page and a Chrome tap on Android; changing either source file alone does not deploy the Odoo page.

Use that HTTPS page URL in the Apporo LINE rich menu. The user taps **Open Apporo Assistant**; if the embedded browser blocks it, use LINE's **Open in browser** menu and tap in Chrome. Browser and device policy can prevent automatic redirects, so the page requires a deliberate click. It does not infer successful launch merely from a hidden page. No Apporo LINE account or rich menu has yet been selected; WOOWTECH's existing menu remains owned by its separate integration.

This is a custom deep link, not a verified HTTPS App Link. Website `assetlinks.json` verification would be a separate integration.

References: [Chrome Android intents](https://developer.chrome.com/docs/android/intents), [Android deep links](https://developer.android.com/training/app-links/create-deeplinks).

## Validation

Source and APK checks guard the browser registration and brand isolation. `node --test apporo/tools/test_browser_page.cjs` covers English branding, the compatible download, same-page fallback, no automatic retries, non-Android guidance and repeated taps. Physical acceptance must additionally cover a real Chrome button click, warm/cold launch, draft retention, hostile extras and invalid explicit entries. Results are recorded separately; a rendered page or successful ADB launch alone is not browser acceptance.
