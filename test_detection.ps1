# Test script to demonstrate improved application detection

# Load apps from apps.json
$appsPath = "apps.json"
$apps = @()
if (Test-Path $appsPath) {
    $apps = Get-Content $appsPath -Raw | ConvertFrom-Json
}

Write-Host "Loaded $($apps.Count) applications from apps.json" -ForegroundColor Green

# Test the detection logic
function Test-NameContains {
    param(
        [object[]]$Items,
        [string]$Needle
    )

    if ([string]::IsNullOrWhiteSpace($Needle)) { return $false }

    foreach ($item in $Items) {
        if ($item.DisplayName -and $item.DisplayName.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

# 1. Scan Registry (Fast) - Using PowerShell cmdlets like Python does
$registryApps = @()
$startApps = @()
$installedServices = @{}

Write-Host "`n=== Scanning Registry ===" -ForegroundColor Cyan

# Get installed apps from all registry locations (including HKCU)
$registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach ($path in $registryPaths) {
    try {
        $appsFromPath = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                       Where-Object { $_.DisplayName } | 
                       Select-Object -ExpandProperty DisplayName
        if ($appsFromPath) {
            $registryApps += $appsFromPath
        }
    } catch {
        Write-Host "  Error scanning $path : $_" -ForegroundColor Yellow
    }
}

Write-Host "  Found $($registryApps.Count) registry applications" -ForegroundColor Green

# 2. Get Start Menu apps (like Python does)
Write-Host "`n=== Scanning Start Menu Apps ===" -ForegroundColor Cyan
try {
    $startAppsRaw = Get-StartApps -ErrorAction SilentlyContinue
    if ($startAppsRaw) {
        $startApps = $startAppsRaw | Select-Object -ExpandProperty Name
        Write-Host "  Found $($startApps.Count) start menu applications" -ForegroundColor Green
        Write-Host "  Sample: $($startApps[0..2] -join ', ')" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Error getting Start apps: $_" -ForegroundColor Yellow
}

# 3. Get services if any apps require service checks
Write-Host "`n=== Checking Services ===" -ForegroundColor Cyan
$serviceNames = @()
foreach ($app in $apps) {
    if ($app.checkType -eq "Service" -and $app.checkService) {
        $serviceNames += $app.checkService.Trim()
    }
}

if ($serviceNames.Count -gt 0) {
    $uniqueServices = $serviceNames | Sort-Object -Unique
    Write-Host "  Looking for services: $($uniqueServices -join ', ')" -ForegroundColor Gray
    try {
        $installedServicesRaw = Get-Service -Name $uniqueServices -ErrorAction SilentlyContinue
        foreach ($service in $installedServicesRaw) {
            $installedServices[$service.Name.ToLower()] = $true
        }
        Write-Host "  Found $($installedServicesRaw.Count) services" -ForegroundColor Green
    } catch {
        Write-Host "  Error checking services: $_" -ForegroundColor Yellow
    }
}

# 4. Test detection for each app
Write-Host "`n=== Application Detection Results ===" -ForegroundColor Cyan
Write-Host "App Name`t`tCategory`t`tDetected" -ForegroundColor Magenta
Write-Host "--------`t`t--------`t`t--------" -ForegroundColor Magenta

foreach ($app in $apps) {
    $isInstalled = $false
    $name = $app.name
    $checkType = $app.checkType
    $checkMatch = $app.checkMatch
    $checkPath = $app.checkPath
    $checkService = $app.checkService
    
    try {
        # 1. Primary Check based on checkType (matches Python)
        if ($checkType -eq "Registry" -and $checkMatch) {
            $isInstalled = Test-NameContains -Items ($registryApps | ForEach-Object { [PSCustomObject]@{DisplayName = $_} }) -Needle $checkMatch
        }
        elseif ($checkType -eq "File" -and $checkPath) {
            if (Test-Path $checkPath) {
                $isInstalled = $true
            }
        }
        elseif ($checkType -eq "Service" -and $checkService) {
            if ($checkService -and $installedServices.ContainsKey($checkService.ToLower())) {
                $isInstalled = $true
            }
        }

        # 2. Robust Fallback: Check Registry by App Name if not already found (matches Python)
        if (-not $isInstalled) {
            $isInstalled = Test-NameContains -Items ($registryApps | ForEach-Object { [PSCustomObject]@{DisplayName = $_} }) -Needle $name
        }

        # 3. Final Fallback: Check cached Start Menu apps (Windows 10+) (matches Python)
        if (-not $isInstalled) {
            $isInstalled = Test-NameContains -Items ($startApps | ForEach-Object { [PSCustomObject]@{DisplayName = $_} }) -Needle $name
        }
    } catch {
        # If any error occurs, assume not installed
        $isInstalled = $false
    }
    
    $detectedText = if ($isInstalled) { "YES" } else { "NO" }
    $color = if ($isInstalled) { "Green" } else { "Red" }
    
    Write-Host "$($name.PadRight(30))$($app.category.PadRight(20))$detectedText" -ForegroundColor $color
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$detectedCount = ($apps | ForEach-Object {
    $isInstalled = $false
    $name = $_.name
    $checkType = $_.checkType
    $checkMatch = $_.checkMatch
    $checkPath = $_.checkPath
    $checkService = $_.checkService
    
    # Same logic as above
    if ($checkType -eq "Registry" -and $checkMatch) {
        $isInstalled = Test-NameContains -Items ($registryApps | ForEach-Object { [PSCustomObject]@{DisplayName = $_} }) -Needle $checkMatch
    }
    elseif ($checkType -eq "File" -and $checkPath) {
        if (Test-Path $checkPath) { $isInstalled = $true }
    }
    elseif ($checkType -eq "Service" -and $checkService) {
        if ($checkService -and $installedServices.ContainsKey($checkService.ToLower())) { $isInstalled = $true }
    }
    
    if (-not $isInstalled) {
        $isInstalled = Test-NameContains -Items ($registryApps | ForEach-Object { [PSCustomObject]@{DisplayName = $_} }) -Needle $name
    }
    
    if (-not $isInstalled) {
        $isInstalled = Test-NameContains -Items ($startApps | ForEach-Object { [PSCustomObject]@{DisplayName = $_} }) -Needle $name
    }
    
    $isInstalled
} | Where-Object { $_ -eq $true }).Count

Write-Host "Detected $detectedCount out of $($apps.Count) applications" -ForegroundColor Yellow
Write-Host "Registry scan found $($registryApps.Count) applications" -ForegroundColor Gray
Write-Host "Start menu scan found $($startApps.Count) applications" -ForegroundColor Gray