function Zip-Dir {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ZipDir,
        [string[]]$Ignore,
        [string[]]$Allow,
        [switch]$Clean
    )

    $sourcePath = Resolve-Path -Path $ZipDir -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Path must be a directory: $ZipDir"
    }

    $folderName = Split-Path -Path $sourcePath -Leaf
    $outputPath = Join-Path -Path (Get-Location).Path -ChildPath "$folderName.zip"

    Push-Location -Path $sourcePath
    try {
        $blacklistDirs = @('node_modules', '__pycache__', '.git', '.svn', '.hg', '.venv', 'venv', 'env', 'dist', 'build', '.next', '.nuxt', 'target', 'bin', 'obj', '.idea', '.vscode')
        $blacklistFiles = @('.DS_Store', 'Thumbs.db', 'desktop.ini', 'ehthumbs.db')
        $blacklistExts = @('*.pyc', '*.pyo')

        $allowList = $Allow | ForEach-Object { $_ -split ';' } | Where-Object { $_ -ne '' }
        $ignoreList = $Ignore | ForEach-Object { $_ -split ';' } | Where-Object { $_ -ne '' }

        $baseFiles = & {
            $stack = [System.Collections.Generic.Stack[string]]::new()
            $stack.Push($sourcePath.Path)
            while ($stack.Count -gt 0) {
                $dir = $stack.Pop()
                foreach ($item in Get-ChildItem -LiteralPath $dir) {
                    if ($item.PSIsContainer) {
                        if ($item.Name -notin $blacklistDirs) { $stack.Push($item.FullName) }
                    } else { $item.FullName }
                }
            }
        } | ForEach-Object { $_.Substring($sourcePath.Path.Length + 1) }

        $allowCandidates = $baseFiles
        if ($allowList) {
            $extraFiles = foreach ($d in $blacklistDirs) {
                $p = Join-Path $sourcePath.Path $d
                if (Test-Path -LiteralPath $p) {
                    Get-ChildItem -LiteralPath $p -Recurse -File | ForEach-Object {
                        $_.FullName.Substring($sourcePath.Path.Length + 1)
                    }
                }
            }
            if ($extraFiles) { $allowCandidates = @($allowCandidates) + @($extraFiles) | Select-Object -Unique }
        }

        $allFiles = $baseFiles | Where-Object {
            $f = $_; $skip = $blacklistFiles -contains (Split-Path -Leaf $f)
            if (-not $skip) { foreach ($p in $blacklistExts) { if ($f -like $p) { $skip = $true; break } } }
            -not $skip
        }

        $includeRelative = $null
        $gitignorePath = Join-Path -Path $sourcePath -ChildPath ".gitignore"

        $git = Get-Command -Name "git" -ErrorAction SilentlyContinue
        if ($git -and (Test-Path -LiteralPath $gitignorePath)) {
            $isRepo = git rev-parse --git-dir 2>$null
            if ($isRepo) {
                Write-Host "Using git to resolve .gitignore..." -ForegroundColor Cyan
                $includeRelative = git ls-files --cached --others --exclude-standard
            }
        }

        if (-not $includeRelative -and (Test-Path -LiteralPath $gitignorePath)) {
            Write-Host "Parsing .gitignore manually..." -ForegroundColor Yellow
            $ignorePatterns = Get-Content -Path $gitignorePath | ForEach-Object {
                $line = $_.Trim()
                if ($line -and -not $line.StartsWith('#')) { $line }
            }
            if ($ignorePatterns) {
                $includeRelative = $allFiles | Where-Object {
                    $rel = $_
                    $ignored = $false
                    foreach ($pattern in $ignorePatterns) {
                        $p = $pattern
                        $negate = $p.StartsWith('!')
                        if ($negate) { $p = $p.Substring(1).TrimStart() }
                        if ($p.EndsWith('/')) { $p = $p.TrimEnd('/') + '/**' }
                        $regex = '^' + [regex]::Escape($p).Replace('\*\*\/', '(.*\\/)?').Replace('\*\*', '.*').Replace('\*', '[^\\/]*').Replace('\?', '.') + '$'
                        if ($rel -match $regex) {
                            $ignored = -not $negate
                        }
                    }
                    -not $ignored
                }
            }
            else {
                $includeRelative = $allFiles
            }
        }

        if (-not $includeRelative) {
            Write-Host "No .gitignore found, including all files..." -ForegroundColor Cyan
            $includeRelative = $allFiles
        }

        if ($allowList) {
            Write-Host "Allow patterns: $($allowList -join '; ')" -ForegroundColor Cyan
            $allowed = foreach ($f in $allowCandidates) {
                foreach ($p in $allowList) { if ($f -like $p) { $f; break } }
            }
            $includeRelative = @($includeRelative | Where-Object { $_ }) + @($allowed) | Select-Object -Unique
        }

        if ($ignoreList) {
            Write-Host "Ignore patterns: $($ignoreList -join '; ')" -ForegroundColor Cyan
            $includeRelative = @($includeRelative | Where-Object { $_ }) | Where-Object {
                $f = $_; $m = $false
                foreach ($p in $ignoreList) { if ($f -like $p) { $m = $true; break } }
                -not $m
            }
        }

        if (-not $includeRelative -or $includeRelative.Count -eq 0) {
            Write-Warning "No files to zip in '$sourcePath'"
            return
        }

        if (Test-Path -LiteralPath $outputPath) {
            if (-not $Clean) {
                $choice = $host.UI.PromptForChoice('Overwrite', "File '$folderName.zip' already exists. Overwrite?", @('&Yes', '&No'), 1)
                if ($choice -ne 0) { Write-Host 'Aborted.' -ForegroundColor Yellow; return }
            }
            Remove-Item -LiteralPath $outputPath -Force
        }

        $7zExe = @(
            (Get-Command -Name "7z" -ErrorAction SilentlyContinue).Source,
            (Get-Command -Name "7za" -ErrorAction SilentlyContinue).Source,
            "C:\Program Files\7-Zip\7z.exe",
            "C:\Program Files (x86)\7-Zip\7z.exe",
            "$env:ProgramFiles\7-Zip\7z.exe"
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

        if ($7zExe) {
            Write-Host "Using 7-Zip: $7zExe" -ForegroundColor Cyan
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                [System.IO.File]::WriteAllLines($tempFile, $includeRelative)
                & $7zExe a -tzip -bd $outputPath "@$tempFile"
            }
            finally {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Host "Using Compress-Archive..." -ForegroundColor Cyan
            $includeRelative | Compress-Archive -DestinationPath $outputPath -CompressionLevel Optimal -Force
        }

        if (Test-Path -LiteralPath $outputPath) {
            $item = Get-Item -LiteralPath $outputPath
            Write-Host "Created: $($item.FullName) ($([math]::Round($item.Length / 1KB)) KB)" -ForegroundColor Green
        }
    }
    finally {
        Pop-Location
    }
}

Set-Alias -Name zipdir -Value Zip-Dir
