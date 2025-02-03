# cd "D:\FF14 dev plugin\Pulling-multiple-repositories" && pwsh -Command ".\update_repos.ps1"
# pwsh -Command ".\update_repos.ps1"

$config = @{
    MaxParallelJobs = 5
    ShowProgress = $true
    ForceUpdate = $false
    EnableOptimization = $true
    OptimizationChance = 10
    StashChanges = $true
    ProgressBarWidth = 50
    ProgressUpdateInterval = 250
}

$directories = @(
    "D:\FF14 dev plugin\FF14_Plugins",
    "D:\FF14 dev plugin\FF14_DEV",
    "D:\FF14 dev plugin\FF14_Scripts_Lua\Other Scripts"
)

function Update-Repository {
    param (
        [string]$path
    )
    
    try {
        if (-not (Test-Path (Join-Path $path ".git"))) {
            Write-Error "Not a git repository: $path"
            return @{
                Success = $false
                Error = "Not a git repository"
                Path = $path
            }
        }

        Push-Location $path -ErrorAction Stop
        
        $env:GIT_TERMINAL_PROMPT = 0
        git config --global credential.helper cache 2>&1 | Out-Null
        
        $fetchOutput = git fetch --prune --no-progress --quiet origin 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git fetch failed: $fetchOutput"
        }
        
        $status = git status --porcelain
        $stashed = $false
        
        if ($status -and $config.StashChanges) {
            git stash push -q -m "Auto stash before update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>&1 | Out-Null
            $stashed = $true
        } elseif ($status -and $config.ForceUpdate) {
            git reset --hard HEAD 2>&1 | Out-Null
            git clean -fd 2>&1 | Out-Null
        }
        
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get current branch"
        }
        
        $upstreamBranch = & git rev-parse --abbrev-ref '@{upstream}' 2>$null
        if ($LASTEXITCODE -ne 0) {
            $upstreamBranch = "origin/$currentBranch"
            & git branch --set-upstream-to="$upstreamBranch" "$currentBranch" 2>$null
        }
        
        $localCommit = git rev-parse HEAD 2>&1
        $remoteCommit = & git rev-parse '@{upstream}' 2>$null
        
        if ($localCommit -ne $remoteCommit) {
            $pullOutput = git pull --rebase --autostash --quiet origin $currentBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Git pull failed: $pullOutput"
            }
            
            if ($config.EnableOptimization -and (Get-Random -Minimum 1 -Maximum 100) -le $config.OptimizationChance) {
                git gc --auto --quiet 2>&1 | Out-Null
                git prune --quiet 2>&1 | Out-Null
            }
        }
        
        if ($stashed) {
            git stash pop --quiet 2>&1 | Out-Null
        }
        
        Pop-Location
        return @{
            Success = $true
            Path = $path
            Branch = $currentBranch
            Updated = ($localCommit -ne $remoteCommit)
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($stashed) {
            git stash pop --quiet 2>&1 | Out-Null
        }
        Pop-Location
        return @{
            Success = $false
            Error = $errorMessage
            Path = $path
        }
    }
}

try {
    $startTime = Get-Date
    $lastProgressUpdate = [DateTime]::MinValue
    Write-Host "`nStarting repository update process" -ForegroundColor Cyan
    
    $allRepos = @()
    foreach ($dir in $directories) {
        if (Test-Path $dir) {
            Write-Host "Scanning directory: $dir" -ForegroundColor Cyan
            $allRepos += Get-ChildItem -Path $dir -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
        }
        else {
            Write-Host "Directory not found: $dir" -ForegroundColor Red
        }
    }
    
    $totalRepos = $allRepos.Count
    Write-Host "Found $totalRepos repositories to update`n" -ForegroundColor Cyan
    
    $jobs = @()
    $completed = 0
    
    $jobScriptBlock = {
        param($repoPath)
        
        try {
            if (-not (Test-Path (Join-Path $repoPath ".git"))) {
                return @{
                    Success = $false
                    Error = "Not a git repository"
                    Path = $repoPath
                }
            }

            Push-Location $repoPath
            
            $env:GIT_TERMINAL_PROMPT = 0
            git config --global credential.helper cache 2>&1 | Out-Null
            
            $fetchOutput = git fetch --prune --no-progress --quiet origin 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Git fetch failed: $fetchOutput"
            }
            
            $status = git status --porcelain
            if ($status) {
                git stash push -q -m "Auto stash before update" 2>&1 | Out-Null
            }
            
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
            
            $localCommit = git rev-parse HEAD 2>&1
            $remoteCommit = & git rev-parse '@{upstream}' 2>$null
            
            if ($localCommit -ne $remoteCommit) {
                $pullOutput = git pull --rebase --autostash --quiet origin $currentBranch 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Git pull failed: $pullOutput"
                }
            }
            
            if ($status) {
                git stash pop --quiet 2>&1 | Out-Null
            }
            
            Pop-Location
            return @{
                Success = $true
                Path = $repoPath
                Branch = $currentBranch
                Updated = ($localCommit -ne $remoteCommit)
            }
        }
        catch {
            Pop-Location
            return @{
                Success = $false
                Error = $_.Exception.Message
                Path = $repoPath
            }
        }
    }
    
    foreach ($repo in $allRepos) {
        while ((Get-Job -State Running).Count -ge $config.MaxParallelJobs) {
            Get-Job | Wait-Job -Any | Out-Null
            
            if ($config.ShowProgress) {
                $now = Get-Date
                if (($now - $lastProgressUpdate).TotalMilliseconds -ge $config.ProgressUpdateInterval) {
                    $completed = (Get-Job -State Completed).Count
                    $percent = [math]::Round(($completed / $totalRepos) * 100)
                    
                    $progressWidth = $config.ProgressBarWidth
                    $completedWidth = [math]::Round(($completed / $totalRepos) * $progressWidth)
                    $remainingWidth = $progressWidth - $completedWidth
                    
                    $progressBar = "[" + ("=" * $completedWidth) + (" " * $remainingWidth) + "]"
                    
                    $statusText = "$completed of $totalRepos repositories processed ($percent%)"
                    
                    $status = "{0} {1}" -f $statusText.PadRight(37), $progressBar
                    
                    $progress = @{
                        Activity = "Updating Git Repositories"
                        Status = $status
                        PercentComplete = $percent
                    }
                    Write-Progress @progress
                    $lastProgressUpdate = $now
                }
            }
        }
        
        $jobs += Start-Job -ScriptBlock $jobScriptBlock -ArgumentList $repo.FullName
    }
    
    Wait-Job $jobs | Out-Null
    
    $successCount = 0
    $failCount = 0
    $updatedRepos = @()
    $failedRepos = @()
    
    foreach ($job in $jobs) {
        $result = Receive-Job $job -ErrorAction Continue
        if ($result.Success) {
            $successCount++
            if ($result.Updated) {
                $updatedRepos += "$($result.Path) ($($result.Branch))"
            }
        } else {
            $failCount++
            $failedRepos += "$($result.Path) - $($result.Error)"
        }
        Remove-Job $job
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Host "`nUpdate process completed in $($duration.TotalMinutes.ToString('0.00')) minutes" -ForegroundColor Green
    Write-Host "Successfully updated: $successCount repositories" -ForegroundColor Green
    
    if ($updatedRepos.Count -gt 0) {
        Write-Host "`nUpdated repositories:" -ForegroundColor Cyan
        $updatedRepos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Cyan }
    }
    
    if ($failCount -gt 0) {
        Write-Host "`nFailed to update: $failCount repositories" -ForegroundColor Yellow
        Write-Host "Failed repositories:" -ForegroundColor Yellow
        $failedRepos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
}
catch {
    Write-Host "Critical error in main execution: $_" -ForegroundColor Red
}
finally {
    if ($config.ShowProgress) {
        Write-Progress -Activity "Updating Git Repositories" -Completed
    }
} 