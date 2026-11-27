/* Bot list landing (owner 2026-11-27), the same file as Android fa22299c; iOS runs it in an isolated WKContentWorld. Reads markup structure and the website's fixed loading-state key only: no text, value,
   cookie or storage, no network, no native interface. Its one action is a click on the website's own "open bot list" button,
   when asked and the phone list is closed. */
(function (open) {
  const app = document.querySelector('[data-look="app"]');
  if (!app) {
    // The sign-in and pairing pages come before the workspace app.
    if (document.querySelector('input:not([type=hidden]), textarea')) return 'form';
    // Still starting: the website renders into its empty #root once the session is checked and the app code has loaded.
    const root = document.getElementById('root');
    return root && !root.firstElementChild ? 'boot' : 'none';
  }
  // The website's loading screen while it connects or updates; 'app.loading.noBots' is a connected workspace without bots.
  const loading = app.querySelector('[data-app-loading]');
  if (loading && loading.getAttribute('data-app-loading') !== 'app.loading.noBots') return 'connecting';
  // Bots not in the list yet: opening it now would be undone when the selected bot loads.
  if (!loading && !app.querySelector('[data-sidebar-bot-row]')) return 'app';
  // On a phone the list covers the chat, opened by the first button of the area that holds the list. On a wide screen the
  // button is hidden because the list is beside the chat.
  let area = app.querySelector('[data-look="sidebar"]');
  while (area && area.parentElement !== app) area = area.parentElement;
  const button = area && area.firstElementChild;
  if (!button || button.tagName !== 'BUTTON' || !button.hasAttribute('aria-expanded') || !button.getClientRects().length) return 'wide';
  if (button.getAttribute('aria-expanded') === 'true') return 'open';
  if (!open) return 'closed';
  button.click();
  return 'opening';
})(__WOOW_OPEN__)
