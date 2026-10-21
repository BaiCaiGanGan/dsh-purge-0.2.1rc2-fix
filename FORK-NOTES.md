# 分支说明：dsh-purge × DSH 0.2.1-rc.2

> **本仓库是社区适配分支，不是上游官方发布，亦未获上游背书。**
> 上游：[`YuJunZhiXue/dsh-purge`](https://github.com/YuJunZhiXue/dsh-purge)（MIT）。
> 本仓库保留上游全部代码与许可，仅叠加针对 **DSH `0.2.1-rc.2`** 的九处适配修复。
> 上游 `master` 目前仍为 `1.1.71`、`dshTarget: 0.2.0-rc.2`，**这些修复尚未合并上游**。

## 1. 版本基线

| 项 | 值 |
|---|---|
| 上游版本 | `1.1.71` |
| 上游提交 | `6c1d638` |
| 上游 release | [v1.1.71](https://github.com/YuJunZhiXue/dsh-purge/releases/tag/v1.1.71) |
| 本分支版本 | `1.1.71-dsh0.2.1rc2-fix.5` |
| 目标宿主 | DSH `0.2.1-rc.2`（`<DSH 安装目录>\resources\app`） |
| 许可 | MIT（见 [LICENSE](LICENSE)）；上游代码著作权归原作者**小杨** |

## 2. 分支边界

本分支只解决「既有功能在新宿主上不再成立」的问题，边界如下：

**做：**

- 让上游既有功能在 `0.2.1-rc.2` 上重新可用。
- 每处修复带宿主结构探测，在旧宿主上自动退让，不产生回归。
- 为新增修复补离线回归测试。

**不做：**

- 不改写提示词内容，不调整人格设定，不移除任何功能。
- 不改变产品行为。唯一涉及行为的补丁 `#85` / `#86`（Ctrl+Enter 语义）保持原状，理由见 [FIXES.md](FIXES.md) 附录 B。
- 不跟进上游 `0.2.0-rc.2` 时期的设计假设，也不为更老的 DSH 提供兼容。

## 3. 修复范围

九处修复的编号、症状与改法见 [FIXES.md](FIXES.md) 的索引表。摘要如下：

| 编号 | 一句话 | 归属 |
|---|---|---|
| FIX-01 | `cordis.patch.yml` 重复 `- insert:` 块 → DSH 无法启动 | 本仓库定位 |
| FIX-02 | `toolFilter` / `persona` 已被宿主删除，写入即抛错 | 本仓库定位 |
| FIX-03 | 宿主不再注册 `cwd` 提示词变量 | 本仓库定位 |
| FIX-04 | `#40` 锚点因 `requiredContexts` 收窄而失配 | 本仓库定位 |
| FIX-05 | 可执行名改为 `DSH Desktop.exe`，`desktop-shell` 定位失败 | 本仓库定位 |
| FIX-06 | `assemble()` 异常时提示词被整批丢空 | 本仓库定位 |
| FIX-07 | `HOST_SYNC` 漏 `closeSync` → 备份一份都写不出来 | 交叉比对后并入 |
| FIX-08 | `tool-workflow` / `tool-ralph` 未禁用 → 可绕过 `maxDepth: 1` | 交叉比对后并入 |
| FIX-09 | 同步函数调用 async 未 `await` → Node 24 升级成 fatal | 交叉比对后并入 |

> **关于 FIX-01 的一处事实澄清**：上游源码的 `cordis.patch.yml` **没有**重复 `- insert:` 块（只有 1 个，70 行）。出现重复的是本机安装产物。上游自带的另一处问题是那条重复的 `- id: dsh-purge` 引用行。详见 [FIXES.md](FIXES.md) FIX-01。

## 4. 与其它适配分支的关系

FIX-07 至 FIX-09 是在与 [`evilevil/dsh-purge-021rc2`](https://github.com/evilevil/dsh-purge-021rc2) 逐条比对后并入的。两者修复同一批宿主断裂，但实现取舍不同：

| 项 | 该分支 | 本分支 |
|---|---|---|
| `HOST_SYNC` / fd 类方法 | 混入同一张表，统一走 `route()` | 拆出 `HOST_FD` 表直接落到 `node:fs`（fd 不是路径，走 `route()` 会用 `String(fd)` 探测 asar 并污染探针缓存） |
| `#119` 同步/异步 | 改为 `async` + 补 `await`，并改调用链 | 只把调用点换成同为原子写的同步实现，签名与调用链不动 |
| `{{cwd}}` | 依赖 `escapeDshInterpolation` + `CWD_STATIC_SUFFIX` | 自行注册 `cwd` 提示词变量（该机制已被上游 `1.1.72` 删除，不可依赖） |
| 旧预设迁移 | 未提供就地自愈 | `repairLeafBoundary()` 就地修补已落地预设，保留使用方其它编辑且幂等 |
| 平台覆盖 | macOS + `web` profile | Windows + `desktop` profile（本分支的验证基线） |

本分支未采纳该仓库在 `#121`（Ctrl+Enter）上的改动，原因见 [FIXES.md](FIXES.md) 附录 B。

## 5. 自愈工具

`dsh-purge-repair.mjs` 处理两类历史遗留问题：重复 `- insert:` 块、已退役的配置键。路径自定位，不写死 DSH 安装目录。

```bash
# 只检查：退出码 0 正常 / 1 有问题未修 / 2 环境错误
node dsh-purge-repair.mjs --check

# 检查并修复（改前自动备份为 cordis.patch.yml.dshpurge.bak.<时间戳>）
node dsh-purge-repair.mjs --fix
```

## 6. 向上游合并的建议

若上游恢复维护，建议按以下顺序合并，每条都可独立评审：

1. **FIX-02、FIX-03、FIX-05、FIX-06**：纯宿主适配，无行为变化，风险最低，可先合。
2. **FIX-01**：涉及安装产物与引用行两个独立问题，建议拆成两个提交。
3. **FIX-04**：需连带 `completePromptInjectBody()` 的抽取，改动面稍大。
4. **FIX-07、FIX-09**：均为静态可判定的缺陷，附测试后易评审。
5. **FIX-08**：涉及预设契约，需上游确认「叶子边界」的预期语义后再合。

`test/fixes.test.mjs` 可直接作为这些修复的验收用例。

## 7. 致谢与许可

- 上游作者**小杨**：全部原始代码、提示词与文档。
- [`evilevil/dsh-purge-021rc2`](https://github.com/evilevil/dsh-purge-021rc2)：FIX-07 至 FIX-09 的问题定位线索。

MIT。原始版权 `Copyright (c) 2026 小杨`，本分支修改部分 `Copyright (c) 2026 Star`。全文见 [LICENSE](LICENSE)。
