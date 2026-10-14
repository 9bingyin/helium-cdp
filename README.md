# helium-cdp

用 [Helium](https://github.com/imputnet/helium-linux) 在 9222 提供 CDP。字体是 Noto CJK。屏幕是 1280×720。版本来自 [helium-bin](https://github.com/9bingyin/nur-packages)。

```sh
nix build .#image
./result | docker load
version=$(nix eval --raw .#image.heliumVersion)
docker tag "helium-cdp:$version" helium-cdp:latest
docker run -d --name helium-cdp -p 9222:9222 --shm-size=1g helium-cdp
curl -s http://127.0.0.1:9222/json/version
```

`--shm-size` 至少 1GB。追加的参数会传给浏览器，重复的开关以后面的为准。

自定义规则挂到 `/etc/helium/ublock/user-filters.txt`，一行一条。空行和以 `#` 开头的行会忽略。`/etc/helium/ublock/filter-lists.txt` 会整份替换默认订阅。替换后还要自定义规则时，里面留一行 `user-filters`。

构建脚本是 MIT，见 [LICENSE](LICENSE)。Helium 浏览器是 GPL-3.0。
