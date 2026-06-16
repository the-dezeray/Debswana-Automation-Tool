Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

# ── Resolve paths ────────────────────────────────────────────
if (-not $ToolDir) { $ToolDir = (Get-Location).Path }
$AppsJsonPath = Join-Path $ToolDir "apps.json"
$LogoPath = Join-Path $ToolDir "image.png"

# ── Shell Copy Helper ────────────────────────────────────────
function Copy-WithWindowsDialog {
    param([string]$SourcePath, [string]$DestPath)
    $shell = New-Object -ComObject "Shell.Application"
    if (-not (Test-Path $DestPath)) {
        New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
    }
    $folder = $shell.NameSpace($DestPath)
    $folder.CopyHere($SourcePath, 4) # 4 = "Yes to All"
}

# ── Network Path Helper with Timeout ────────────────────────
function Test-PathWithTimeout {
    param([string]$Path, [int]$TimeoutSeconds = 5)
    $job = Start-Job -ScriptBlock { param($p) Test-Path $p } -ArgumentList $Path
    $timeout = [DateTime]::Now.AddSeconds($TimeoutSeconds)
    
    # Loop to allow UI to breathe while waiting for path check
    while (($job.State -eq 'Running') -and ([DateTime]::Now -lt $timeout)) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
    
    if ($job.State -eq 'Completed') {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job -Force
        return $result
    } else {
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        return $false
    }
}

# ── Get all installed programs (64-bit, 32-bit, and per-user) ──
function Get-InstalledPrograms {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $items = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher
    }

    return $items | Sort-Object DisplayName -Unique
}

# Global cache for installed programs to speed up UI
$script:InstalledCache = $null

# ── Installation Detection Helper ────────────────────────────
function Test-AppInstalled {
    param([psobject]$App)
    if (-not $App) { return $false }

    # Refresh cache if empty
    if ($null -eq $script:InstalledCache) {
        $script:InstalledCache = Get-InstalledPrograms
    }

    # 1. Use specific check criteria
    if ($App.checkType) {
        switch ($App.checkType) {
            "Registry" {
                if ($App.checkMatch) {
                    # Case-insensitive partial match
                    $found = $script:InstalledCache | Where-Object { $_.DisplayName -like "*$($App.checkMatch)*" }
                    if ($found) { return $true }
                }
            }
            "File" {
                if ($App.checkPath -and (Test-Path $App.checkPath)) { return $true }
            }
            "Service" {
                if ($App.checkService) {
                    $svc = Get-Service -Name $App.checkService -ErrorAction SilentlyContinue
                    if ($svc) { return $true }
                }
            }
        }
    }

    # 2. Robust Fallback: Check Registry by app name
    if ($App.name) {
        $nameMatch = $script:InstalledCache | Where-Object { $_.DisplayName -like "*$($App.name)*" }
        if ($nameMatch) { return $true }
        
        # 3. Fallback: Windows Start Apps
        $startApps = Get-StartApps -Name "*$($App.name)*" -ErrorAction SilentlyContinue
        if ($startApps) { return $true }
    }

    return $false
}

# ── Install Helper (Responsive) ────────────────────────────────
function Run {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Args = "",
        [string]$WorkingDir = "",
        [System.Windows.Forms.Label]$StatusLabel,
        [bool]$RunAsAdmin = $false,
        [bool]$KeepWindowOpen = $false
    )

    $StatusLabel.Text = "Checking network path for $Name..."
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    [System.Windows.Forms.Application]::DoEvents()

    $pathExists = Test-PathWithTimeout -Path $Path -TimeoutSeconds 5
    if (-not $pathExists) {
        $StatusLabel.Text = "$([char]0x2716) Cannot access: $Path"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        return $false
    }

    $StatusLabel.Text = "Launching installer: $Name ..."
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $params = @{ FilePath = $Path; PassThru = $true }
        
        if ($KeepWindowOpen) {
            # Use cmd /k to keep window open. Wrap path in quotes for safety.
            $params.FilePath = "cmd.exe"
            $params.ArgumentList = "/k `"$Path`" $Args"
        } else {
            if ($Args) { $params.ArgumentList = $Args }
        }

        if ($WorkingDir) { $params.WorkingDirectory = $WorkingDir }
        if ($RunAsAdmin) { $params.Verb = "RunAs" }

        $proc = Start-Process @params
        while (-not $proc.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
        }

        $StatusLabel.Text = "$([char]0x2714) $Name - Installation completed."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Green
        return $true
    } catch {
        $StatusLabel.Text = "$([char]0x2716) Error installing: $Name"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        return $false
    }
}

# ── Check WiFi Connection ───────────────────────────────────
function Test-DebsWiFi {
    try {
        $networks = netsh wlan show interfaces
        if ($networks -match "SSID\s+:\s+(.+)") {
            $currentSSID = $matches[1].Trim()
            return @{ Connected = $true; SSID = $currentSSID; IsDebs = $currentSSID -like "*debs*" }
        }
        return @{ Connected = $false; SSID = ""; IsDebs = $false }
    } catch {
        return @{ Connected = $false; SSID = ""; IsDebs = $false }
    }
}

function Show-CorporateWifiWarning {
    param(
        [System.Windows.Forms.Form]$Owner,
        [hashtable]$WifiStatus,
        [string]$LogoPath
    )

    $warning = New-Object System.Windows.Forms.Form
    $warning.Text = "Corporate WiFi Required"
    $warning.Size = New-Object System.Drawing.Size(520, 300)
    $warning.StartPosition = "CenterParent"
    $warning.FormBorderStyle = "FixedDialog"
    $warning.MaximizeBox = $false
    $warning.MinimizeBox = $false
    $warning.BackColor = [System.Drawing.Color]::White
    $warning.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $topBar = New-Object System.Windows.Forms.Panel
    $topBar.Dock = "Top"
    $topBar.Height = 78
    $topBar.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $warning.Controls.Add($topBar)

    if (Test-Path $LogoPath) {
        $logoBox = New-Object System.Windows.Forms.PictureBox
        $logoBox.Location = New-Object System.Drawing.Point(22, 18)
        $logoBox.Size = New-Object System.Drawing.Size(180, 34)
        $logoBox.SizeMode = "Zoom"
        try {
            $logoBox.Image = [System.Drawing.Image]::FromFile($LogoPath)
            $topBar.Controls.Add($logoBox)
        } catch {}
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Connect to DEBS WiFi"
    $title.Location = New-Object System.Drawing.Point(28, 100)
    $title.Size = New-Object System.Drawing.Size(455, 32)
    $title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(45, 70, 95)
    $warning.Controls.Add($title)

    $currentNetwork = if ($WifiStatus.Connected -and $WifiStatus.SSID) { $WifiStatus.SSID } else { "No WiFi network detected" }

    $message = New-Object System.Windows.Forms.Label
    $message.Text = "You are currently connected to: $currentNetwork`r`n`r`nThis tool uses Debswana network locations. Accessing installers and shared paths will not work unless you are connected to the corporate DEBS WiFi."
    $message.Location = New-Object System.Drawing.Point(30, 142)
    $message.Size = New-Object System.Drawing.Size(452, 74)
    $message.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $message.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $warning.Controls.Add($message)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "OK"
    $okBtn.Location = New-Object System.Drawing.Point(382, 228)
    $okBtn.Size = New-Object System.Drawing.Size(100, 34)
    $okBtn.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $okBtn.ForeColor = [System.Drawing.Color]::White
    $okBtn.FlatStyle = "Flat"
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $warning.AcceptButton = $okBtn
    $warning.Controls.Add($okBtn)

    $warning.ShowDialog($Owner) | Out-Null
}

# ── Open Path Helper ─────────────────────────────────────────
function Open-AppPath {
    param([psobject]$App)
    $pathToOpen = $null
    if ($App.type -eq "copy-then-run" -and $App.destDir) { $pathToOpen = $App.destDir }
    elseif ($App.path) { $pathToOpen = Split-Path $App.path -Parent }
    
    if ($pathToOpen -and (Test-PathWithTimeout -Path $pathToOpen -TimeoutSeconds 3)) {
        Start-Process "explorer.exe" -ArgumentList $pathToOpen
    } else {
        [System.Windows.Forms.MessageBox]::Show("Cannot access path.`nIt may be disconnected or missing.", "Error")
    }
}

# ── Run an app entry (handles plain exe / copy-then-run) ──
function Invoke-AppEntry {
    param([psobject]$App, [System.Windows.Forms.Label]$StatusLabel)

    # Extract new properties with defaults
    $runAsAdmin = if ($App.runAsAdmin) { $true } else { $false }
    $keepWindowOpen = if ($App.keepWindowOpen) { $true } else { $false }

    if ($App.type -eq "copy-then-run") {
        $StatusLabel.Text = "Checking source path for $($App.name)..."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        [System.Windows.Forms.Application]::DoEvents()

        if (-not (Test-PathWithTimeout -Path $App.path -TimeoutSeconds 5)) {
            $StatusLabel.Text = "$([char]0x2716) Cannot access source path"
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            return $false
        }

        $StatusLabel.Text = "Copying installation files for $($App.name)..."
        try {
            Copy-WithWindowsDialog $App.path $App.destDir
            $exePath = Join-Path $App.destDir $App.exeName
            if (-not (Test-PathWithTimeout -Path $exePath -TimeoutSeconds 3)) {
                $StatusLabel.Text = "$([char]0x2716) Installation aborted - Files not copied"
                $StatusLabel.ForeColor = [System.Drawing.Color]::Red
                return $false
            }

            $StatusLabel.Text = "🚀 Files verified. Launching installer..."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Green
            [System.Windows.Forms.Application]::DoEvents()
            return Run -Path $exePath -Name $App.name -Args $App.args -WorkingDir $App.destDir -StatusLabel $StatusLabel -RunAsAdmin $runAsAdmin -KeepWindowOpen $keepWindowOpen
        } catch {
            $StatusLabel.Text = "$([char]0x2716) Error processing $($App.name) files."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            return $false
        }
    } else {
        return Run -Path $App.path -Name $App.name -Args $App.args -WorkingDir $App.workingDir -StatusLabel $StatusLabel -RunAsAdmin $runAsAdmin -KeepWindowOpen $keepWindowOpen
    }
}

# ── Load/Save JSON ──────────────────────────────────────────
function Get-Apps {
    param([string]$JsonPath)
    if (-not (Test-Path $JsonPath)) { return @() }
    $raw = Get-Content -Path $JsonPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    try { return @($raw | ConvertFrom-Json) } catch { return @() }
}

function Save-Apps {
    param([array]$Apps, [string]$JsonPath)
    $json = $Apps | ConvertTo-Json -Depth 5
    if ($Apps.Count -eq 1 -and -not $json.TrimStart().StartsWith("[")) { $json = "[`n$json`n]" }
    Set-Content -Path $JsonPath -Value $json -Encoding UTF8
}

# ── Core Setup & Data ────────────────────────────────────────
$script:AllApps = Get-Apps -JsonPath $AppsJsonPath
$script:SelectedCategory = "All"
$wifiStatus = Test-DebsWiFi

# ── Main form ────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "Desiree Software Center"
$form.Size = New-Object System.Drawing.Size(1000, 750)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 255)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Set form icon from logo
if (Test-Path $LogoPath) {
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($LogoPath)
    } catch {}
}

# ── Header ───────────────────────────────────────────────────
$header = New-Object System.Windows.Forms.Panel
$header.Size = New-Object System.Drawing.Size(1000, 60)
$header.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$form.Controls.Add($header)

$headerTitle = New-Object System.Windows.Forms.Label
$headerTitle.Text = "   Debswana IT Automation Tool"
$headerTitle.ForeColor = [System.Drawing.Color]::White
$headerTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
$headerTitle.Location = New-Object System.Drawing.Point(0, 15)
$headerTitle.Size = New-Object System.Drawing.Size(400, 40)
$header.Controls.Add($headerTitle)

$connStatus = New-Object System.Windows.Forms.Label
$connStatus.Location = New-Object System.Drawing.Point(700, 20)
$connStatus.Size = New-Object System.Drawing.Size(270, 30)
$connStatus.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$connStatus.TextAlign = "MiddleRight"
if ($wifiStatus.IsDebs) {
    $connStatus.Text = "● DEBS WiFi Connected"
    $connStatus.ForeColor = [System.Drawing.Color]::LightGreen
} else {
    $connStatus.Text = "● Not Connected"
    $connStatus.ForeColor = [System.Drawing.Color]::LightCoral
}
$header.Controls.Add($connStatus)

# ── Sidebar (Navigation) ─────────────────────────────────────
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = New-Object System.Drawing.Point(0, 60)
$sidebar.Size = New-Object System.Drawing.Size(200, 650)
$sidebar.BackColor = [System.Drawing.Color]::White
$sidebar.BorderStyle = "FixedSingle"
$form.Controls.Add($sidebar)

$sidebarTitle = New-Object System.Windows.Forms.Label
$sidebarTitle.Text = "CATEGORIES"
$sidebarTitle.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$sidebarTitle.ForeColor = [System.Drawing.Color]::Gray
$sidebarTitle.Location = New-Object System.Drawing.Point(15, 20)
$sidebar.Controls.Add($sidebarTitle)

$sidebarY = 45
$categories = @("All", "Standard", "Mining", "Oil Processing", "IM", "Uninstallers")
$navButtons = @()

foreach ($cat in $categories) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "  $cat"
    $btn.Tag = $cat
    $btn.Location = New-Object System.Drawing.Point(10, $sidebarY)
    $btn.Size = New-Object System.Drawing.Size(180, 35)
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.TextAlign = "MiddleLeft"
    $btn.Cursor = "Hand"
    
    if ($cat -eq "All") {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 255)
        $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
    } else {
        $btn.BackColor = [System.Drawing.Color]::White
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    }

    $btn.Add_Click({
        $script:SelectedCategory = $this.Tag
        foreach ($b in $navButtons) {
            if ($b.Tag -eq $script:SelectedCategory) {
                $b.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 255)
                $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
            } else {
                $b.BackColor = [System.Drawing.Color]::White
                $b.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            }
        }
        Apply-Filters
    })
    
    $sidebar.Controls.Add($btn)
    $navButtons += $btn
    $sidebarY += 40
}

# Credits in Sidebar Bottom
$refreshStatusBtn = New-Object System.Windows.Forms.Button
$refreshStatusBtn.Text = "🔄 Refresh Status"
$refreshStatusBtn.Location = New-Object System.Drawing.Point(10, 480)
$refreshStatusBtn.Size = New-Object System.Drawing.Size(180, 35)
$refreshStatusBtn.BackColor = [System.Drawing.Color]::White
$refreshStatusBtn.FlatStyle = "Flat"
$refreshStatusBtn.Cursor = "Hand"
$refreshStatusBtn.Add_Click({
    $script:InstalledCache = $null
    Apply-Filters
})
$sidebar.Controls.Add($refreshStatusBtn)

$credits = New-Object System.Windows.Forms.Label
$credits.Text = "Built by Desiree Chingwaru, Odirile Mathepeo "
$credits.Location = New-Object System.Drawing.Point(10, 525)
$credits.Size = New-Object System.Drawing.Size(180, 50)
$credits.ForeColor = [System.Drawing.Color]::Gray
$credits.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$sidebar.Controls.Add($credits)

# Logo in sidebar below credits
if (Test-Path $LogoPath) {
    $sidebarLogo = New-Object System.Windows.Forms.PictureBox
    $sidebarLogo.Location = New-Object System.Drawing.Point(20, 585)
    $sidebarLogo.Size = New-Object System.Drawing.Size(160, 29)
    $sidebarLogo.SizeMode = "Zoom"
    try {
        $sidebarLogo.Image = [System.Drawing.Image]::FromFile($LogoPath)
        $sidebar.Controls.Add($sidebarLogo)
    } catch {}
}

# ── Top Bar (Search & Actions) ───────────────────────────────
$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(220, 80)
$searchBox.Size = New-Object System.Drawing.Size(350, 24)
$searchBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($searchBox)

$installAllBtn = New-Object System.Windows.Forms.Button
$installAllBtn.Text = "⚡ Install All Standard"
$installAllBtn.Location = New-Object System.Drawing.Point(640, 78)
$installAllBtn.Size = New-Object System.Drawing.Size(160, 30)
$installAllBtn.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$installAllBtn.ForeColor = [System.Drawing.Color]::White
$installAllBtn.FlatStyle = "Flat"
$installAllBtn.Cursor = "Hand"
$form.Controls.Add($installAllBtn)

$addAppBtn = New-Object System.Windows.Forms.Button
$addAppBtn.Text = "+ Add App"
$addAppBtn.Location = New-Object System.Drawing.Point(810, 78)
$addAppBtn.Size = New-Object System.Drawing.Size(100, 30)
$addAppBtn.BackColor = [System.Drawing.Color]::White
$addAppBtn.FlatStyle = "Flat"
$addAppBtn.Cursor = "Hand"
$form.Controls.Add($addAppBtn)

# ── Two-Column Dashboard Panel ───────────────────────────────
$dashboardPanel = New-Object System.Windows.Forms.Panel
$dashboardPanel.Location = New-Object System.Drawing.Point(220, 130)
$dashboardPanel.Size = New-Object System.Drawing.Size(750, 520)
$dashboardPanel.AutoScroll = $true
$form.Controls.Add($dashboardPanel)

# ── Progress and Status ──────────────────────────────────────
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(220, 660)
$progressBar.Size = New-Object System.Drawing.Size(730, 15)
$form.Controls.Add($progressBar)

$status = New-Object System.Windows.Forms.Label
$status.Text = "$([char]0x2714) Ready."
$status.Location = New-Object System.Drawing.Point(220, 680)
$status.Size = New-Object System.Drawing.Size(730, 20)
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($status)

# ── Render Application Cards ─────────────────────────────────
function Render-AppCards {
    param([array]$Apps)
    $dashboardPanel.Controls.Clear()
    $index = 0

    foreach ($app in $Apps) {
        # Two-Column layout math
        $col = $index % 2
        $row = [Math]::Floor($index / 2)
        $x = if ($col -eq 0) { 0 } else { 370 }
        $y = $row * 85

        $card = New-Object System.Windows.Forms.Panel
        $card.Size = New-Object System.Drawing.Size(350, 75)
        $card.Location = New-Object System.Drawing.Point($x, $y)
        $card.BorderStyle = "FixedSingle"

        # Color coding
        switch ($app.category) {
            "Standard"     { $card.BackColor = [System.Drawing.Color]::FromArgb(225, 240, 255) }
            "Mining"       { $card.BackColor = [System.Drawing.Color]::FromArgb(200, 230, 255) }
            "IM"           { $card.BackColor = [System.Drawing.Color]::FromArgb(210, 235, 255) }
            "Uninstallers" { $card.BackColor = [System.Drawing.Color]::FromArgb(180, 220, 255) }
            default        { $card.BackColor = [System.Drawing.Color]::White }
        }

        # App Name Label
        $appName = New-Object System.Windows.Forms.Label
        $appName.Text = $app.name
        $appName.Location = New-Object System.Drawing.Point(15, 15)
        $appName.Size = New-Object System.Drawing.Size(200, 20)
        $appName.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
        $card.Controls.Add($appName)

        # Category Label
        $appCat = New-Object System.Windows.Forms.Label
        $appCat.Text = $app.category
        $appCat.Location = New-Object System.Drawing.Point(15, 35)
        $appCat.Size = New-Object System.Drawing.Size(150, 15)
        $appCat.ForeColor = [System.Drawing.Color]::Gray
        $appCat.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $card.Controls.Add($appCat)

        # Action Button / Status Badge
        $btnAction = New-Object System.Windows.Forms.Button
        $btnAction.Location = New-Object System.Drawing.Point(245, 22)
        $btnAction.Size = New-Object System.Drawing.Size(85, 30)
        $btnAction.Tag = $app
        $btnAction.Cursor = "Hand"
        $btnAction.FlatStyle = "Flat"
        
        # Robust installation check
        if (Test-AppInstalled -App $app) {
            $btnAction.Text = "Installed"
            $btnAction.BackColor = [System.Drawing.Color]::MediumSeaGreen
            $btnAction.ForeColor = [System.Drawing.Color]::White
        } else {
            $btnAction.Text = "Install"
            $btnAction.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
            $btnAction.ForeColor = [System.Drawing.Color]::White
        }
        
        # Left Click - Install
        $btnAction.Add_Click({
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            $success = Invoke-AppEntry -App $this.Tag -StatusLabel $status
            
            # Immediately flip UI to green on completion success
            if ($success) {
                # Reset cache so next check is accurate
                $script:InstalledCache = $null
                $this.Text = "Installed"
                $this.BackColor = [System.Drawing.Color]::MediumSeaGreen
                $this.ForeColor = [System.Drawing.Color]::White
            }
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        })
        
        # Right Click - Show Context Menu
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        $menuItemPath = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItemPath.Text = "Open Path"
        $menuItemPath.Tag = $app
        $menuItemPath.Add_Click({ Open-AppPath -App $this.Tag })
        $contextMenu.Items.Add($menuItemPath)
        
        $btnAction.ContextMenuStrip = $contextMenu
        $card.Controls.Add($btnAction)

        $dashboardPanel.Controls.Add($card)
        $index++
    }
}

# ── Filtering Logic ──────────────────────────────────────────
function Apply-Filters {
    $term = $searchBox.Text.Trim()
    $filtered = if ($script:SelectedCategory -eq "All") { $script:AllApps } 
                else { $script:AllApps | Where-Object { $_.category -eq $script:SelectedCategory } }
    
    if (-not [string]::IsNullOrEmpty($term)) {
        $filtered = $filtered | Where-Object { $_.name -like "*$term*" -or $_.category -like "*$term*" }
    }
    Render-AppCards -Apps $filtered
}

$searchBox.Add_TextChanged({ Apply-Filters })

# ── Install All Handler ──────────────────────────────────────
$installAllBtn.Add_Click({
    $standardApps = $script:AllApps | Where-Object { $_.standard -eq $true -or $_.category -eq "Standard" }
    if ($standardApps.Count -eq 0) { 
        [System.Windows.Forms.MessageBox]::Show("No standard applications found.", "Info")
        return 
    }

    # ── Create Selection Dialog ─────────────────────────────────
    $selectDlg = New-Object System.Windows.Forms.Form
    $selectDlg.Text = "Select Applications to Install"
    $selectDlg.Size = New-Object System.Drawing.Size(750, 650)
    $selectDlg.StartPosition = "CenterParent"
    $selectDlg.FormBorderStyle = "FixedDialog"
    $selectDlg.MaximizeBox = $false
    $selectDlg.BackColor = [System.Drawing.Color]::White

    # Header
    $selectHeader = New-Object System.Windows.Forms.Label
    $selectHeader.Text = "Select the standard applications you want to install:"
    $selectHeader.Location = New-Object System.Drawing.Point(20, 20)
    $selectHeader.Size = New-Object System.Drawing.Size(700, 25)
    $selectHeader.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $selectDlg.Controls.Add($selectHeader)

    # Scrollable panel for checkboxes
    $checkboxPanel = New-Object System.Windows.Forms.Panel
    $checkboxPanel.Location = New-Object System.Drawing.Point(20, 55)
    $checkboxPanel.Size = New-Object System.Drawing.Size(690, 460)
    $checkboxPanel.BorderStyle = "FixedSingle"
    $checkboxPanel.AutoScroll = $true
    $checkboxPanel.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $selectDlg.Controls.Add($checkboxPanel)

    # Create checkboxes and status labels for each standard app
    $checkboxes = @()
    $statusLabels = @{}
    $yPos = 10
    foreach ($app in $standardApps) {
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Text = "$($app.name) - $($app.category)"
        $checkbox.Location = New-Object System.Drawing.Point(15, $yPos)
        $checkbox.Size = New-Object System.Drawing.Size(250, 25)
        $checkbox.Checked = $true  # Default: all selected
        $checkbox.Tag = $app
        $checkbox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $checkboxPanel.Controls.Add($checkbox)
        $checkboxes += $checkbox

        $statusLbl = New-Object System.Windows.Forms.Label
        $statusLbl.Text = ""
        $statusLbl.ForeColor = [System.Drawing.Color]::Gray
        $statusLbl.Location = New-Object System.Drawing.Point(270, ($yPos + 3))
        $statusLbl.Size = New-Object System.Drawing.Size(380, 20)
        $statusLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $checkboxPanel.Controls.Add($statusLbl)
        
        # Store label with app name as key to easily access it later
        $statusLabels[$app.name] = $statusLbl

        $yPos += 35
    }

    # Select All / Deselect All buttons
    $selectAllBtn = New-Object System.Windows.Forms.Button
    $selectAllBtn.Text = "Select All"
    $selectAllBtn.Location = New-Object System.Drawing.Point(20, 525)
    $selectAllBtn.Size = New-Object System.Drawing.Size(120, 32)
    $selectAllBtn.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $selectAllBtn.ForeColor = [System.Drawing.Color]::White
    $selectAllBtn.FlatStyle = "Flat"
    $selectAllBtn.Add_Click({
        foreach ($cb in $checkboxes) { $cb.Checked = $true }
    })
    $selectDlg.Controls.Add($selectAllBtn)

    $deselectAllBtn = New-Object System.Windows.Forms.Button
    $deselectAllBtn.Text = "Deselect All"
    $deselectAllBtn.Location = New-Object System.Drawing.Point(150, 525)
    $deselectAllBtn.Size = New-Object System.Drawing.Size(120, 32)
    $deselectAllBtn.BackColor = [System.Drawing.Color]::White
    $deselectAllBtn.FlatStyle = "Flat"
    $deselectAllBtn.Add_Click({
        foreach ($cb in $checkboxes) { $cb.Checked = $false }
    })
    $selectDlg.Controls.Add($deselectAllBtn)

    # Progress bar and status (initially hidden or zero)
    $dialogProgressBar = New-Object System.Windows.Forms.ProgressBar
    $dialogProgressBar.Location = New-Object System.Drawing.Point(20, 570)
    $dialogProgressBar.Size = New-Object System.Drawing.Size(350, 15)
    $dialogProgressBar.Visible = $false
    $selectDlg.Controls.Add($dialogProgressBar)

    $dialogStatus = New-Object System.Windows.Forms.Label
    $dialogStatus.Text = ""
    $dialogStatus.Location = New-Object System.Drawing.Point(20, 590)
    $dialogStatus.Size = New-Object System.Drawing.Size(450, 20)
    $dialogStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $dialogStatus.Visible = $false
    $selectDlg.Controls.Add($dialogStatus)

    # Cancel button
    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel"
    $cancelBtn.Location = New-Object System.Drawing.Point(490, 570)
    $cancelBtn.Size = New-Object System.Drawing.Size(110, 35)
    $cancelBtn.BackColor = [System.Drawing.Color]::White
    $cancelBtn.FlatStyle = "Flat"
    $cancelBtn.Add_Click({ $selectDlg.Close() })
    $selectDlg.Controls.Add($cancelBtn)

    # Install button
    $installBtn = New-Object System.Windows.Forms.Button
    $installBtn.Text = "Install Selected"
    $installBtn.Location = New-Object System.Drawing.Point(610, 570)
    $installBtn.Size = New-Object System.Drawing.Size(120, 35)
    $installBtn.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $installBtn.ForeColor = [System.Drawing.Color]::White
    $installBtn.FlatStyle = "Flat"
    $installBtn.Add_Click({
        $selectedApps = $checkboxes | Where-Object { $_.Checked -eq $true } | ForEach-Object { $_.Tag }
        
        if ($selectedApps.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one application.", "No Selection")
            return
        }

        # Disable controls to prevent clicking multiple times
        $installBtn.Enabled = $false
        $selectAllBtn.Visible = $false
        $deselectAllBtn.Visible = $false
        foreach ($cb in $checkboxes) { $cb.Enabled = $false }

        # Setup progress bar
        $totalApps = $selectedApps.Count
        $dialogProgressBar.Maximum = $totalApps
        $dialogProgressBar.Value = 0
        $dialogProgressBar.Visible = $true
        
        $dialogStatus.Visible = $true
        $dialogStatus.Text = "Starting installation..."
        
        # Pre-fill all selected labels with the waiting icon
        foreach ($app in $selectedApps) {
            $lbl = $statusLabels[$app.name]
            $lbl.Text = "⏳ Waiting in queue..."
            $lbl.ForeColor = [System.Drawing.Color]::Gray
        }

        foreach ($app in $selectedApps) {
            $lbl = $statusLabels[$app.name]
            $lbl.Text = "🔄 Installing..."
            $lbl.ForeColor = [System.Drawing.Color]::DarkOrange
            [System.Windows.Forms.Application]::DoEvents()

            $dialogProgressBar.Value++
            $dialogStatus.Text = "⏳ Installing ($($dialogProgressBar.Value)/$totalApps): $($app.name)..."
            [System.Windows.Forms.Application]::DoEvents()
            
            try {
                $res = Invoke-AppEntry -App $app -StatusLabel $lbl
            } catch {
                $lbl.Text = "$([char]0x2716) Error"
                $lbl.ForeColor = [System.Drawing.Color]::Red
            }
        }
        
        $dialogStatus.Text = "$([char]0x2714) Installation complete! ($totalApps applications)"
        # Reset cache so next check is accurate
        $script:InstalledCache = $null
        $installBtn.Enabled = $false
        $cancelBtn.Text = "Close"
        
        # Refresh master list dashboard indicators
        Apply-Filters
    })
    $selectDlg.Controls.Add($installBtn)

    $selectDlg.ShowDialog() | Out-Null
})

# ── Add Application Dialog ───────────────────────────────────
$addAppBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Add Application"
    $dlg.Size = New-Object System.Drawing.Size(480, 360)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"

    $lblName = New-Object System.Windows.Forms.Label; $lblName.Text = "Name:"; $lblName.Location = New-Object System.Drawing.Point(15, 15); $dlg.Controls.Add($lblName)
    $txtName = New-Object System.Windows.Forms.TextBox; $txtName.Location = New-Object System.Drawing.Point(120, 15); $txtName.Size = New-Object System.Drawing.Size(330, 22); $dlg.Controls.Add($txtName)

    $lblPath = New-Object System.Windows.Forms.Label; $lblPath.Text = "Path:"; $lblPath.Location = New-Object System.Drawing.Point(15, 50); $dlg.Controls.Add($lblPath)
    $txtPath = New-Object System.Windows.Forms.TextBox; $txtPath.Location = New-Object System.Drawing.Point(120, 50); $txtPath.Size = New-Object System.Drawing.Size(250, 22); $dlg.Controls.Add($txtPath)
    
    $btnBrowse = New-Object System.Windows.Forms.Button; $btnBrowse.Text = "Browse"; $btnBrowse.Location = New-Object System.Drawing.Point(378, 49); $dlg.Controls.Add($btnBrowse)
    $btnBrowse.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtPath.Text = $ofd.FileName }
    })

    $lblArgs = New-Object System.Windows.Forms.Label; $lblArgs.Text = "Args:"; $lblArgs.Location = New-Object System.Drawing.Point(15, 85); $dlg.Controls.Add($lblArgs)
    $txtArgs = New-Object System.Windows.Forms.TextBox; $txtArgs.Location = New-Object System.Drawing.Point(120, 85); $txtArgs.Size = New-Object System.Drawing.Size(330, 22); $dlg.Controls.Add($txtArgs)

    $lblWorkDir = New-Object System.Windows.Forms.Label; $lblWorkDir.Text = "Work Dir:"; $lblWorkDir.Location = New-Object System.Drawing.Point(15, 120); $dlg.Controls.Add($lblWorkDir)
    $txtWorkDir = New-Object System.Windows.Forms.TextBox; $txtWorkDir.Location = New-Object System.Drawing.Point(120, 120); $txtWorkDir.Size = New-Object System.Drawing.Size(330, 22); $dlg.Controls.Add($txtWorkDir)

    $lblCategory = New-Object System.Windows.Forms.Label; $lblCategory.Text = "Category:"; $lblCategory.Location = New-Object System.Drawing.Point(15, 155); $dlg.Controls.Add($lblCategory)
    $cmbCategory = New-Object System.Windows.Forms.ComboBox; $cmbCategory.Location = New-Object System.Drawing.Point(120, 155); $cmbCategory.Size = New-Object System.Drawing.Size(330, 22)
    $cmbCategory.Items.AddRange(@("Standard", "Mining", "Oil Processing", "IM", "Uninstallers"))
    $cmbCategory.SelectedIndex = 0; $dlg.Controls.Add($cmbCategory)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Location = New-Object System.Drawing.Point(280, 250)
    $btnSave.Size = New-Object System.Drawing.Size(85, 30)
    $btnSave.Add_Click({
        $newApp = @{
            name = $txtName.Text
            path = $txtPath.Text
            args = $txtArgs.Text
            workingDir = $txtWorkDir.Text
            category = $cmbCategory.SelectedItem.ToString()
            type = "exe"
        }
        $script:AllApps += $newApp
        Save-Apps -Apps $script:AllApps -JsonPath $AppsJsonPath
        Apply-Filters
        $dlg.Close()
    })
    $dlg.Controls.Add($btnSave)
    $dlg.ShowDialog()
})

# ── Initialization ───────────────────────────────────────────
Apply-Filters
$form.Add_Shown({
    if (-not $wifiStatus.IsDebs) {
        Show-CorporateWifiWarning -Owner $form -WifiStatus $wifiStatus -LogoPath $LogoPath
    }
})
$form.ShowDialog() | Out-Null