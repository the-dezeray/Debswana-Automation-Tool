# Debug script to see what's actually in registry and what we're looking for

# Load apps from apps.json
$appsPath = "apps.json"
$apps = @()
if (Test-Path $appsPath) {
    $apps = Get-Content $appsPath -Raw | ConvertFrom-Json
}

Write-Host "Looking for these applications:" -ForegroundColor Cyan
foreach ($app in $apps) {
    Write-Host "  - $($app.name)" -ForegroundColor Gray
    if ($app.checkMatch) { Write-Host "    Check match: $($app.checkMatch)" -ForegroundColor DarkGray }
    if ($app.checkPath) { Write-Host "    Check path: $($app.checkPath)" -ForegroundColor DarkGray }
    if ($app.checkService) { Write-Host "    Check service: $($app.checkService)" -ForegroundColor DarkGray }
}

# Get ALL registry apps
$allRegistryApps = @()
$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

Write-Host "`n=== All Registry Applications ===" -ForegroundColor Cyan
$count = 0
foreach ($path in $registryPaths) {
    try {
        $appsFromPath = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                       Where-Object { $_.DisplayName } | 
                       Select-Object DisplayName
        foreach ($appItem in $appsFromPath) {
            $count++
            Write-Host "  $count. $($appItem.DisplayName)" -ForegroundColor Gray
        }
    } catch {}
}

# Let's check for partial matches
Write-Host "`n=== Checking for Partial Matches ===" -ForegroundColor Cyan
foreach ($app in $apps) {
    $name = $app.name
    $checkMatch = $app.checkMatch
    
    Write-Host "`nLooking for '$name' or '$checkMatch':" -ForegroundColor Yellow
    
    # Check in registry
    $foundInRegistry = $false
    foreach ($path in $registryPaths) {
        try {
            $matches = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                      Where-Object { $_.DisplayName -and 
                          ($_.DisplayName -like "*$name*" -or 
                           ($checkMatch -and $_.DisplayName -like "*$checkMatch*")) }
            if ($matches) {
                $foundInRegistry = $true
                foreach ($match in $matches) {
                    Write-Host "  ✓ Found in registry: $($match.DisplayName)" -ForegroundColor Green
                }
            }
        } catch {}
    }
    
    if (-not $foundInRegistry) {
        Write-Host "  ✗ Not found in registry" -ForegroundColor Red
    }
    
    # Check start apps
    try {
        $startApps = Get-StartApps -ErrorAction SilentlyContinue
        $foundInStart = $startApps | Where-Object { 
            $_.Name -like "*$name*" -or ($checkMatch -and $_.Name -like "*$checkMatch*") 
        }
        if ($foundInStart) {
            foreach ($match in $foundInStart) {
                Write-Host "  ✓ Found in start menu: $($match.Name)" -ForegroundColor Green
            }
        } else {
            Write-Host "  ✗ Not found in start menu" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✗ Error checking start menu: $_" -ForegroundColor Red
    }
}

# Let's also check what common apps ARE installed
Write-Host "`n=== Common Applications Found ===" -ForegroundColor Cyan
$commonPatterns = @(
    "7-Zip", "Adobe", "Microsoft", "Google", "Mozilla", 
    "Chrome", "Firefox", "Python", "Java", "Visual Studio",
    "VLC", "Windows", "Intel", "NVIDIA", "AMD"
)

foreach ($pattern in $commonPatterns) {
    $found = $false
    foreach ($path in $registryPaths) {
        try {
            $matches = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                      Where-Object { $_.DisplayName -like "*$pattern*" }
            if ($matches) {
                $found = $true
                break
            }
        } catch {}
    }
    
    if ($found) {
        Write-Host "  ✓ Found something with '$pattern'" -ForegroundColor Green
    }
}