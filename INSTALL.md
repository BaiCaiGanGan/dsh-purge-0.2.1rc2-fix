# 安装说明（DSH Desktop 0.2.1-rc.2）

## 这个包是什么

- 基于上游 [dsh-purge](https://github.com/YuJunZhiXue/dsh-purge) `1.1.71`（commit `6c1d638`，MIT）
- 叠加了针对 **DSH Desktop 0.2.1-rc.2** 的 6 处适配修复，详见 [FORK-NOTES.md](FORK-NOTES.md) 与 [FIXES.md](FIXES.md)
- **不要**直接 `pnpm add dsh-purge`（装到的是上游未修复版）

## 第 0 步 · 确认版本

修复是针对 **0.2.1-rc.2** 写的（且都是版本自适应写法），但**不要**装到比 `0.2.0` 更老的 DSH 上。

## 第 1 步 · 装包

```bash
cd <DSH_HOME>/profiles/desktop          # DSH_HOME 默认是 ~/.dsh
```

三种方式，任选一种：

```bash
# A. 从 Release 的 tag 装（推荐：地址固定，不随 main 变动）
pnpm add https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases/latest/download/dsh-purge-dsh0.2.1rc2-fix.tar.gz

# A2. 用 git spec（宿主会先做一次 GitHub 连通性检查，5 秒超时）
pnpm add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"

# B. 用 Release 附件里的 tarball（已随 Release 发布）
pnpm add file:/path/to/dsh-purge-1.1.71-dsh0.2.1rc2-fix.tar.gz
#    下载页：https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases

# C. 直接拷目录（离线机器）
cp -r dsh-purge <DSH_HOME>/profiles/desktop/node_modules/
```

> 装了多个 profile（除 `desktop` 还有别的）时，**每个要用的 profile 都要放一份**。

## 第 2 步 · 登记成 bundle（最容易漏）

编辑 `<DSH_HOME>/profiles/desktop/package.json`：

```json
{
  "dsh": {
    "profile": {
      "bundles": [ "@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dshmarket", "dsh-purge" ]
    },
    "desktopDeselectedBundles": []
  }
}
```

**必须同时满足两条**：

1. `dsh-purge` 在 `dsh.profile.bundles` 里（**只留在 `dependencies` 里不算**）
2. `desktopDeselectedBundles` 里**没有** `dsh-purge`

很多"插件装了没生效"都是栽在这两个字段上。

> **更省事的办法**：DSH 的**插件面板 → 添加插件**接受 Git 地址 / 压缩包 / 本地绝对路径，装完会自动把 `dsh-purge` 写进 `bundles`（宿主侧 `installBundle()` 装完即调 `selectBundle(name, true)`），这两个字段就不用手改了。

## 第 3 步 · 同步预设 + 重启

```bash
# 预设是"插件模板 + 用户副本"两份，改模板不会覆盖已存在的用户副本
# 老格式预设交给自愈工具处理：
ELECTRON_RUN_AS_NODE=1 "<DSH 安装目录>/DSH Desktop.exe" \
  <DSH_HOME>/profiles/desktop/node_modules/dsh-purge/dsh-purge-repair.mjs --fix
```

然后**完全退出并重启 DSH**（`lib/**` 与 `cordis.patch.yml` 只在启动时读盘）。

---

## 装完怎么验证

### 1. 插件真的挂载了

宿主日志：`%APPDATA%\DSH Desktop\logs\host\dsh-<日期>.log`

应能搜到、**且各只出现一次**：

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；…）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

**不该**再出现：

```
[W] [root] patch: entry "dsh-purge" not found
[E] [tool-subagent] Error: tool-subagent: toolFilter is no longer supported
[W] [agent-preset-registry] agent preset redteam: … is broken
```

### 2. 设置页不再重复渲染

打开 dsh-purge 面板：每个配置项**只出现一块**。还是两块 → 跑自愈工具。

### 3. 工作目录正常

系统提示词尾部应是 `Your working directory is <路径>.`，不是 `{ {cwd}}`、不是空。

---

## 出问题了怎么救

### A. DSH 打不开（启动卡住 / 直接崩）

**先让它能开** —— 编辑 `<DSH_HOME>/profiles/desktop/package.json`，把 `dsh-purge` 从 `bundles`
**移到** `desktopDeselectedBundles`：

```json
{
  "dsh": {
    "profile": { "bundles": [ /* 去掉 dsh-purge */ ] },
    "desktopDeselectedBundles": ["dsh-purge"]
  }
}
```

**再修根因**：

```bash
ELECTRON_RUN_AS_NODE=1 "<DSH 安装目录>/DSH Desktop.exe" \
  <DSH_HOME>/profiles/desktop/node_modules/dsh-purge/dsh-purge-repair.mjs --fix
```

然后把 `dsh-purge` 从 `desktopDeselectedBundles` 移回 `bundles`，重启。

### B. `cordis.patch.yml` 整个丢了

宿主 `loadOverlayPatches()` 有兜底：读不到主文件时会去读同目录的
**`cordis.patch.yml.dshpurge.bak`**。所以这个 `.dshpurge.bak` **不要删**。

### C. 只想看问题、不改文件

```bash
ELECTRON_RUN_AS_NODE=1 "…/DSH Desktop.exe" <…>/dsh-purge-repair.mjs
```

退出码：`0` 正常 · `1` 有问题未修 · `2` 找不到环境。

---

## 注意事项

- **升级 DSH 后重新跑一次自愈工具的检查模式**。上游 master 仍是 `1.1.71` 且仍带这些故障。
- **别用 `pnpm update dsh-purge`** —— 会打回上游未修复版本。
- 自愈工具依赖 `yaml` 解析器。它会先尝试 DSH 自带的
  `resources/app/node_modules/yaml/dist/index.js`，所以**建议用 DSH 自己的 node 运行**：
  `ELECTRON_RUN_AS_NODE=1 "…/DSH Desktop.exe" dsh-purge-repair.mjs`。
