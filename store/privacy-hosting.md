# 隐私政策 / 法务页托管方案

## 问题

App Store Connect 的 **隐私政策 URL 是必填项，且必须公开可访问**。
当前 `https://wonangfei.app/privacy`、`/terms` 全部连不上（`curl` 返回 `000` = 域名没解析 / 没部署）。

同时 App 里也用到这个域名：
- `WNF/Legal.swift` 先加载 `https://wonangfei.app/privacy`，**失败时回退到 App 内置的本地 HTML**，所以 App 内法务页离线可用——域名打不开不影响 App 本身，只卡 ASC 那一栏。
- `WNF/WNF.entitlements` 有 `applinks:wonangfei.app`（通用链接），需要域名上放 AASA 文件才生效（不影响上架）。

**真正完整的法务文档是 App 内置的这两个文件**（根目录 `legal/*.html` 是旧占位，别用）：
- `WNF/Legal/privacy.html`
- `WNF/Legal/terms.html`

要托管就托管这两份，保证 App 内、网页版、ASC 三处内容一致。

---

## 方案 A（推荐，长期）：把 wonangfei.app 真正部署起来

如果你**拥有 wonangfei.app 这个域名**，这一步能一次性解决三件事：ASC 隐私 URL、App 内远程加载、通用链接。

用任意免费静态托管（GitHub Pages / Cloudflare Pages / Vercel / Netlify 均可），目录结构做成：

```
/
├── privacy/index.html            ← 复制 WNF/Legal/privacy.html
├── terms/index.html              ← 复制 WNF/Legal/terms.html
└── .well-known/
    └── apple-app-site-association  ← 已为你生成：store/site/.well-known/apple-app-site-association
```

这样 `wonangfei.app/privacy`、`/terms` 就能干净访问（和 `Legal.swift` 里的路径完全对上）。

一键把要部署的目录拼好（从权威文件复制，不手抄、避免内容漂移）：

```sh
cd /Users/shelingzhao/Developer/AppleApps/wonangfei
rm -rf store/site/privacy store/site/terms
mkdir -p store/site/privacy store/site/terms
cp WNF/Legal/privacy.html store/site/privacy/index.html
cp WNF/Legal/terms.html   store/site/terms/index.html
echo "可部署目录已就绪：store/site/"
```

然后把 `store/site/` 整个目录发布到你的托管，并把自定义域名绑到 wonangfei.app。

### AASA（通用链接）注意事项
- 文件路径必须是 `/.well-known/apple-app-site-association`，**无扩展名**。
- 必须走 **HTTPS**、返回 `Content-Type: application/json`、**不能有重定向**。
- 内容已按你的 `TeamID.BundleID = TZ2T95MG29.com.wonangfei.app` 生成好。
- 验证：`curl -sI https://wonangfei.app/.well-known/apple-app-site-association`（看 200 + json 类型）。
- 如果 v1 不打算做通用链接，这个文件可不放，`applinks` entitlement 留着也无害。

---

## 方案 B（最快，先上架）：直接用一个能访问的 URL 填 ASC

ASC 的隐私政策 URL **不要求和 App 的 bundle 域名一致**——任何可访问的 HTTPS 页面都行。
所以不想折腾 DNS 的话，最快路径：

1. 新建一个公开仓库（如 `wonangfei-legal`），把 `WNF/Legal/privacy.html`、`terms.html` 传上去。
2. 打开 GitHub Pages（Settings → Pages → Deploy from branch）。
3. 拿到形如 `https://<你的用户名>.github.io/wonangfei-legal/privacy.html` 的地址，填进 ASC 的「隐私政策 URL」。

代价：通用链接暂时不生效（不影响上架），App 内远程加载仍会回退到本地副本（用户无感）。等以后再做方案 A 把 wonangfei.app 接上即可。

---

## 支持 URL（Support URL，也是必填）

ASC 还要一个「支持 URL」（不是邮箱，得是网页）。三选一：
- 方案 A 的站点加一页 `support/index.html`（写一句联系方式 + 邮箱 `raysyadesu@gmail.com`）。
- 或直接复用隐私页地址临时顶上。
- 或一个公开的 Notion / 简单落地页。

---

## 我能帮你做的

- ✅ 已生成 AASA 文件、可部署目录脚本（见上）。
- 需要的话我可以：把 `store/site/` 目录拼好（跑上面的 `cp` 脚本）、写一个 `support` 页、或初始化 GitHub Pages 仓库（涉及推到你的 GitHub，会先问你）。

> 注：是否拥有 wonangfei.app、用哪个托管，是你的决定。我不会未经你同意往外部服务部署东西。
