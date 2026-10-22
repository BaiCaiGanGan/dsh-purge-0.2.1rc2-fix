<#
.SYNOPSIS
  一键安装 dsh-purge：自动探测 DSH 安装目录与运行模式，安装插件并写入 dsh.profile.bundles。

.DESCRIPTION
  做四件事：
    1. 探测 DSH 安装目录（运行中的进程 / 常见安装位置 / 注册表 / 浅层扫描），拿到 desktop-cli.js；
    2. 判定当前是「桌面端」还是「原版 CLI」，并选出 profile；
    3. 调用对应入口执行 pnpm add（这一步写入 dependencies）；
    4. 把包名写进 dsh.profile.bundles —— 正是这一步让插件重启后自动加载，
       省掉手动到「插件」页点启用。

  安全约束：
    * 远端 tarball 地址一律拒绝（宿主带 CI=true，会写出缺 integrity 的锁文件条目并冻结 profile）。
    * DSH 在运行时默认不执行：pnpm 要重命名原生模块目录，而运行中的 DSH 占着它，必报 EPERM。
    * 改动前备份 package.json；写入后重新解析校验，失败即回滚。

  网络兜底：
    * git 连不上 github.com 时（报 ERR_PNPM_GIT_RESOLVE_FAILED / unable to access），
      自动改为下载本版本发布包并按本地 file: 安装，再重试一次。
      发布包走镜像（ghfast.top → gh-proxy.com → 直连），并校验包名与版本。
    * 也可显式用 -FromRelease 直接走发布包。

.PARAMETER Spec
  安装源。默认 GitHub 源（tag 锁定，可复现）。

.PARAMETER DshHome
  DSH 数据目录，默认 %USERPROFILE%\.dsh

.PARAMETER DshInstall
  手动指定 DSH 安装目录；留空则自动探测。

.PARAMETER Mode
  auto（默认）/ desktop / cli。

.PARAMETER Force
  DSH 仍在运行时也继续（不推荐，通常会导致 EPERM）。

.PARAMETER NoBundle
  只装包、不写 bundles（等价于裸 pnpm add，装完需手动启用）。

.PARAMETER DryRun
  只打印计划，不改动任何文件。

.PARAMETER SelfTest
  对内置样例跑写入逻辑的自检，不接触真实 profile。

.PARAMETER FromRelease
  跳过 GitHub 源，直接下载本版本的发布包（走镜像）并按本地文件安装。
  git 到 github.com 不通时用这个。

.PARAMETER AssetUrl
  手动指定发布包地址（配合 -FromRelease）。

.EXAMPLE
  .\install.ps1

.EXAMPLE
  .\install.ps1 -DryRun

.EXAMPLE
  .\install.ps1 -DshInstall "D:\DSH Desktop"

.EXAMPLE
  .\install.ps1 -FromRelease
#>
[CmdletBinding()]
param(
    [string]$Spec = "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.7",
    [string]$PackageName = "dsh-purge",
    [string]$DshHome = "",
    [string]$DshInstall = "",
    [ValidateSet("auto", "desktop", "cli")]
    [string]$Mode = "auto",
    [switch]$Force,
    [switch]$NoBundle,
    [switch]$DryRun,
    [switch]$SelfTest,
    [switch]$FromRelease,
    [string]$AssetUrl = ""
)

$ErrorActionPreference = "Stop"
$script:ExitCode = 0

# DSH 数据目录：显式 -DshHome > 环境变量 DSH_HOME > 默认 ~\.dsh
# （原先默认写死用户目录，会把 DSH_HOME 指向别处的用户装到错误位置）
if (-not $DshHome) {
    $DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }
}

# 本版本对应的发布产物：git 不通时的兜底来源（镜像按顺序尝试）
$script:RepoSlug = "Potato1008ypy/dsh-purge-0.2.1rc2-fix"
$script:ReleaseTag = "v1.1.71-dsh0.2.1rc2-fix.7"
$script:AssetName = "dsh-purge-dsh0.2.1rc2-fix.7.tar.gz"
$script:AssetVersion = "1.1.71-dsh0.2.1rc2-fix.7"
$script:AssetMirrors = @(
    "https://ghfast.top/https://github.com/$($script:RepoSlug)/releases/download/$($script:ReleaseTag)/$($script:AssetName)",
    "https://gh-proxy.com/https://github.com/$($script:RepoSlug)/releases/download/$($script:ReleaseTag)/$($script:AssetName)",
    "https://github.com/$($script:RepoSlug)/releases/download/$($script:ReleaseTag)/$($script:AssetName)"
)

function Say([string]$Text) { Write-Host $Text }
function Ok([string]$Text) { Write-Host "  ✓ $Text" -ForegroundColor Green }
function Warn([string]$Text) { Write-Host "  ! $Text" -ForegroundColor Yellow }
function Die([string]$Text, [int]$Code = 1) {
    Write-Host "  ✗ $Text" -ForegroundColor Red
    exit $Code
}

# ─────────────────────────────────────────── profile 配置读写（按 JSON 路径改写）
# 1) 5.1 的 Get-Content 默认按系统 ANSI 解码，无 BOM 的 UTF-8 中文会被读坏，
#    实测会让 ConvertFrom-Json 直接失败 —— 读写都必须显式 UTF-8。
# 2) 不按文本正则找 "bundles"：文档里别处也可能有同名键，正则只会命中第一个。
function Read-JsonText([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Get-FileHasBom([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Write-JsonText([string]$Path, [string]$Text) {
    # 按原文件是否带 BOM 精确写回：5.1 的 Set-Content -Encoding UTF8 会写 BOM，宿主 JSON.parse 会失败
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding((Get-FileHasBom $Path))))
}

function Get-CompareShape($Object) {
    # 仅用于比对：把两个目标数组抹平后序列化，用来证明其它字段没被动过
    $copy = ($Object | ConvertTo-Json -Depth 100) | ConvertFrom-Json
    if ($copy.PSObject.Properties["dsh"]) {
        if ($copy.dsh.PSObject.Properties["profile"] -and $copy.dsh.profile.PSObject.Properties["bundles"]) {
            $copy.dsh.profile.bundles = @()
        }
        if ($copy.dsh.PSObject.Properties["desktopDeselectedBundles"]) {
            $copy.dsh.desktopDeselectedBundles = @()
        }
    }
    return ($copy | ConvertTo-Json -Depth 100)
}

function Update-ProfileConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [switch]$AddBundle,
        [switch]$UndoDeselect
    )
    $raw = Read-JsonText $Path
    $obj = $raw | ConvertFrom-Json
    $before = $raw | ConvertFrom-Json          # 独立副本，事后比对用

    if (-not ($obj.PSObject.Properties["dsh"] -and $obj.dsh.PSObject.Properties["profile"])) {
        throw "在 $Path 里找不到 dsh.profile"
    }
    $prof = $obj.dsh.profile
    if (-not $prof.PSObject.Properties["bundles"]) { throw "在 $Path 里找不到 dsh.profile.bundles 数组" }

    $bundleAdded = $false
    $removedDeselect = $false

    if ($AddBundle) {
        $bundles = @($prof.bundles)
        if ($bundles -notcontains $Name) {
            $prof.bundles = @($bundles + $Name)
            $bundleAdded = $true
        }
    }
    if ($UndoDeselect -and $obj.dsh.PSObject.Properties["desktopDeselectedBundles"]) {
        $d = @($obj.dsh.desktopDeselectedBundles)
        if ($d -contains $Name) {
            $obj.dsh.desktopDeselectedBundles = @($d | Where-Object { $_ -ne $Name })
            $removedDeselect = $true
        }
    }

    if (-not ($bundleAdded -or $removedDeselect)) {
        return [pscustomobject]@{ BundleAdded = $false; DeselectedRemoved = $false; Changed = $false }
    }

    # 只允许这两个数组变化，其它字段必须逐一相同，否则不写
    if ((Get-CompareShape $before) -ne (Get-CompareShape $obj)) {
        throw "改写前后其它字段不一致，已放弃写入"
    }

    $out = ($obj | ConvertTo-Json -Depth 100)
    # ConvertTo-Json 在 5.1 下用 CRLF；原文件是 LF 的就换回去，避免无谓的整文件 diff
    if ($raw -notmatch "`r`n") { $out = $out -replace "`r`n", "`n" }
    if (-not $out.EndsWith("`n")) { $out += $(if ($raw -match "`r`n") { "`r`n" } else { "`n" }) }
    Write-JsonText $Path $out

    # 落盘后重新解析，确认目标状态达成
    $check = (Read-JsonText $Path) | ConvertFrom-Json
    if ($AddBundle -and -not (@($check.dsh.profile.bundles) -contains $Name)) { throw "写入后 bundles 校验失败" }
    if ($UndoDeselect -and (@($check.dsh.desktopDeselectedBundles) -contains $Name)) { throw "写入后 desktopDeselectedBundles 校验失败" }

    return [pscustomobject]@{ BundleAdded = $bundleAdded; DeselectedRemoved = $removedDeselect; Changed = $true }
}

# ─────────────────────────────────────────── 安装目录探测
function Test-DshDir([string]$Dir) {
    if (-not $Dir) { return $false }
    return (Test-Path (Join-Path $Dir "resources\app\lib\desktop-cli.js"))
}

function Find-InstallDir([string]$Hint) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Hint) { $candidates.Add($Hint) }

    foreach ($p in (Get-Process "DSH Desktop" -ErrorAction SilentlyContinue)) {
        try { if ($p.Path) { $candidates.Add((Split-Path -Parent $p.Path)) } } catch { }
    }

    $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\DSH Desktop"))
    $candidates.Add((Join-Path $env:ProgramFiles "DSH Desktop"))
    if (${env:ProgramW6432}) { $candidates.Add((Join-Path ${env:ProgramW6432} "DSH Desktop")) }
    $candidates.Add("D:\DSH Desktop")
    $candidates.Add("C:\DSH Desktop")

    foreach ($c in $candidates) {
        if (Test-DshDir $c) { return (Resolve-Path $c).Path }
    }

    # 注册表兜底
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($r in $roots) {
        foreach ($item in (Get-ItemProperty $r -ErrorAction SilentlyContinue)) {
            if ($item.DisplayName -notlike "*DSH*") { continue }
            if ($item.InstallLocation -and (Test-DshDir $item.InstallLocation)) {
                return (Resolve-Path $item.InstallLocation).Path
            }
            if ($item.DisplayIcon) {
                $icon = $item.DisplayIcon.Trim('"').Split(',')[0]
                if ($icon) {
                    $dir = Split-Path -Parent $icon
                    if (Test-DshDir $dir) { return (Resolve-Path $dir).Path }
                }
            }
        }
    }
    return $null
}

function Get-ProfileCandidates {
    $root = Join-Path $DshHome "profiles"
    if (-not (Test-Path $root)) { return @() }
    return @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "package.json") } |
        Select-Object -ExpandProperty Name)
}

function Test-DesktopCli {
    param([string]$Dir)
    return ($Dir -and (Test-DshDir $Dir))
}

function Quote-Arg([string]$s) {
    if ($s -notmatch '[\s"]') { return $s }
    return '"' + ($s -replace '"', '\"') + '"'
}

function Invoke-DesktopCli {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string[]]$CliArgs
    )
    $exe = Join-Path $Dir "DSH Desktop.exe"
    $cli = Join-Path $Dir "resources\app\lib\desktop-cli.js"
    $env:ELECTRON_RUN_AS_NODE = "1"

    # 不用 Start-Process：环境里同时存在 NO_PROXY/no_proxy 这类大小写重复键时它会直接抛异常。
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ((@($cli) + $CliArgs) | ForEach-Object { Quote-Arg $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    # pnpm 的日志里带 ✅ ⚠️ 这类字符，是 UTF-8 多字节序列。不指定编码时 .NET Framework 会按
    # 系统 OEM 码页（简中 936）解码，✅(E2 9C 85) 就被解成「鉁?」。这里显式按 UTF-8 读。
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8

    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()      # 异步读流，避免管道写满互相阻塞
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    return [pscustomobject]@{
        Code   = $p.ExitCode
        Output = ((@($outTask.Result, $errTask.Result) | Where-Object { $_ }) -join "`n")
    }
}

# ─────────────────────────────────────────── 发布包兜底（git 不通时）
function Test-GitSpec([string]$s) {
    return ($s -match '^github:') -or ($s -match '^https?://github\.com/')
}

function Test-GitResolveFailure([string]$output) {
    if (-not $output) { return $false }
    return $output -match 'GIT_RESOLVE_FAILED|Failed to resolve git dependency|unable to access|Could not resolve host|Failed to connect|Connection timed out|Connection refused'
}

function Test-PackageTarball([string]$path, [string]$expectedVersion) {
    # 不用 PowerShell 原生捕获 tar 输出：那会把 UTF-8 按 OEM 代码页解码，含中文时值会被写坏、
    # 极端情况下连 JSON 结构都断掉。这里按字节读、显式 UTF-8 解码。
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "tar"
    $psi.Arguments = "-xzOf `"$path`" package/package.json"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $text = $proc.StandardOutput.ReadToEnd()
    $null = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0 -or -not $text) { return "包里没有 package/package.json" }
    try { $p = $text | ConvertFrom-Json } catch { return "package.json 解析失败" }
    if ($p.name -ne $PackageName) { return "包名不符：$($p.name)" }
    if ($expectedVersion -and $p.version -ne $expectedVersion) { return "版本不符：$($p.version)" }
    return $null
}

function Get-ReleaseTarball {
    param([string[]]$Urls)
    # 落到持久缓存，不能放 %TEMP%：这个路径会被写进 dependencies，
    # 临时目录被清理后，重装或恢复依赖就找不到包了。
    $cacheDir = Join-Path $DshHome "cache\plugins"
    try {
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
    }
    catch {
        $cacheDir = Join-Path $env:LOCALAPPDATA "dsh-purge\cache"
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
        Warn "DSH 数据目录不可写，改用 $cacheDir"
    }
    $dst = Join-Path $cacheDir $script:AssetName
    $n = 0
    foreach ($u in $Urls) {
        if (-not $u) { continue }
        $n++
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $u -OutFile $dst
        }
        catch {
            Warn "  源 $n 下载失败：$($_.Exception.Message.Split([char]10)[0])"
            continue
        }
        $bad = Test-PackageTarball -path $dst -expectedVersion $script:AssetVersion
        if ($bad) { Warn "  源 $n 内容不对（$bad）"; continue }
        $hash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
        $size = (Get-Item -LiteralPath $dst).Length
        Ok "发布包就绪：$(Split-Path -Leaf $dst)（$size 字节，sha256 $($hash.Substring(0, 16))…）"
        return $dst
    }
    return $null
}

# ─────────────────────────────────────────── 自检
if ($SelfTest) {
    $fails = @()
    function Tmp-Json([string]$text) {
        $p = Join-Path $env:TEMP ("bundle-selftest-" + [guid]::NewGuid().ToString("N") + ".json")
        # 故意写成「无 BOM + UTF-8」，模拟真实用户配置
        [System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))
        return $p
    }

    # 1) 基本写入 + 幂等 + 其它字段不动
    $f1 = Tmp-Json @'
{
  "name": "dsh-profile-desktop",
  "private": true,
  "dependencies": {
    "dsh-purge": "github:owner/repo#tag"
  },
  "dsh": {
    "profile": {
      "bundles": ["@deepseek-ai/dsh-base", "dshmarket"]
    },
    "desktopDeselectedBundles": ["dsh-purge"]
  }
}
'@
    $r1 = Update-ProfileConfig -Path $f1 -Name "dsh-purge" -AddBundle -UndoDeselect
    $p1 = Read-JsonText $f1 | ConvertFrom-Json
    if (-not $r1.Changed) { $fails += "首次调用应有改动" }
    if (-not $r1.BundleAdded) { $fails += "应写入 bundles" }
    if (-not $r1.DeselectedRemoved) { $fails += "应摘除禁用项" }
    if (@($p1.dsh.profile.bundles) -notcontains "dsh-purge") { $fails += "bundles 未包含目标" }
    if (@($p1.dsh.profile.bundles)[0] -ne "@deepseek-ai/dsh-base") { $fails += "原有顺序被打乱" }
    if ($p1.name -ne "dsh-profile-desktop") { $fails += "其它字段被破坏" }
    if ($p1.dependencies.'dsh-purge' -ne "github:owner/repo#tag") { $fails += "dependencies 被破坏" }
    if ((@($p1.dsh.desktopDeselectedBundles)).Count -ne 0) { $fails += "禁用项未清空" }

    $r1b = Update-ProfileConfig -Path $f1 -Name "dsh-purge" -AddBundle -UndoDeselect
    if ($r1b.Changed) { $fails += "重复调用应无改动" }

    # 2) 空数组分支
    $f2 = Tmp-Json '{"dsh":{"profile":{"bundles":[]}}}'
    $r2 = Update-ProfileConfig -Path $f2 -Name "dsh-purge" -AddBundle
    $p2 = Read-JsonText $f2 | ConvertFrom-Json
    if (-not (@($p2.dsh.profile.bundles) -contains "dsh-purge")) { $fails += "空数组分支未写入" }
    if (@($p2.dsh.profile.bundles).Count -ne 1) { $fails += "空数组分支写入了多余元素" }
    if ($p2.dsh.PSObject.Properties["desktopDeselectedBundles"]) { $fails += "不应凭空创建 desktopDeselectedBundles" }

    # 3) 无 BOM + 中文字段必须原样保留（读取时不指定 UTF-8 会读坏、甚至解析失败）
    $cn = '{"开头":"说明文档","备注":"中文不应被改写","dsh":{"profile":{"bundles":[]},"desktopDeselectedBundles":[]}}'
    $f3 = Tmp-Json $cn
    $r3 = Update-ProfileConfig -Path $f3 -Name "dsh-purge" -AddBundle -UndoDeselect
    $p3 = Read-JsonText $f3 | ConvertFrom-Json
    if ($p3.'开头' -ne "说明文档") { $fails += "中文字段被改坏：$($p3.'开头')" }
    if ($p3.'备注' -ne "中文不应被改写") { $fails += "中文备注被改坏：$($p3.'备注')" }
    if (@($p3.dsh.profile.bundles) -notcontains "dsh-purge") { $fails += "含中文时 bundles 未写入" }

    # 4) 别处同名 bundles 不得被误判为目标
    $shadow = '{"other":{"bundles":["dsh-purge"]},"dsh":{"profile":{"bundles":[]},"desktopDeselectedBundles":[]}}'
    $f4 = Tmp-Json $shadow
    $r4 = Update-ProfileConfig -Path $f4 -Name "dsh-purge" -AddBundle -UndoDeselect
    $p4 = Read-JsonText $f4 | ConvertFrom-Json
    if (-not $r4.BundleAdded) { $fails += "影子 bundles 导致误判为已登记" }
    if (@($p4.dsh.profile.bundles) -notcontains "dsh-purge") { $fails += "目标数组未写入" }
    if (@($p4.other.bundles).Count -ne 1) { $fails += "误改了 other.bundles" }

    # 5) 写回的 JSON 不能带 BOM（宿主 JSON.parse 会失败）
    $bb = [System.IO.File]::ReadAllBytes($f1)
    if ($bb.Length -ge 3 -and $bb[0] -eq 0xEF -and $bb[1] -eq 0xBB -and $bb[2] -eq 0xBF) { $fails += "写入后带上了 BOM" }
    $t1 = [System.IO.File]::ReadAllText($f1)
    if ($t1.Length -gt 0 -and [int]$t1[0] -eq 0xFEFF) { $fails += "首字符是 U+FEFF" }

    # 6) 原本带 BOM 的文件应保持带 BOM（不改变宿主既有约定）
    $f5 = Join-Path $env:TEMP ("bundle-selftest-keepbom-" + [guid]::NewGuid().ToString("N") + ".json")
    [System.IO.File]::WriteAllText($f5, '{"dsh":{"profile":{"bundles":[]}}}', (New-Object System.Text.UTF8Encoding($true)))
    $null = Update-ProfileConfig -Path $f5 -Name "dsh-purge" -AddBundle
    $b5 = [System.IO.File]::ReadAllBytes($f5)
    if (-not ($b5.Length -ge 3 -and $b5[0] -eq 0xEF -and $b5[1] -eq 0xBB -and $b5[2] -eq 0xBF)) { $fails += "原有 BOM 被丢弃" }

    # 7) 缺 dsh.profile.bundles 时应明确报错，而不是静默成功
    $f6 = Tmp-Json '{"dsh":{"profile":{}}}'
    $threw = $false
    try { $null = Update-ProfileConfig -Path $f6 -Name "dsh-purge" -AddBundle } catch { $threw = $true }
    if (-not $threw) { $fails += "缺少 bundles 数组时应抛错" }

    Remove-Item $f1, $f2, $f3, $f4, $f5, $f6 -Force -ErrorAction SilentlyContinue
    if ($fails.Count -gt 0) {
        $fails | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
        exit 1
    }
    Ok "自检通过：路径定位、中文无损、无 BOM 写回、幂等、缺键报错"
    exit 0
}

# ─────────────────────────────────────────── 主流程
Say ""
Say "dsh-purge 一键安装"
Say "═══════════════════"

# 1) spec 安全检查
if ($Spec -match '^https?://' -and $Spec -match '\.(tgz|tar\.gz|tar)$') {
    Die "拒绝远端 tarball 地址：宿主给 pnpm 带 CI=true，会写出缺 integrity 的锁文件条目并冻结整个 profile（见 INSTALL.md 7.5）。请改用 github: 源或本地 file: 压缩包。" 2
}
Ok "安装源：$Spec"

# 1.5) 运行时预检：演练台事实库用 node:sqlite（Node 22.5 起才有，22.13 起不用加 flag）。
#      Node 18/20 上装得上、但 store 插件加载即失败，报错离原因很远，所以先提示一句。
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeVerRaw = (& node -v 2>$null)
    $m = [regex]::Match([string]$nodeVerRaw, 'v(\d+)\.(\d+)')
    if ($m.Success) {
        $major = [int]$m.Groups[1].Value
        $minor = [int]$m.Groups[2].Value
        if ($major -lt 22 -or ($major -eq 22 -and $minor -lt 13)) {
            Warn "node $nodeVerRaw 低于 22.13：演练台的事实库（node:sqlite）在这个版本上不可用，界面会报 store 加载失败。桌面端自带 Node 22.x 不受影响；命令行 / web 模式请升级 Node 到 22.13+。"
        } else {
            Ok "node $nodeVerRaw（node:sqlite 可用）"
        }
    }
}

# 2) 安装目录与模式
$installDir = Find-InstallDir $DshInstall
$resolvedMode = $Mode
if ($resolvedMode -eq "auto") {
    if (Test-DesktopCli $installDir) { $resolvedMode = "desktop" }
    elseif (Get-Command dsh -ErrorAction SilentlyContinue) { $resolvedMode = "cli" }
    else { $resolvedMode = "cli" }
}

if ($resolvedMode -eq "desktop") {
    if (-not (Test-DesktopCli $installDir)) {
        Die "找不到 DSH 安装目录（需要 resources\app\lib\desktop-cli.js）。用 -DshInstall ""<安装目录>"" 指定。" 4
    }
    Ok "模式：桌面端"
    Ok "安装目录：$installDir"
}
else {
    if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
        Die "找不到 dsh 命令；若这是桌面版，请确认安装目录或用 -DshInstall 指定。" 4
    }
    Ok "模式：原版 CLI（dsh）"
}

# 3) profile
# 必须 @() 包一层：只有一个 profile 时，PowerShell 会把单元素数组展开成字符串，
# 之后 $profiles[0] 取到的是第一个字符（例如 "web" -> "w"）。
$profiles = @(Get-ProfileCandidates)
if ($profiles.Count -eq 0) {
    Die "在 $DshHome\profiles 下没有找到任何 profile（缺 package.json）" 4
}
$profileName = $null
if ($profiles -contains "desktop" -and $resolvedMode -eq "desktop") { $profileName = "desktop" }
elseif ($profiles.Count -eq 1) { $profileName = $profiles[0] }
elseif ($profiles -contains "web") { $profileName = "web" }
else { $profileName = $profiles[0] }
Ok "profile：$profileName（可选：$($profiles -join ', ')）"

$profileDir = Join-Path (Join-Path $DshHome "profiles") $profileName
$pkgPath = Join-Path $profileDir "package.json"
$modPath = Join-Path $profileDir ("node_modules\" + $PackageName)

# 4) DSH 是否在运行
$running = @(Get-Process "DSH Desktop" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0 -and -not $Force) {
    Die "DSH 正在运行（$($running.Count) 个进程）。pnpm 需要重命名 node_modules 里的原生模块目录，运行中的 DSH 占着它，会报 ERR_PNPM_EPERM。请完全退出 DSH 后重试；确实要继续加 -Force。" 3
}

# 5) 清理残留
$tmpDirs = @(Get-ChildItem (Join-Path $profileDir "node_modules") -Directory -Filter "*_tmp_*" -ErrorAction SilentlyContinue)
if ($tmpDirs.Count -gt 0) {
    if ($DryRun) { Warn "发现 $($tmpDirs.Count) 个 _tmp_ 残留目录（将清理）" }
    else { $tmpDirs | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Ok "清理了 $($tmpDirs.Count) 个 _tmp_ 残留" }
}

# 5.5) 安装前快照：必须在 install 之前，否则快照里已经含新装的依赖，回不去安装前状态
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$snapDir = Join-Path $DshHome ("backups\install-" + $stamp)
$snapFiles = @("package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml")
$snapSaved = @()
if ($DryRun) {
    Warn "将在安装前快照到 $snapDir（$($snapFiles -join ' / ')）"
}
else {
    New-Item -ItemType Directory -Force -Path $snapDir | Out-Null
    foreach ($f in $snapFiles) {
        $src = Join-Path $profileDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $snapDir $f) -Force; $snapSaved += $f }
    }
    if ($snapSaved.Count -gt 0) { Ok "安装前快照：$snapDir（$($snapSaved -join ' / ')）" }
    else { Warn "安装前没有可快照的文件：$profileDir" }
}

# 6) 执行安装
$cliArgs = @("plugin", "--profile", $profileName, "add", $Spec)

# 让子进程用同一个 DSH_HOME，否则 -DshHome 只影响脚本自己的路径计算
$env:DSH_HOME = $DshHome

if ($DryRun) {
    Say ""
    Say "  [预演] 将执行："
    if ($resolvedMode -eq "desktop") {
        Say "    `"$installDir\DSH Desktop.exe`" `"$installDir\resources\app\lib\desktop-cli.js`" $($cliArgs -join ' ')"
    }
    else {
        Say "    dsh $($cliArgs -join ' ')"
    }
    if (-not $NoBundle) { Say "    然后写入 $pkgPath 的 dsh.profile.bundles（若尚未包含 $PackageName）" }
    if ($FromRelease) { Say "    （-FromRelease：先下载 $($script:AssetName)，再按 file: 安装）" }
    Say ""
    Say "未改动任何文件。"
    exit 0
}

function Invoke-Install([string]$spec) {
    $a = @("plugin", "--profile", $profileName, "add", $spec)
    if ($resolvedMode -eq "desktop") {
        $res = Invoke-DesktopCli -Dir $installDir -CliArgs $a
        return [pscustomobject]@{ Code = $res.Code; Output = $res.Output }
    }
    # 原生命令输出是 UTF-8，而 PowerShell 按 [Console]::OutputEncoding（简中默认 936）解码，
    # pnpm 日志里的 ✅ 会变成「鉁?」。只在这次调用期间切到 65001，读完立刻还原，
    # 免得影响脚本自己的中文输出。
    $prevEnc = $null
    try { $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { $out = (& dsh @a 2>&1 | Out-String) }
    finally { if ($prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } } }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }}

Say ""
Say "安装中……"

if ($FromRelease) {
    $tgz = Get-ReleaseTarball -Urls (@($AssetUrl) + $script:AssetMirrors)
    if (-not $tgz) { Die "发布包下载失败（镜像均不可达）；可用 -AssetUrl 指定可达地址" 7 }
    $Spec = "file:" + ($tgz -replace '\\', '/')
}

$r = Invoke-Install $Spec
if ($r.Output) { Write-Host $r.Output.TrimEnd() }
$code = $r.Code

# git 连不上 github.com（国内网络很常见）→ 自动换发布包重试一次
if ($code -ne 0 -and -not $FromRelease -and (Test-GitSpec $Spec) -and (Test-GitResolveFailure $r.Output)) {
    Say ""
    Warn "git 连不上 github.com，改用发布包本地安装（file: 会写入完整 integrity）……"
    $tgz = Get-ReleaseTarball -Urls (@($AssetUrl) + $script:AssetMirrors)
    if ($tgz) {
        $Spec = "file:" + ($tgz -replace '\\', '/')
        Say ""
        Say "重试安装（本地包）……"
        $r = Invoke-Install $Spec
        if ($r.Output) { Write-Host $r.Output.TrimEnd() }
        $code = $r.Code
    }
    else {
        Warn "发布包也取不到；请在能上网的机器下载 $($script:AssetName)，再用 -Spec `"file:<路径>`" 安装"
    }
}

if ($code -ne 0) { Die "安装失败（退出码 $code）" 5 }
Ok "包已安装"

# 7) 写 bundles + 摘掉禁用项
if ($NoBundle) {
    Warn "已跳过 bundles 写入（-NoBundle）：重启后需到「插件」页手动启用"
}
else {
    # 这份快照只用于「写 bundles 失败时回滚」，取的是装完之后的现场；
    # 可恢复安装前状态的快照在上面（backups\install-*）。
    $bak = "$pkgPath.snapshot-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $pkgPath $bak -Force
    try {
        # 一次解析完成两件事：登记 bundles + 摘掉禁用项；只改这两个数组，其它字段比对不变才写
        $res = Update-ProfileConfig -Path $pkgPath -Name $PackageName -AddBundle -UndoDeselect
        if ($res.BundleAdded) { Ok "已写入 dsh.profile.bundles" }
        else { Ok "dsh.profile.bundles 里已有 $PackageName，未改动" }
        if ($res.DeselectedRemoved) { Ok "已从 desktopDeselectedBundles 移除 $PackageName（解除禁用）" }
        if (-not $res.Changed) { Ok "配置无变化（已登记、且不在禁用列表）" }
    }
    catch {
        Copy-Item $bak $pkgPath -Force
        Die "写入 profile 配置失败并已回滚：$($_.Exception.Message)" 6
    }
    finally {
        if (Test-Path $bak) { Remove-Item $bak -Force -ErrorAction SilentlyContinue }
    }
}

# 8) 校验
Say ""
Say "校验"
$pkg = Read-JsonText $pkgPath | ConvertFrom-Json
if ($pkg.dependencies.PSObject.Properties[$PackageName]) {
    Ok "dependencies：$($pkg.dependencies.$PackageName)"
}
else {
    Warn "dependencies 里没有 $PackageName —— 安装可能未落盘"
    $script:ExitCode = 6
}
if (-not $NoBundle) {
    if (@($pkg.dsh.profile.bundles) -contains $PackageName) { Ok "bundles：已登记" }
    else { Warn "bundles：未登记"; $script:ExitCode = 6 }
    if (@($pkg.dsh.desktopDeselectedBundles) -contains $PackageName) {
        Warn "desktopDeselectedBundles 里仍有 $PackageName —— 重启后插件仍是禁用状态"
    }
}
$modPkg = Join-Path $modPath "package.json"
if (Test-Path $modPkg) {
    $v = (Read-JsonText $modPkg | ConvertFrom-Json).version
    Ok "已落地：node_modules\$PackageName@$v"
}
else {
    Warn "node_modules\$PackageName 不存在"
    $script:ExitCode = 6
}

Say ""
if ($script:ExitCode -eq 0) {
    Say "下一步：启动 DSH —— 插件会随 profile 自动加载，无需再到「插件」页点启用。"
    Say "初次加载后，在会话标题旁点 dsh-purge → 清洗 → 应用。"
}
exit $script:ExitCode
