[CmdletBinding()]
param(
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Lethal Company',
    [switch]$ManifestOnly,
    [switch]$Publish,
    [string]$CommitMessage = "更新翻譯 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dynamicRoot = Join-Path $repoRoot 'dynamic'
$filesRoot = Join-Path $dynamicRoot 'files'
$manifestPath = Join-Path $dynamicRoot 'manifest.txt'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-RelativePath {
    param([string]$Root, [string]$Path)

    return $Path.Substring($Root.Length).TrimStart('\').Replace('\', '/')
}

function Test-DynamicFiles {
    param([string]$Root)

    $terminal = Join-Path $Root 'terminal\LCTC.Terminal.Translations.txt'
    if (-not (Test-Path -LiteralPath $terminal -PathType Leaf)) {
        throw '缺少終端機翻譯：terminal/LCTC.Terminal.Translations.txt'
    }
    if ((Get-Item -LiteralPath $terminal).Length -eq 0) {
        throw '終端機翻譯是空檔案，已停止更新。'
    }

    $allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File)
    if ($allFiles.Count -eq 0) {
        throw '沒有找到任何可發布的翻譯檔案。'
    }

    $totalSize = 0L
    foreach ($file in $allFiles) {
        $relative = Get-RelativePath -Root $Root -Path $file.FullName
        $allowed = $relative -eq 'terminal/LCTC.Terminal.Translations.txt' -or
            $relative -match '^game/Text/[^/]+\.txt$' -or
            $relative -match '^game/Texture/[^/]+\.png$'
        if (-not $allowed) {
            throw "偵測到不允許發布的檔案：$relative"
        }
        if ($file.Length -gt 16MB) {
            throw "檔案超過 16 MB 上限：$relative"
        }
        $totalSize += $file.Length
    }

    if ($totalSize -gt 64MB) {
        throw '翻譯更新總大小超過 64 MB 上限。'
    }

    $textFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'game\Text') -Filter '*.txt' -File -ErrorAction SilentlyContinue)
    if ($textFiles.Count -eq 0) {
        throw '沒有找到遊戲本體文字翻譯。'
    }

    return $allFiles
}

function Write-Manifest {
    param([string]$Root, [string]$OutputPath)

    $files = @(Test-DynamicFiles -Root $Root)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# relative/path|sha256|size')

    foreach ($file in ($files | Sort-Object { Get-RelativePath -Root $Root -Path $_.FullName })) {
        $relative = Get-RelativePath -Root $Root -Path $file.FullName
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines.Add("$relative|$hash|$($file.Length)")
    }

    [System.IO.File]::WriteAllText($OutputPath, (($lines -join "`n") + "`n"), $utf8NoBom)
    return $files.Count
}

if (-not $ManifestOnly) {
    $sourceConfig = Join-Path $GamePath 'BepInEx\config'
    $sourceTerminal = Join-Path $sourceConfig 'LCTC.Terminal.Translations.txt'
    $sourceGame = Join-Path $sourceConfig 'zh-TW'
    $sourceText = $sourceGame
    $sourceTexture = Join-Path $sourceGame 'Texture'

    if (-not (Test-Path -LiteralPath $sourceTerminal -PathType Leaf)) {
        throw "找不到終端機翻譯：$sourceTerminal"
    }
    if (-not (Test-Path -LiteralPath $sourceGame -PathType Container)) {
        throw "找不到遊戲本體翻譯：$sourceGame"
    }

    $token = [Guid]::NewGuid().ToString('N')
    $stagingRoot = Join-Path $dynamicRoot ".files-staging-$token"
    $backupRoot = Join-Path $dynamicRoot ".files-backup-$token"
    $oldMoved = $false

    try {
        New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'terminal') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'game\Text') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'game\Texture') -Force | Out-Null

        Copy-Item -LiteralPath $sourceTerminal -Destination (Join-Path $stagingRoot 'terminal\LCTC.Terminal.Translations.txt')
        Get-ChildItem -LiteralPath $sourceText -Filter '*.txt' -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stagingRoot 'game\Text')
        }
        if (Test-Path -LiteralPath $sourceTexture -PathType Container) {
            Get-ChildItem -LiteralPath $sourceTexture -Filter '*.png' -File | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stagingRoot 'game\Texture')
            }
        }

        $null = Test-DynamicFiles -Root $stagingRoot
        if (Test-Path -LiteralPath $filesRoot) {
            Move-Item -LiteralPath $filesRoot -Destination $backupRoot
            $oldMoved = $true
        }
        Move-Item -LiteralPath $stagingRoot -Destination $filesRoot
        $null = Test-DynamicFiles -Root $filesRoot
        if ($oldMoved) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force
            $oldMoved = $false
        }
    }
    catch {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
        if ($oldMoved -and (Test-Path -LiteralPath $backupRoot)) {
            if (Test-Path -LiteralPath $filesRoot) {
                Remove-Item -LiteralPath $filesRoot -Recurse -Force
            }
            Move-Item -LiteralPath $backupRoot -Destination $filesRoot
        }
        throw
    }
}

$fileCount = Write-Manifest -Root $filesRoot -OutputPath $manifestPath
Write-Host "已產生 manifest：$fileCount 個翻譯檔案。"

if ($Publish) {
    & git -C $repoRoot add -- 'dynamic/files' 'dynamic/manifest.txt'
    if ($LASTEXITCODE -ne 0) {
        throw 'git add 失敗。'
    }

    $staged = @(& git -C $repoRoot diff --cached --name-only)
    $blocked = @($staged | Where-Object {
        $_ -ne 'dynamic/manifest.txt' -and $_ -notmatch '^dynamic/files/'
    })
    if ($blocked.Count -gt 0) {
        throw "暫存區含有翻譯以外的檔案，為避免上傳源代碼已停止：$($blocked -join ', ')"
    }

    & git -C $repoRoot diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host '翻譯沒有變更，不需要發布。'
        exit 0
    }

    & git -C $repoRoot commit -m $CommitMessage
    if ($LASTEXITCODE -ne 0) {
        throw 'git commit 失敗，請先設定 Git 使用者名稱與信箱。'
    }
    & git -C $repoRoot push origin main
    if ($LASTEXITCODE -ne 0) {
        throw 'git push 失敗，請確認 GitHub 登入狀態。'
    }
    Write-Host '翻譯已發布到 GitHub。'
}
