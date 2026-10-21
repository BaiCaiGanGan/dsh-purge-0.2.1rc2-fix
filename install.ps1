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
    [string]$Spec = "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.5",
    [string]$PackageName = "dsh-purge",
    [string]$DshHome = (Join-Path $env:USERPROFILE ".dsh"),
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

# 本版本对应的发布产物：git 不通时的兜底来源（镜像按顺序尝试）
$script:RepoSlug = "Potato1008ypy/dsh-purge-0.2.1rc2-fix"
$script:ReleaseTag = "v1.1.71-dsh0.2.1rc2-fix.5"
$script:AssetName = "dsh-purge-dsh0.2.1rc2-fix.5.tar.gz"
$script:AssetVersion = "1.1.71-dsh0.2.1rc2-fix.5"
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

# ─────────────────────────────────────────── bundles 写入（文本级手术，保留原有格式）
function Add-BundleEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    $raw = Get-Content -Path $Path -Raw
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }

    $null = $raw | ConvertFrom-Json        # 先确认原文件可解析

    $m = [regex]::Match($raw, '("bundles"\s*:\s*\[)([\s\S]*?)(\])')
    if (-not $m.Success) { throw "在 $Path 里找不到 dsh.profile.bundles 数组" }

    $inner = $m.Groups[2].Value
    $found = @([regex]::Matches($inner, '"((?:[^"\\]|\\.)*)"'))
    $names = @($found | ForEach-Object { $_.Groups[1].Value })
    if ($names -contains $Name) { return $false }      # 已登记，幂等退出

    if ($names.Count -eq 0) {
        $newInner = "$nl        `"$Name`"$nl      "
    }
    else {
        $last = $found[$found.Count - 1]
        $at = $last.Index + $last.Length
        $newInner = $inner.Substring(0, $at) + ",$nl        `"$Name`"" + $inner.Substring($at)
    }

    $updated = $raw.Substring(0, $m.Index) + $m.Groups[1].Value + $newInner + $m.Groups[3].Value +
               $raw.Substring($m.Index + $m.Length)

    $check = $updated | ConvertFrom-Json              # 写入后必须仍可解析
    if (-not ($check.dsh.profile.bundles -contains $Name)) { throw "写入 bundles 后校验失败" }

    Set-Content -Path $Path -Value $updated -NoNewline -Encoding UTF8
    return $true
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
    $raw = & tar -xzOf $path "package/package.json" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return "包内没有 package/package.json" }
    $text = (@($raw) -join "`n")
    try { $p = $text | ConvertFrom-Json } catch { return "package.json 解析失败" }
    if ($p.name -ne $PackageName) { return "包名不符：$($p.name)" }
    if ($expectedVersion -and $p.version -ne $expectedVersion) { return "版本不符：$($p.version)" }
    return $null
}

function Get-ReleaseTarball {
    param([string[]]$Urls)
    $dst = Join-Path $env:TEMP $script:AssetName
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
    $tmp = Join-Path $env:TEMP ("bundle-selftest-" + [guid]::NewGuid().ToString("N") + ".json")
    $sample = @'
{
  "name": "dsh-profile-desktop",
  "private": true,
  "dependencies": {
    "dsh-purge": "github:owner/repo#tag"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "dshmarket"
      ]
    },
    "desktopDeselectedBundles": []
  }
}
'@
    Set-Content -Path $tmp -Value $sample -NoNewline -Encoding UTF8

    $changed = Add-BundleEntry -Path $tmp -Name "dsh-purge"
    $parsed = Get-Content $tmp -Raw | ConvertFrom-Json
    $cmd = [regex]::Match((Get-Content $tmp -Raw), '"bundles"\s*:\s*\[([\s\S]*?)\]').Groups[1].Value

    $fails = @()
    if (-not $changed) { $fails += "首次写入应返回 true" }
    if (-not ($parsed.dsh.profile.bundles -contains "dsh-purge")) { $fails += "bundles 未包含目标" }
    if ($parsed.dsh.profile.bundles[0] -ne "@deepseek-ai/dsh-base") { $fails += "原有顺序被打乱" }
    if ($parsed.name -ne "dsh-profile-desktop") { $fails += "其它字段被破坏" }
    if (-not $parsed.dsh.PSObject.Properties["desktopDeselectedBundles"]) { $fails += "desktopDeselectedBundles 丢失" }
    if ($cmd -notmatch '^\s*@deepseek-ai/dsh-base,\s*dshmarket,\s*dsh-purge,?\s*$' -and
        $cmd -notmatch '"dsh-purge"') { $fails += "文本插入位置异常：$cmd" }

    $second = Add-BundleEntry -Path $tmp -Name "dsh-purge"
    if ($second) { $fails += "重复调用应幂等返回 false" }
    $count = ([regex]::Matches((Get-Content $tmp -Raw), '"dsh-purge"')).Count
    if ($count -ne 2) { $fails += "出现次数应为 2（依赖 + bundle），实际 $count" }

    # 空数组分支
    $empty = Join-Path $env:TEMP ("bundle-selftest-empty-" + [guid]::NewGuid().ToString("N") + ".json")
    Set-Content -Path $empty -Value '{"dsh":{"profile":{"bundles":[]}}}' -NoNewline -Encoding UTF8
    $null = Add-BundleEntry -Path $empty -Name "dsh-purge"
    $parsedEmpty = Get-Content $empty -Raw | ConvertFrom-Json
    if (-not ($parsedEmpty.dsh.profile.bundles -contains "dsh-purge")) { $fails += "空数组分支未写入" }

    Remove-Item $tmp, $empty -Force -ErrorAction SilentlyContinue
    if ($fails.Count -gt 0) {
        $fails | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
        exit 1
    }
    Ok "自检通过：写入、幂等、空数组、格式保留"
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
$profiles = Get-ProfileCandidates
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

# 7) 写 bundles
if ($NoBundle) {
    Warn "已跳过 bundles 写入（-NoBundle）：重启后需到「插件」页手动启用"
}
else {
    $bak = "$pkgPath.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $pkgPath $bak -Force
    try {
        $added = Add-BundleEntry -Path $pkgPath -Name $PackageName
        if ($added) { Ok "已写入 dsh.profile.bundles（备份：$(Split-Path -Leaf $bak)）" }
        else { Ok "dsh.profile.bundles 里已有 $PackageName，未改动" }
    }
    catch {
        Copy-Item $bak $pkgPath -Force
        Die "写入 bundles 失败并已回滚：$($_.Exception.Message)" 6
    }
}

# 8) 校验
Say ""
Say "校验"
$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
if ($pkg.dependencies.PSObject.Properties[$PackageName]) {
    Ok "dependencies：$($pkg.dependencies.$PackageName)"
}
else {
    Warn "dependencies 里没有 $PackageName —— 安装可能未落盘"
    $script:ExitCode = 6
}
if (-not $NoBundle) {
    if ($pkg.dsh.profile.bundles -contains $PackageName) { Ok "bundles：已登记" }
    else { Warn "bundles：未登记"; $script:ExitCode = 6 }
}
$modPkg = Join-Path $modPath "package.json"
if (Test-Path $modPkg) {
    $v = (Get-Content $modPkg -Raw | ConvertFrom-Json).version
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
