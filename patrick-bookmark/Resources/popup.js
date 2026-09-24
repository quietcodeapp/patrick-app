const statusEl = document.getElementById("status");
const hintEl = document.getElementById("hint");
const folderSelectEl = document.getElementById("folder-select");
const primaryActionEl = document.getElementById("primary-action");
const LIST_KIND = "bookmark";
let currentTab;
let currentStatus = null;
let folders = [];
let defaultFolderUUID = "";

primaryActionEl.addEventListener("click", () => {
    runPrimaryAction().catch((error) => {
        hintEl.textContent = String(error);
        hintEl.hidden = false;
        primaryActionEl.disabled = false;
    });
});

folderSelectEl.addEventListener("change", () => {
    if (!currentStatus?.inList) return;
    moveToSelectedFolder().catch((error) => {
        hintEl.textContent = String(error);
        hintEl.hidden = false;
        folderSelectEl.disabled = false;
    });
});

async function refresh() {
    try {
        statusEl.hidden = true;
        hintEl.hidden = true;
        const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
        currentTab = tab;
        if (!tab?.id) {
            statusEl.textContent = "No active tab.";
            statusEl.hidden = false;
            primaryActionEl.hidden = true;
            return;
        }

        if (typeof tab.url !== "string" || (!tab.url.startsWith("http://") && !tab.url.startsWith("https://"))) {
            statusEl.textContent = "This page cannot be bookmarked.";
            statusEl.hidden = false;
            hintEl.textContent = "Open an http or https page.";
            hintEl.hidden = false;
            primaryActionEl.hidden = true;
            folderSelectEl.disabled = true;
            return;
        }

        const [statusResult, foldersResult] = await Promise.all([
            browser.runtime.sendMessage({ type: "getStatus", tabId: tab.id, url: tab.url, force: true }),
            browser.runtime.sendNativeMessage({ action: "folders" })
        ]);

        folders = unwrapNative(foldersResult)?.folders ?? [];
        defaultFolderUUID = unwrapNative(foldersResult)?.lastFolderUUID ?? "";
        applyFolders(statusResult?.folderUUID);

        if (!statusResult) {
            statusEl.textContent = "Could not read status.";
            statusEl.hidden = false;
            hintEl.textContent = "Reload this tab, then open the popup again.";
            hintEl.hidden = false;
            primaryActionEl.hidden = true;
            return;
        }

        if (!statusResult.hasAccess) {
            statusEl.textContent = "Safari is not connected yet.";
            statusEl.hidden = false;
            hintEl.textContent = "Open the Patrick app and tap Connect Safari.";
            hintEl.hidden = false;
            primaryActionEl.hidden = true;
            folderSelectEl.disabled = true;
            return;
        }

        currentStatus = statusResult;
        applyBookmarkUI(statusResult);
    } catch (error) {
        statusEl.textContent = "Could not read status.";
        statusEl.hidden = false;
        hintEl.textContent = String(error);
        hintEl.hidden = false;
        primaryActionEl.hidden = true;
    }
}

function applyFolders(selectedUUID) {
    folderSelectEl.innerHTML = "";
    if (!folders.length) {
        const option = document.createElement("option");
        option.value = "";
        option.textContent = "No folders found";
        folderSelectEl.appendChild(option);
        folderSelectEl.disabled = true;
        return;
    }

    for (const folder of folders) {
        const option = document.createElement("option");
        option.value = folder.uuid;
        option.textContent = `${"  ".repeat(folder.depth)}${folder.title}`;
        folderSelectEl.appendChild(option);
    }

    const rootUUID = folders.find((folder) => folder.depth === 0)?.uuid || folders[0]?.uuid || "";
    const preferred = [selectedUUID, defaultFolderUUID, rootUUID].find((uuid) =>
        uuid && folders.some((folder) => folder.uuid === uuid)
    ) || "";
    if (preferred) folderSelectEl.value = preferred;
    folderSelectEl.disabled = false;
}

function applyBookmarkUI(result) {
    hintEl.textContent = result.error ? String(result.error) : "";
    hintEl.hidden = !result.error;
    if (result.inList) {
        primaryActionEl.textContent = "Remove";
        primaryActionEl.dataset.action = "remove";
        if (result.folderUUID) folderSelectEl.value = result.folderUUID;
    } else {
        primaryActionEl.textContent = "Add";
        primaryActionEl.dataset.action = "add";
        if (!folderSelectEl.value && defaultFolderUUID) {
            folderSelectEl.value = defaultFolderUUID;
        }
    }
    primaryActionEl.hidden = false;
    primaryActionEl.disabled = false;
}

async function runPrimaryAction() {
    if (!currentTab?.id) return;
    primaryActionEl.disabled = true;
    const action = primaryActionEl.dataset.action;
    const payload = {
        action,
        url: currentTab.url,
        title: currentTab.title,
        list: LIST_KIND,
        folderUUID: folderSelectEl.value || undefined
    };
    const result = unwrapNative(await browser.runtime.sendNativeMessage(payload));
    await browser.runtime.sendMessage({
        type: "getStatus",
        tabId: currentTab.id,
        url: currentTab.url,
        force: true
    });
    currentStatus = result;
    applyBookmarkUI(result);
    primaryActionEl.disabled = false;
}

async function moveToSelectedFolder() {
    if (!currentTab?.id || !currentStatus?.inList) return;
    const folderUUID = folderSelectEl.value;
    if (!folderUUID || folderUUID === currentStatus.folderUUID) return;

    folderSelectEl.disabled = true;
    hintEl.textContent = "Changing folder…";
    hintEl.hidden = false;
    try {
        const result = unwrapNative(await browser.runtime.sendNativeMessage({
            action: "move",
            url: currentTab.url,
            folderUUID,
            list: LIST_KIND
        }));
        currentStatus = result;
        applyBookmarkUI(result);
        await browser.runtime.sendMessage({
            type: "getStatus",
            tabId: currentTab.id,
            url: currentTab.url,
            force: true
        });
        if (!result.error) {
            hintEl.textContent = "Folder changed.";
            hintEl.hidden = false;
        }
    } finally {
        folderSelectEl.disabled = folders.length === 0;
    }
}

function unwrapNative(result) {
    if (!result || typeof result !== "object") return {};
    if (result.inList !== undefined || result.hasAccess !== undefined || result.folders !== undefined) {
        return result;
    }
    let message = result.message;
    if (typeof message === "string") {
        try {
            message = JSON.parse(message);
        } catch {
            return {};
        }
    }
    if (message && typeof message === "object") return message;
    return {};
}

refresh();
