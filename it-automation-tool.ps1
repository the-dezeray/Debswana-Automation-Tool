Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Resolve paths ────────────────────────────────────────────
if (-not $ToolDir) { $ToolDir = (Get-Location).Path }
$AppsJsonPath = Join-Path $ToolDir "apps.json"

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
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if ($completed) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job -Force
        return $result
    } else {
        Remove-Job -Job $job -Force
        return $false
    }
}

# ── Install Helper (Responsive) ────────────────────────────────
function Run {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Args = "",
        [string]$WorkingDir = "",
        [System.Windows.Forms.Label]$StatusLabel
    )

    $StatusLabel.Text = "🔍 Checking network path for $Name..."
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    [System.Windows.Forms.Application]::DoEvents()

    $pathExists = Test-PathWithTimeout -Path $Path -TimeoutSeconds 5
    if (-not $pathExists) {
        $StatusLabel.Text = "❌ Cannot access: $Path"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        return
    }

    $StatusLabel.Text = "🚀 Launching installer: $Name ..."
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $params = @{ FilePath = $Path; PassThru = $true }
        if ($Args) { $params.ArgumentList = $Args }
        if ($WorkingDir) { $params.WorkingDirectory = $WorkingDir }

        $proc = Start-Process @params
        while (-not $proc.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
        }

        $StatusLabel.Text = "✅ $Name — Installation completed."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Green
    } catch {
        $StatusLabel.Text = "❌ Error installing: $Name"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
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

    if ($App.type -eq "copy-then-run") {
        $StatusLabel.Text = "🔍 Checking source path for $($App.name)..."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        [System.Windows.Forms.Application]::DoEvents()

        if (-not (Test-PathWithTimeout -Path $App.path -TimeoutSeconds 5)) {
            $StatusLabel.Text = "❌ Cannot access source path"
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            return
        }

        $StatusLabel.Text = "📦 Copying installation files for $($App.name)..."
        try {
            Copy-WithWindowsDialog $App.path $App.destDir
            $exePath = Join-Path $App.destDir $App.exeName
            if (-not (Test-PathWithTimeout -Path $exePath -TimeoutSeconds 3)) {
                $StatusLabel.Text = "❌ Installation aborted - Files not copied"
                $StatusLabel.ForeColor = [System.Drawing.Color]::Red
                return
            }

            $StatusLabel.Text = "🚀 Files verified. Launching installer..."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Green
            [System.Windows.Forms.Application]::DoEvents()
            Run -Path $exePath -Name $App.name -Args $App.args -WorkingDir $App.destDir -StatusLabel $StatusLabel
        } catch {
            $StatusLabel.Text = "❌ Error processing $($App.name) files."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        }
    } else {
        Run -Path $App.path -Name $App.name -Args $App.args -WorkingDir $App.workingDir -StatusLabel $StatusLabel
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

# ── Header ───────────────────────────────────────────────────
$header = New-Object System.Windows.Forms.Panel
$header.Size = New-Object System.Drawing.Size(1000, 60)
$header.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$form.Controls.Add($header)

$headerTitle = New-Object System.Windows.Forms.Label
$headerTitle.Text = "   Desiree Software Center"
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
    $connStatus.Text = "🟢 DEBS WiFi Connected"
    $connStatus.ForeColor = [System.Drawing.Color]::LightGreen
} else {
    $connStatus.Text = "🔴 Not Connected"
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
$credits = New-Object System.Windows.Forms.Label
$credits.Text = "Built by Desiree Chingwaru, Odirile Mathepeo & Simoen Uden"
$credits.Location = New-Object System.Drawing.Point(10, 580)
$credits.Size = New-Object System.Drawing.Size(180, 50)
$credits.ForeColor = [System.Drawing.Color]::Gray
$credits.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$sidebar.Controls.Add($credits)

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
$status.Text = "✅ Ready."
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

        # Single Action Button (Click to Install, Right-Click for Options)
        $btnAction = New-Object System.Windows.Forms.Button
        $btnAction.Text = "Install"
        $btnAction.Location = New-Object System.Drawing.Point(250, 22)
        $btnAction.Size = New-Object System.Drawing.Size(80, 30)
        $btnAction.Tag = $app
        $btnAction.Cursor = "Hand"
        $btnAction.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
        $btnAction.ForeColor = [System.Drawing.Color]::White
        $btnAction.FlatStyle = "Flat"
        
        # Left Click - Install
        $btnAction.Add_Click({
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Invoke-AppEntry -App $this.Tag -StatusLabel $status
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
    if ($standardApps.Count -eq 0) { return }

    $totalApps = $standardApps.Count
    $progressBar.Maximum = $totalApps
    $progressBar.Value = 0

    $installAllBtn.Enabled = $false
    foreach ($app in $standardApps) {
        $progressBar.Value++
        $status.Text = "⏳ Installing ($($progressBar.Value)/$totalApps): $($app.name)..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            Invoke-AppEntry -App $app -StatusLabel $status
        } catch {}
    }
    $status.Text = "✅ Installation complete! ($totalApps applications)"
    $installAllBtn.Enabled = $true
    $progressBar.Value = 0
})

# ── Add Application Dialog ───────────────────────────────────
$addAppBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Add Application"
    $dlg.Size = New-Object System.Drawing.Size(480, 360)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"

    # (Dialog labels/inputs generation omitted for brevity but mirror your exact UI sizes)
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
$form.ShowDialog()