# dsh-purge × DSH 0.2.1-rc.2 适配修复版

> **这是一个 fork，不是上游。** 上游：[YuJunZhiXue/dsh-purge](https://github.com/YuJunZhiXue/dsh-purge)（MIT）。
> 本仓库保留上游全部代码与许可，只叠加针对 **DSH Desktop 0.2.1-rc.2** 的 6 处适配修复。
> 上游 master 目前仍是 `1.1.71`、`dshTarget: 0.2.0-rc.2`，**这些修复尚未合并**。

- 上游提交：`6c1d638`（版本 `1.1.71`，release [v1.1.71](https://github.com/YuJunZhiXue/dsh-purge/releases/tag/v1.1.71)）
- 目标宿主：**DSH Desktop 0.2.1-rc.2**（`D:\DSH Desktop\resources\app`）
- 许可：MIT（见 [LICENSE](LICENSE)）。**上游代码的著作权归原作者小杨**；本 fork 的适配修复由 **Star** 完成

---

## 为什么要有这个 fork

DSH 从 `0.2.0-rc.2` 升到 `0.2.1-rc.2` 之后，上游 `1.1.71` 在桌面版上**装不起来 / 起来了也带病**。本 fork 修的就是这些。

### 最严重的一条：`- insert:` 块被写了两遍 → DSH 直接打不开

先说结论，分成两件事看：

**A. 上游代码本身是干净的。** 上游 `master` 的 `cordis.patch.yml` 是 70 行、**只有 1 个 `- insert:` 块**。
**B. 但本机安装出来的副本里，这个块出现了两遍** —— 于是同一批插件各被插入两次：

```yaml
# ↑ 这是「本机安装出来的那份」修前的状态（B），不是上游源码的形状
- insert:
    - id: dsh-purge
    - id: dsh-purge-redteam
    - id: dsh-purge-redteam-store     # ← 两个实例抢同一个 SQLite 文件
    - id: dsh-purge-redteam-ui
    # ↓ 从这里开始是完全一样的一份
    - id: dsh-purge
    - id: dsh-purge-redteam
    - id: dsh-purge-redteam-store
    - id: dsh-purge-redteam-ui
```

宿主每次启动都重新读盘解析这个文件，所以这个故障**每次启动都会命中**。表现：DSH 启动不了（或插件配置在设置页里渲染成两块）。实测宿主组合引擎的输出：

```
insert -> dsh-purge (dsh-purge)  [dsh-purge]
insert -> dsh-purge-redteam (dsh-purge/redteam)  [dsh-purge]
insert -> dsh-purge-redteam-store (dsh-purge/redteam/store)  [dsh-purge]
insert -> dsh-purge-redteam-ui (dsh-purge/redteam/ui)  [dsh-purge]
insert -> dsh-purge (dsh-purge)  [dsh-purge]          ← 重复
insert -> dsh-purge-redteam (dsh-purge/redteam)  [dsh-purge]   ← 重复
```

**C. 还有一处是上游代码本身就带的**：上游那 70 行里，除插入块外还有一条只写 `inject` 的
`- id: dsh-purge` 引用行（上游第 33–34 行）。它给配置补一个覆盖项，但同时又让插入块里的
`- id: dsh-purge` 带了同名 `config`，同一批设置被声明两遍。本仓库把那行去掉，
`postPrompt` / `enabled` 这类改动统一走**面板写入 profile 自己的 patch**，不再回落到插件自带值。

> 排查 A / B 哪个才是你遇到的那份，比对这一行：
> ```bash
> curl -sL https://raw.githubusercontent.com/YuJunZhiXue/dsh-purge/master/cordis.patch.yml | grep -c '^- insert:'
> grep -c '^- insert:' <DSH_HOME>/profiles/desktop/node_modules/dsh-purge/cordis.patch.yml
> ```
> 上游应输出 `1`；本地若输出 `2`，就是 B 那种情况。

### 其余五处

| # | 文件 | 症状 | 修法 |
|---|---|---|---|
| 2 | `lib/redteam/index.js`、`presets/redteam/agent.cordis.yml` | `[E] [tool-subagent] toolFilter is no longer supported` → 预设 broken → 派活全废 | 0.2.1-rc.2 把 `toolFilter` / `persona` 从 `@deepseek-ai/dsh-tool-subagent` 的 Config 里删了，写入即 throw。去掉这两个键，叶子约束交给 `maxDepth: 1`；并加版本自适应的剥离逻辑，老格式预设会自动修好 |
| 3 | `lib/identity.js`、`lib/index.js` | `unknown prompt variable "{{cwd}}"` → 整批 sections 被丢 | 0.2.1 的宿主只注册 `model` / `provider` 两个提示词变量，`cwd` 被删了。插件自己把 `cwd` 注册回去；并且 persona 段**优先写字面路径**，不再依赖占位符 |
| 4 | `lib/core.js` | `#40 COMPLETE_PROMPT_KEEP_INJECT` 静默 skipped → complete 预设注入被吞 | 宿主把 `contexts` 收窄成 `requiredContexts` 过滤，旧锚点失配。补 0.2.1 形态的 pattern |
| 5 | `lib/desktop.js` | `desktop-shell` 永远定位不到（报 `missing_file`） | 0.2.1 的可执行名是 `DSH Desktop.exe`，`isOfficialHarnessExecutable` 只认 `deepseek-harness`。补上名字集合 |
| 6 | `lib/identity.js`、`lib/core.js` | 宿主 assemble 一抛就把整个系统提示词丢掉 | 兜底路径改为按宿主注册顺序重建段表、丢掉插值过不了的段，而不是返回 `{ sections: [] }` |

另外给补丁注册表加了 `retired` 标记：宿主升级后结构性失效的老补丁（同一批壳补丁链、web 面文案、已被宿主原生功能覆盖的 rewind 补丁）从"skipped"正名为"已退役"，并写明退役理由，不再把"没命中"和"用不着"混在一起。

---

## 安装

见 **[INSTALL.md](INSTALL.md)**（含三步安装、验证清单、三种故障的救援流程）。

最短路径：

```bash
cd <DSH_HOME>/profiles/desktop          # 默认 ~/.dsh
# 从 Release 的 tag 装（地址固定）
pnpm add https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases/latest/download/dsh-purge-dsh0.2.1rc2-fix.tar.gz
```

然后在 `profiles/desktop/package.json` 的 `dsh.profile.bundles` 里加上 `"dsh-purge"`，
并确保 `desktopDeselectedBundles` 里**没有**它。重启 DSH。

---

## 自愈工具

`dsh-purge-repair.mjs` —— 万一重复块或退役键又回来了，一条命令修好：

```bash
# 只检查（退出码 0 正常 / 1 有问题未修 / 2 环境错误）
ELECTRON_RUN_AS_NODE=1 "<DSH 安装目录>/DSH Desktop.exe" dsh-purge-repair.mjs

# 检查并修复（改前自动备份；会留一份 cordis.patch.yml.dshpurge.bak 作宿主级安全网）
ELECTRON_RUN_AS_NODE=1 "<DSH 安装目录>/DSH Desktop.exe" dsh-purge-repair.mjs --fix
```

它检查两处：`cordis.patch.yml` 的重复 `insert` 块 / 重复插件 id；红队预设里 0.2.1 已删除的 `toolFilter` / `persona` 键。
**升级 DSH 后建议跑一次检查模式。**

---

## 给上游的合并建议

这 6 处都是**版本自适应**写法（宿主没有对应结构时自动退让），可以直接合进上游而不破坏对 `0.2.0-rc.2` 的兼容。逐条 diff 与验证方法见 **[FIXES.md](FIXES.md)**。

---

## 致谢与许可

- 原始项目与全部代码：**小杨** — [YuJunZhiXue/dsh-purge](https://github.com/YuJunZhiXue/dsh-purge)（著作权人）
- 本 fork 的宿主适配修复：**Star**（[Potato1008ypy](https://github.com/Potato1008ypy)）
- 许可：MIT，见 [LICENSE](LICENSE)
- 本 fork 只做宿主适配修复，不含上游代码的重写或删改；如上游合并了这些修复，请优先使用上游版本。
