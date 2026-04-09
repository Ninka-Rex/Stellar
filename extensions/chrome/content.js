// content.js – injected into all pages
// Tracks modifier keys on download link clicks and notifies the service worker

document.addEventListener("click", (e) => {
    const target = e.target.closest("a");
    if (!target || !target.href) return;

    // Determine which modifier key is held (0=none, 1=alt, 2=ctrl, 3=shift)
    let modifierKey = 0;
    if (e.altKey) modifierKey = 1;
    else if (e.ctrlKey) modifierKey = 2;
    else if (e.shiftKey) modifierKey = 3;

    // Only notify if a modifier key was held
    if (modifierKey > 0) {
        chrome.runtime.sendMessage({
            type: "recordModifierKey",
            modifierKey: modifierKey,
        }).catch(() => {
            // Service worker may not be ready, ignore
        });
    }
}, true);  // Use capture phase to intercept all clicks
