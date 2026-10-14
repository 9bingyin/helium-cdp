/**
 * Connect to a running helium-cdp container with Bun.WebView and check that
 * CJK text is backed by Noto CJK (not a missing-glyph fallback).
 *
 *   docker run -d --name helium-cdp -p 9222:9222 --shm-size=1g helium-cdp
 *   bun test/cdp.ts
 */
const endpoint = process.env.CDP_HTTP ?? "http://127.0.0.1:9222";

type VersionInfo = {
  Browser?: string;
  "Protocol-Version"?: string;
  webSocketDebuggerUrl?: string;
};

const html = `<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<title>cjk</title>
<style>
  html, body { margin: 0; background: #fff; color: #111; }
  body {
    font-family: sans-serif;
    font-size: 64px;
    line-height: 1.35;
    padding: 24px;
  }
</style>
<body>
  中文测试<br>
  日本語テスト<br>
  한글 테스트
</body>
</html>`;

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
      if (response.ok) {
        return (await response.json()) as VersionInfo;
      }
      lastError = `HTTP ${response.status}`;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await Bun.sleep(500);
  }
  fail(`等待 ${endpoint}/json/version 超时: ${lastError}`);
}

function browserSocket(version: VersionInfo): string {
  const raw = version.webSocketDebuggerUrl;
  if (!raw) fail(`/json/version 没有 webSocketDebuggerUrl: ${JSON.stringify(version)}`);
  const socket = new URL(raw);
  const pub = new URL(endpoint);
  socket.protocol = pub.protocol === "https:" ? "wss:" : "ws:";
  socket.hostname = pub.hostname;
  socket.port = pub.port;
  return socket.toString();
}

const version = await waitForVersion();
const browser = version.Browser ?? "";
console.log("Browser:", browser);
console.log("Protocol-Version:", version["Protocol-Version"]);
if (!/Chrome|Chromium|Helium/i.test(browser)) {
  fail(`无法识别的浏览器标识: ${browser}`);
}

const socketURL = browserSocket(version);
console.log("DevTools:", socketURL);

await using view = new Bun.WebView({
  width: 960,
  height: 540,
  backend: {
    type: "chrome",
    url: socketURL,
  },
});

await view.navigate("data:text/html;charset=utf-8," + encodeURIComponent(html));

const result = await view.evaluate(`(() => {
  const samples = [
    ["Noto Sans CJK SC", "中文测试"],
    ["Noto Sans CJK JP", "日本語テスト"],
    ["Noto Sans CJK KR", "한글 테스트"],
    ["Noto Serif CJK SC", "中文测试"],
  ];
  const checks = {};
  for (const [family, text] of samples) {
    checks[family] = document.fonts.check('64px "' + family + '"', text);
  }
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  ctx.font = "64px sans-serif";
  const width = ctx.measureText("中文测试").width;
  return {
    title: document.title,
    text: document.body.innerText,
    checks,
    sansWidth: width,
  };
})()`);

console.log(JSON.stringify(result, null, 2));

const checks = result?.checks ?? {};
for (const [family, ok] of Object.entries(checks)) {
  if (ok !== true) fail(`字体不可用: ${family}`);
}
if (typeof result?.sansWidth !== "number" || result.sansWidth < 128) {
  fail(`sans-serif 下「中文测试」宽度异常: ${result?.sansWidth}`);
}
if (!String(result?.text ?? "").includes("中文测试")) {
  fail("页面没有渲染出中文文本");
}

const png = await view.screenshot({ encoding: "buffer" });
if (png.length < 1024 || png[0] !== 0x89 || png[1] !== 0x50) {
  fail(`截图不是有效 PNG（${png.length} 字节）`);
}
console.log("CDP 与 CJK 字体检查通过");
