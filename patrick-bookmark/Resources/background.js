const LIST_KIND = "bookmark";
const OUTLINE_PATH = {
    19: "images/star-19.png",
    32: "images/star-32.png",
    38: "images/star-38.png"
};
const FILL_PATH = {
    19: "images/star-fill-19.png",
    32: "images/star-fill-32.png",
    38: "images/star-fill-38.png"
};
const IN_TITLE = "Bookmarked";
const OUT_TITLE = "Not bookmarked";
const DEFAULT_TITLE = "Bookmark status";
const LOOKUP_POLL_MS = 500;

const lastStatusByTab = new Map();
const lastIconVisual = new Map();
const statusRevisionByTab = new Map();
let refreshInFlight = false;

pollActiveTabs();
setInterval(pollActiveTabs, LOOKUP_POLL_MS);

browser.windows.onFocusChanged.addListener(() => {
    pollActiveTabs();
});

browser.tabs.onActivated.addListener(({ tabId }) => {
    updateActiveTabStatus(tabId);
});

browser.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
    if (changeInfo.url || changeInfo.status === "complete") {
        await updateTabStatus(tabId, tab.url);
    }
});

browser.tabs.onRemoved.addListener((tabId) => {
    statusRevisionByTab.delete(tabId);
    lastStatusByTab.delete(tabId);
    lastIconVisual.delete(tabId);
});

browser.runtime.onMessage.addListener((request, _sender, sendResponse) => {
    if (request?.type !== "getStatus") return;

    const cached = lastStatusByTab.get(request.tabId);
    if (!request.force && cached?.url === request.url) {
        sendResponse(cached.result);
        return;
    }

    const revision = beginStatusRequest(request.tabId);
    lookupStatus(request.url)
        .then(async (result) => {
            if (typeof request.tabId === "number") {
                await commitStatus(request.tabId, request.url, result, revision, Boolean(request.force));
            }
            sendResponse(result);
        })
        .catch((error) => {
            sendResponse({ inList: false, hasAccess: false, error: String(error) });
        });
    return true;
});

function pollActiveTabs() {
    if (refreshInFlight) return;
    refreshInFlight = true;
    refreshActiveTabs()
        .catch(() => {})
        .finally(() => {
            refreshInFlight = false;
        });
}

async function refreshActiveTabs() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    for (const tab of tabs) {
        if (typeof tab.id === "number") {
            await updateTabStatus(tab.id, tab.url);
        }
    }
}

async function updateActiveTabStatus(tabId) {
    try {
        const tab = await browser.tabs.get(tabId);
        await updateTabStatus(tabId, tab.url);
    } catch {
        // Tabs can disappear between onActivated and tabs.get().
    }
}

async function updateTabStatus(tabId, url) {
    const revision = beginStatusRequest(tabId);
    const result = await lookupStatus(url);
    await commitStatus(tabId, url, result, revision);
    return result;
}

function beginStatusRequest(tabId) {
    if (typeof tabId !== "number") return null;
    const revision = (statusRevisionByTab.get(tabId) ?? 0) + 1;
    statusRevisionByTab.set(tabId, revision);
    return revision;
}

async function commitStatus(tabId, url, result, revision, force = false) {
    if (statusRevisionByTab.get(tabId) !== revision) return;
    if (!(await tabStillHasURL(tabId, url))) return;
    if (statusRevisionByTab.get(tabId) !== revision) return;
    lastStatusByTab.set(tabId, { url, result });
    if (force) lastIconVisual.delete(tabId);
    await applyIcon(tabId, url, result, revision);
}

async function tabStillHasURL(tabId, url) {
    try {
        const tab = await browser.tabs.get(tabId);
        return tab.url === url;
    } catch {
        return false;
    }
}

async function lookupStatus(url) {
    if (typeof url !== "string" || (!url.startsWith("http://") && !url.startsWith("https://"))) {
        return { inList: false, hasAccess: false, error: "unsupported_url" };
    }

    const result = await sendNative({ action: "lookup", url, list: LIST_KIND });
    return {
        inList: Boolean(result?.inList),
        hasAccess: Boolean(result?.hasAccess),
        folderUUID: result?.folderUUID ?? null,
        error: result?.error ?? null
    };
}

async function sendNative(payload) {
    try {
        return unwrapNative(await browser.runtime.sendNativeMessage(payload));
    } catch (error) {
        if (String(error).includes("Other version in use")) {
            return { inList: false, hasAccess: false, error: "other_version_in_use" };
        }
        throw error;
    }
}

async function applyIcon(tabId, url, result, revision) {
    const filled = Boolean(result.inList);
    const visualKey = `${url}:${filled ? "fill" : "outline"}`;
    if (lastIconVisual.get(tabId) === visualKey) return;

    try {
        if (statusRevisionByTab.get(tabId) !== revision) return;
        await browser.action.setTitle({
            tabId,
            title: filled ? IN_TITLE : (result.hasAccess ? OUT_TITLE : DEFAULT_TITLE)
        });
        if (statusRevisionByTab.get(tabId) !== revision) return;
        await browser.action.setIcon({ tabId, path: filled ? FILL_PATH : OUTLINE_PATH });
        if (statusRevisionByTab.get(tabId) !== revision) return;
        lastIconVisual.set(tabId, visualKey);
    } catch (error) {
        if (String(error).includes("Tab not found")) return;
        console.error("patrick-bookmark icon failed", error);
        try {
            await browser.action.setIcon({ tabId, path: filled ? FILL_PATH : OUTLINE_PATH });
        } catch {
            // The tab may have closed while falling back to the static PNG.
        }
        lastIconVisual.delete(tabId);
    }
}

function unwrapNative(result) {
    if (!result || typeof result !== "object") return {};
    if (result.inList !== undefined || result.hasAccess !== undefined) {
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
