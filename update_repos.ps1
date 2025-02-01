# cd "D:\FF14 dev plugin" && pwsh -Command ".\update_repos.ps1"
# pwsh -Command ".\update_repos.ps1"

$directories = @(
    "D:\FF14 dev plugin\FF14_Plugins",
    "D:\FF14 dev plugin\FF14_DEV",
    "D:\FF14 dev plugin\FF14_Scripts_Lua\Other Scripts"
)

function Update-Repository {
    param (
        [string]$path
    )
    
    if (Test-Path (Join-Path $path ".git")) {
        Write-Host "`nUpdating repository in: $path" -ForegroundColor Cyan
        Push-Location $path
        
        git fetch
        
        $status = git status --porcelain
        
        if ($status) {
            Write-Host "Local changes detected in $path. Stashing changes..." -ForegroundColor Yellow
            git stash
        }
        
        $currentBranch = git rev-parse --abbrev-ref HEAD
        
        git pull origin $currentBranch
        
        if ($status) {
            Write-Host "Applying stashed changes..." -ForegroundColor Yellow
            git stash pop
        }
        
        Pop-Location
    }
}

foreach ($dir in $directories) {
    if (Test-Path $dir) {
        Write-Host "`nProcessing directory: $dir" -ForegroundColor Green
        
        $repos = Get-ChildItem -Path $dir -Directory
        
        foreach ($repo in $repos) {
            Update-Repository -path $repo.FullName
        }
    }
    else {
        Write-Host "`nDirectory not found: $dir" -ForegroundColor Red
    }
}

Write-Host "`nAll repositories have been updated!" -ForegroundColor Green 
