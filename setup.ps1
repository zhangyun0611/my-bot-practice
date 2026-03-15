# ============================================================
# 一键初始化脚本 (setup.ps1)
# 运行这个脚本，它会帮你：
#   1. 检查 gh 和 claude 是否已装好
#   2. 创建 GitHub 仓库
#   3. 推送练手项目
#   4. 创建需要的 label
# ============================================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  三机器人闭环 — 一键初始化" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- 检查工具 ---
Write-Host "[1/6] 检查必要工具..." -ForegroundColor Yellow

# 检查 gh
try {
    $ghVersion = gh --version 2>&1 | Select-Object -First 1
    Write-Host "  ✅ GitHub CLI: $ghVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ 没有安装 GitHub CLI，请运行: winget install GitHub.cli" -ForegroundColor Red
    exit 1
}

# 检查 gh 是否登录
$ghAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ GitHub CLI 未登录，请运行: gh auth login" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ GitHub CLI 已登录" -ForegroundColor Green

# 检查 claude
try {
    $claudeVersion = claude --version 2>&1
    Write-Host "  ✅ Claude Code CLI: $claudeVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ 没有安装 Claude Code CLI" -ForegroundColor Red
    Write-Host "    请参考: https://docs.claude.com/en/docs/claude-code" -ForegroundColor Yellow
    exit 1
}

# 检查 git
try {
    $gitVersion = git --version 2>&1
    Write-Host "  ✅ Git: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ 没有安装 Git" -ForegroundColor Red
    exit 1
}

# --- 选择项目位置 ---
Write-Host ""
Write-Host "[2/6] 选择项目位置..." -ForegroundColor Yellow

$defaultPath = "$env:USERPROFILE\my-bot-practice"
$projectPath = Read-Host "项目文件夹路径 (直接回车用默认: $defaultPath)"
if ([string]::IsNullOrWhiteSpace($projectPath)) {
    $projectPath = $defaultPath
}

# --- 创建 GitHub 仓库 ---
Write-Host ""
Write-Host "[3/6] 创建 GitHub 仓库..." -ForegroundColor Yellow

$repoName = "my-bot-practice"
Write-Host "  创建仓库: $repoName"

# 先检查仓库是否已存在
$existingRepo = gh repo view $repoName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ⚠️  仓库已存在，跳过创建" -ForegroundColor Yellow
    
    if (-not (Test-Path $projectPath)) {
        gh repo clone $repoName $projectPath 2>&1
    }
} else {
    # 创建新仓库
    gh repo create $repoName --public --description "三机器人闭环练手项目 — AI自动维护代码" --clone $projectPath 2>&1
    Write-Host "  ✅ 仓库创建成功" -ForegroundColor Green
}

# --- 复制项目文件 ---
Write-Host ""
Write-Host "[4/6] 初始化项目文件..." -ForegroundColor Yellow

Set-Location $projectPath

# 复制练手项目文件（如果 src/app.js 不存在的话）
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path "src\app.js")) {
    # 创建目录结构
    New-Item -ItemType Directory -Path "src" -Force | Out-Null
    New-Item -ItemType Directory -Path "_bots\logs" -Force | Out-Null
    
    # 提示用户复制文件
    Write-Host "  请把以下文件复制到项目目录:" -ForegroundColor Yellow
    Write-Host "    - practice-project/* 的内容 → $projectPath\" -ForegroundColor White
    Write-Host "    - _bots/*.ps1 → $projectPath\_bots\" -ForegroundColor White
    Write-Host ""
    Write-Host "  或者你可以手动把下载的文件拖进去" -ForegroundColor Yellow
} else {
    Write-Host "  ✅ 项目文件已存在" -ForegroundColor Green
}

# 确保 _bots/logs 目录存在
New-Item -ItemType Directory -Path "_bots\logs" -Force | Out-Null

# --- 创建 GitHub Labels ---
Write-Host ""
Write-Host "[5/6] 创建 GitHub Labels..." -ForegroundColor Yellow

# 创建 bot-audit label
gh label create "bot-audit" --description "审核机器人创建的Issue" --color "D93F0B" 2>&1 | Out-Null
Write-Host "  ✅ Label: bot-audit (红色)" -ForegroundColor Green

# 创建 bot-fix label  
gh label create "bot-fix" --description "修复机器人创建的PR" --color "0E8A16" 2>&1 | Out-Null
Write-Host "  ✅ Label: bot-fix (绿色)" -ForegroundColor Green

# --- 初始提交 ---
Write-Host ""
Write-Host "[6/6] 提交并推送..." -ForegroundColor Yellow

git add -A 2>&1 | Out-Null
$hasChanges = git diff --cached --name-only 2>&1
if ($hasChanges) {
    git commit -m "init: 练手项目初始化 — 三机器人闭环" 2>&1 | Out-Null
    git push origin main 2>&1 | Out-Null
    Write-Host "  ✅ 已推送到 GitHub" -ForegroundColor Green
} else {
    Write-Host "  ✅ 没有新文件需要提交" -ForegroundColor Green
}

# --- 完成 ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ 初始化完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "项目位置: $projectPath" -ForegroundColor White
Write-Host ""
Write-Host "接下来手动测试一轮：" -ForegroundColor Yellow
Write-Host "  cd $projectPath" -ForegroundColor White
Write-Host "  powershell -File _bots\audit.ps1    # 审核" -ForegroundColor White
Write-Host "  powershell -File _bots\fix.ps1      # 修复" -ForegroundColor White
Write-Host "  powershell -File _bots\review.ps1   # 审查合并" -ForegroundColor White
Write-Host ""
Write-Host "看到 Issue → PR → 合并 的流程跑通后，" -ForegroundColor Yellow
Write-Host "再设置定时任务让它自动循环。" -ForegroundColor Yellow
Write-Host ""
