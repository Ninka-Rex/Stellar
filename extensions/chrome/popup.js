// popup.js – Stellar Chrome extension popup
document.addEventListener("DOMContentLoaded", async () => {
    const statusEl = document.getElementById("status");

    // Ask the service worker to ping the native host
    chrome.runtime.sendMessage({ type: "ping" }, (resp) => {
        if (chrome.runtime.lastError || !resp?.alive) {
            statusEl.textContent = "Stellar is not running.";
            statusEl.style.color = "#f38ba8";
        } else {
            statusEl.textContent = "Connected to Stellar.";
            statusEl.style.color = "#a6e3a1";
        }
    });

    document.getElementById("openApp").addEventListener("click", () => {
        chrome.runtime.sendNativeMessage("com.stellar.downloadmanager", { type: "focus" });
        window.close();
    });
});
