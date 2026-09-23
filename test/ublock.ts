/**
 * Check the default AdGuard subscriptions, then that uBlock blocks a known ad script.
 *
 *   docker run -d --name helium-cdp -p 9222:9222 --shm-size=1g helium-cdp
 *   bun test/ublock.ts
 */
const endpoint = process.env.CDP_HTTP ?? "http://127.0.0.1:9222";
const adURL = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js";
const ublockId = "blockjmkbacgjkknlgpkjjiijinjdanf";
const expectedLists = [
  "user-filters",
  "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_2_Base/filter.txt",
  "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_3_Spyware/filter.txt",
  "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_14_Annoyances/filter.txt",
];
// The real adsbygoogle.js is about 200KB. uBlock replaces it with a short stub.

type VersionInfo = {
  Browser?: string;
  webSocketDebuggerUrl?: string;
};

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

async function waitForVersion(): Promise<VersionInfo> {
  const deadline = Date.now() + 60_000;
  let lastError = "DevTools 尚未响应";
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${endpoint}/json/version`);
      if (response.ok) return (await response.json()) as VersionInfo;
      lastError = `HTTP ${response.status}`;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await Bun.sleep(500);
  }
  fail(`等待 ${endpoint}/json/version 超时: ${lastError}`);
}

type CdpTarget = { targetId: string; type: string; url: string; title?: string };

function sameLists(actual: string[]): boolean {
  if (actual.length !== expectedLists.length) return false;
  const got = new Set(actual);
  return expectedLists.every((item) => got.has(item));
}

async function selectedFilterLists(browserURL: string): Promise<string[]> {
  const ws = new WebSocket(browserURL);
  await new Promise<void>((resolve, reject) => {
    ws.addEventListener("open", () => resolve(), { once: true });
    ws.addEventListener("error", () => reject(new Error("DevTools websocket 连接失败")), { once: true });
  });

  let next = 0;
  const pending = new Map<number, { resolve: (value: unknown) => void; reject: (error: Error) => void }>();
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(String(event.data)) as { id?: number; result?: unknown; error?: { message?: string } };
    if (!message.id || !pending.has(message.id)) return;
    const waiter = pending.get(message.id)!;
    pending.delete(message.id);
    if (message.error) waiter.reject(new Error(message.error.message ?? JSON.stringify(message.error)));
    else waiter.resolve(message.result);
  });

  const call = (method: string, params?: object, sessionId?: string) => {
    const id = ++next;
    return new Promise<unknown>((resolve, reject) => {
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params, sessionId }));
    });
  };

  try {
    const deadline = Date.now() + 120_000;
    let lastError = "还没有读到 selectedFilterLists";
    let sessionId = "";
    while (Date.now() < deadline) {
      try {
        if (!sessionId) {
          const discovered = (await call("Target.getTargets")) as { targetInfos?: CdpTarget[] };
          const target = discovered.targetInfos?.find((item) => item.url.includes(ublockId));
          if (!target) {
            lastError = "还没有 uBlock 扩展目标";
            await Bun.sleep(500);
            continue;
          }
          const attached = (await call("Target.attachToTarget", { targetId: target.targetId, flatten: true })) as {
            sessionId?: string;
          };
          if (!attached.sessionId) {
            lastError = "附加到 uBlock 扩展失败";
            await Bun.sleep(500);
            continue;
          }
          sessionId = attached.sessionId;
          await call("Runtime.enable", {}, sessionId);
        }
        const evaluated = (await call(
          "Runtime.evaluate",
          {
            expression: `new Promise((resolve) => {
              chrome.storage.local.get(["selectedFilterLists", "availableFilterLists"], (bin) => {
                const selected = (bin && bin.selectedFilterLists) || [];
                const available = (bin && bin.availableFilterLists) || {};
                const counts = {};
                for (const key of selected) {
                  const item = available[key] || {};
                  counts[key] = item.entryCount || 0;
                }
                resolve({ selected, counts });
              });
            })`,
            awaitPromise: true,
            returnByValue: true,
          },
          sessionId,
        )) as {
          result?: { value?: { selected?: string[]; counts?: Record<string, number> } };
          exceptionDetails?: { text?: string };
        };
        if (evaluated.exceptionDetails) {
          lastError = evaluated.exceptionDetails.text ?? "读取订阅列表失败";
          sessionId = "";
          await Bun.sleep(500);
          continue;
        }
        const lists = evaluated.result?.value?.selected ?? [];
        const counts = evaluated.result?.value?.counts ?? {};
        console.log(JSON.stringify({ lists, counts }));
        const loaded = expectedLists.every((item) => item === "user-filters" || (counts[item] ?? 0) > 1000);
        if (sameLists(lists) && loaded) return lists;
        lastError = `订阅尚未就绪: ${JSON.stringify({ lists, counts })}`;
      } catch (error) {
        sessionId = "";
        lastError = error instanceof Error ? error.message : String(error);
      }
      await Bun.sleep(500);
    }
    fail(`等待默认订阅超时: ${lastError}`);
  } finally {
    ws.close();
  }
}

const version = await waitForVersion();
const raw = version.webSocketDebuggerUrl;
if (!raw) fail(`/json/version 没有 webSocketDebuggerUrl`);
const socket = new URL(raw);
const pub = new URL(endpoint);
socket.protocol = pub.protocol === "https:" ? "wss:" : "ws:";
socket.hostname = pub.hostname;
socket.port = pub.port;

const lists = await selectedFilterLists(socket.toString());
console.log(`默认订阅: ${lists.join(", ")}`);

await using view = new Bun.WebView({
  width: 800,
  height: 600,
  backend: { type: "chrome", url: socket.toString() },
});

await view.navigate("https://example.com/");

const deadline = Date.now() + 120_000;
let last: { status?: number; len?: number; error?: string } = {};
while (Date.now() < deadline) {
  last = await view.evaluate(`(async () => {
    const url = ${JSON.stringify(adURL)} + "?t=" + Date.now();
    try {
      const response = await fetch(url);
      const text = await response.text();
      return { status: response.status, len: text.length };
    } catch (error) {
      return { error: error && error.message ? error.message : String(error) };
    }
  })()`);
  console.log(JSON.stringify(last));
  if (last.error || (typeof last.len === "number" && last.len < 20000)) break;
  await Bun.sleep(1000);
}

const blocked = Boolean(last.error) || (typeof last.len === "number" && last.len < 20000);
if (!blocked) {
  fail(`广告脚本没有被拦截: ${JSON.stringify(last)}`);
}
console.log("uBlock 已拦截广告脚本");
