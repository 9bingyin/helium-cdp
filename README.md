# helium-cdp

用 [Helium](https://github.com/imputnet/helium-linux) 替代 [`chromedp/headless-shell`](https://github.com/chromedp/docker-headless-shell)。容器在 **9222** 提供 CDP，预装 Noto CJK。默认 Helium **0.17.2.1**（Chromium 153.0.8010.52）。屏幕和页面视口是 **1280×720**。

## 运行

```sh
docker build -t helium-cdp .
docker run -d --name helium-cdp -p 9222:9222 --shm-size=1g helium-cdp
curl -s http://127.0.0.1:9222/json/version
```

`--shm-size` 至少 1GB。追加的参数会传给浏览器，重复的开关以后面的为准。

```go
ctx, cancel := chromedp.NewRemoteAllocator(context.Background(), "http://127.0.0.1:9222")
defer cancel()
```

## uBlock

默认订阅这三份 [AdGuard 过滤器](https://adguard.com/kb/zh-CN/general/ad-filtering/adguard-filters/)（[FiltersRegistry](https://github.com/AdguardTeam/FiltersRegistry)）：

- 基础过滤器 `filter_2_Base`
- 防跟踪保护过滤器 `filter_3_Spyware`
- 恼人广告过滤器 `filter_14_Annoyances`（含 Cookie 通知、弹窗、移动应用横幅、小工具和其他烦恼）

列表由 uBlock 从 GitHub 更新。浏览器自身不自动升级。过滤引擎装好前的头几秒，请求可能还不会被拦。

自定义规则挂到 `/etc/helium/ublock/user-filters.txt`，一行一条。空行和以 `#` 开头的行会忽略。`/etc/helium/ublock/filter-lists.txt` 会整份替换默认订阅；同时还要自定义规则时，里面留一行 `user-filters`。示例是 `examples/user-filters.txt`。

```sh
docker run -d --name helium-cdp -p 9222:9222 --shm-size=1g \
  -v "$PWD/examples/user-filters.txt:/etc/helium/ublock/user-filters.txt:ro" \
  helium-cdp
```

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `HELIUM_PUBLIC_PORT` | `9222` | 对外的 DevTools 端口 |
| `HELIUM_DEBUG_PORT` | `9223` | 浏览器在容器内监听的端口 |
| `HELIUM_UBLOCK_FILTERS` | `/etc/helium/ublock/user-filters.txt` | 自定义规则文件 |
| `HELIUM_UBLOCK_LISTS` | `/etc/helium/ublock/filter-lists.txt` | 自定义订阅文件 |

构建参数 `HELIUM_VERSION` 默认 `0.17.2.1`。构建时用 `image/pubkey.asc` 校验安装包签名。

## 许可

构建脚本是 MIT，见 [LICENSE](LICENSE)。Helium 浏览器是 GPL-3.0。
