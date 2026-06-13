Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Resolve paths (ToolDir is passed in from the launcher) ───
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
    # 4 = Respond with "Yes to All" for overwrites
    $folder.CopyHere($SourcePath, 4)
}

# ── Network Path Helper with Timeout ────────────────────────
function Test-PathWithTimeout {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 5
    )

    $job = Start-Job -ScriptBlock {
        param($p)
        Test-Path $p
    } -ArgumentList $Path

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

    # Check if path exists with timeout to prevent hanging on network issues
    $StatusLabel.Text = "Checking path for $Name..."
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    [System.Windows.Forms.Application]::DoEvents()

    $pathExists = Test-PathWithTimeout -Path $Path -TimeoutSeconds 5
    
    if (-not $pathExists) {
        $StatusLabel.Text = "Cannot access: $Path (network timeout or not found)"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        [System.Windows.Forms.MessageBox]::Show(
            "Cannot access the application path:`n`n$Path`n`nThis may be due to:`n• Network connection issues`n• Path doesn't exist`n• No access to network share`n`nPlease check your network connection and try again.",
            "Path Access Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    $StatusLabel.Text = "Running: $Name ..."
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

        $StatusLabel.Text = "$Name — Installation Complete."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Green
    } catch {
        $StatusLabel.Text = "Error installing: $Name"
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
    }
}

# ── Check WiFi Connection ───────────────────────────────────
function Test-DebsWiFi {
    try {
        $networks = netsh wlan show interfaces
        if ($networks -match "SSID\s+:\s+(.+)") {
            $currentSSID = $matches[1].Trim()
            return @{
                Connected = $true
                SSID = $currentSSID
                IsDebs = $currentSSID -like "*debs*"
            }
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
    
    if ($App.type -eq "copy-then-run" -and $App.destDir) {
        $pathToOpen = $App.destDir
    } elseif ($App.path) {
        # For network paths or exe paths, open the containing folder
        $pathToOpen = Split-Path $App.path -Parent
    }
    
    if ($pathToOpen) {
        # Check path accessibility with timeout
        $accessible = Test-PathWithTimeout -Path $pathToOpen -TimeoutSeconds 3
        
        if ($accessible) {
            Start-Process "explorer.exe" -ArgumentList $pathToOpen
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Cannot access path:`n$pathToOpen`n`nThis may be due to network connection issues or the path no longer exists.",
                "Path Access Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "No valid path available for this application.",
            "No Path",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
}

# ── Run an app entry from apps.json (handles plain exe / copy-then-run) ──
function Invoke-AppEntry {
    param(
        [psobject]$App,
        [System.Windows.Forms.Label]$StatusLabel
    )

    if ($App.type -eq "copy-then-run") {
        # Check source path accessibility first
        $StatusLabel.Text = "Checking source path for $($App.name)..."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        [System.Windows.Forms.Application]::DoEvents()

        $sourceAccessible = Test-PathWithTimeout -Path $App.path -TimeoutSeconds 5
        
        if (-not $sourceAccessible) {
            $StatusLabel.Text = "Cannot access source path (network timeout or not found)"
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.MessageBox]::Show(
                "Cannot access the source path:`n`n$($App.path)`n`nThis may be due to:`n• Network connection issues`n• Path doesn't exist`n• No access to network share`n`nPlease check your network connection and try again.",
                "Source Path Access Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        $StatusLabel.Text = "Opening Windows Copy Dialog for $($App.name)..."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange

        try {
            Copy-WithWindowsDialog $App.path $App.destDir

            [System.Windows.Forms.MessageBox]::Show(
                "The Windows Copy window has opened.`n`nPlease wait for the copy to finish, then click OK here to verify the files.",
                "Copying Files",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            # Verify files were copied
            $StatusLabel.Text = "Verifying copied files..."
            $StatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
            [System.Windows.Forms.Application]::DoEvents()

            $exePath = Join-Path $App.destDir $App.exeName
            $fileExists = Test-PathWithTimeout -Path $exePath -TimeoutSeconds 3
            
            if (-not $fileExists) {
                $verifyResult = [System.Windows.Forms.MessageBox]::Show(
                    "ERROR: The installer file was not found at:`n$exePath`n`nThe copy operation may have failed or is incomplete.`n`nWould you like to open the destination folder to check manually?",
                    "Files Not Found",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                
                if ($verifyResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Open-AppPath -App $App
                }

                $StatusLabel.Text = "Installation aborted - Files not copied successfully"
                $StatusLabel.ForeColor = [System.Drawing.Color]::Red
                return
            }

            # Files verified, proceed with installation
            $StatusLabel.Text = "Files verified. Starting installation..."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Green
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 500

            Run -Path $exePath -Name $App.name -Args $App.args -WorkingDir $App.destDir -StatusLabel $StatusLabel
        } catch {
            $StatusLabel.Text = "Error processing $($App.name) files."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Red
            
            $openFolderResult = [System.Windows.Forms.MessageBox]::Show(
                "An error occurred during the process.`n`nWould you like to open the destination folder to check manually?",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            
            if ($openFolderResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Open-AppPath -App $App
            }
            
            throw $_
        }
    } else {
        Run -Path $App.path -Name $App.name -Args $App.args -WorkingDir $App.workingDir -StatusLabel $StatusLabel
    }
}

# ── Load apps from JSON ─────────────────────────────────────
function Get-Apps {
    param([string]$JsonPath)

    if (-not (Test-Path $JsonPath)) {
        return @()
    }

    $raw = Get-Content -Path $JsonPath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    try {
        $apps = $raw | ConvertFrom-Json
        if ($null -eq $apps) { return @() }
        return @($apps)
    } catch {
        return @()
    }
}

# ── Save apps back to JSON ──────────────────────────────────
function Save-Apps {
    param([array]$Apps, [string]$JsonPath)

    $json = $Apps | ConvertTo-Json -Depth 5

    if ($Apps.Count -eq 1 -and -not $json.TrimStart().StartsWith("[")) {
        $json = "[`n$json`n]"
    }

    Set-Content -Path $JsonPath -Value $json -Encoding UTF8
}

# ── Check WiFi at startup ────────────────────────────────────
$wifiStatus = Test-DebsWiFi
if (-not $wifiStatus.IsDebs) {
    $wifiMessage = if ($wifiStatus.Connected) {
        "You are connected to: $($wifiStatus.SSID)`n`nThis does not appear to be the Debs WiFi network.`n`nAccessing network shares may fail or be very slow."
    } else {
        "No WiFi connection detected.`n`nAccessing network shares may fail."
    }
    
    [System.Windows.Forms.MessageBox]::Show(
        "$wifiMessage`n`nPlease connect to the Debs WiFi network for best results.",
        "WiFi Connection Warning",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

# ── Main window ──────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "Desiree Magical Wand"
$form.Size = New-Object System.Drawing.Size(700, 560)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::White
$form.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Header
$header = New-Object System.Windows.Forms.Label
$header.Text = "  Desiree's Magical Wand"
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(700, 50)
$header.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$header.ForeColor = [System.Drawing.Color]::FromArgb(30, 70, 180)
$header.BackColor = [System.Drawing.Color]::FromArgb(230, 238, 255)
$header.TextAlign = "MiddleLeft"
$form.Controls.Add($header)

# ── Search box ─────────────────────────────────────────────────
$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = "Search:"
$searchLabel.Location = New-Object System.Drawing.Point(15, 60)
$searchLabel.Size = New-Object System.Drawing.Size(55, 24)
$searchLabel.TextAlign = "MiddleLeft"
$form.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(75, 58)
$searchBox.Size = New-Object System.Drawing.Size(360, 24)
$searchBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($searchBox)

# "Install All" button
$installAllBtn = New-Object System.Windows.Forms.Button
$installAllBtn.Text = "⚡ Install All"
$installAllBtn.Location = New-Object System.Drawing.Point(445, 56)
$installAllBtn.Size = New-Object System.Drawing.Size(115, 28)
$installAllBtn.FlatStyle = "Flat"
$installAllBtn.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 180)
$installAllBtn.ForeColor = [System.Drawing.Color]::FromArgb(80, 40, 10)
$installAllBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$installAllBtn.Cursor = "Hand"
$form.Controls.Add($installAllBtn)

# "Add Application" button (top-right, always visible)
$addAppBtn = New-Object System.Windows.Forms.Button
$addAppBtn.Text = "+ Add App"
$addAppBtn.Location = New-Object System.Drawing.Point(570, 56)
$addAppBtn.Size = New-Object System.Drawing.Size(110, 28)
$addAppBtn.FlatStyle = "Flat"
$addAppBtn.BackColor = [System.Drawing.Color]::FromArgb(220, 235, 220)
$addAppBtn.ForeColor = [System.Drawing.Color]::FromArgb(25, 80, 35)
$addAppBtn.Cursor = "Hand"
$form.Controls.Add($addAppBtn)

# ── Category filter buttons ─────────────────────────────────────
$categoryPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$categoryPanel.Location = New-Object System.Drawing.Point(15, 92)
$categoryPanel.Size = New-Object System.Drawing.Size(670, 40)
$categoryPanel.WrapContents = $true
$form.Controls.Add($categoryPanel)

$script:SelectedCategory = "All"

$categories = @("All", "Standard", "Mining", "Oil Processing", "IM", "Uninstallers")
foreach ($cat in $categories) {
    $catBtn = New-Object System.Windows.Forms.Button
    $catBtn.Text = $cat
    $catBtn.Size = New-Object System.Drawing.Size(105, 30)
    $catBtn.FlatStyle = "Flat"
    $catBtn.Margin = New-Object System.Windows.Forms.Padding(2)
    $catBtn.Cursor = "Hand"
    $catBtn.Tag = $cat
    
    if ($cat -eq "All") {
        $catBtn.BackColor = [System.Drawing.Color]::FromArgb(100, 150, 230)
        $catBtn.ForeColor = [System.Drawing.Color]::White
        $catBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    } else {
        $catBtn.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
        $catBtn.ForeColor = [System.Drawing.Color]::FromArgb(50, 70, 100)
        $catBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    }
    
    $catBtn.Add_Click({
        $script:SelectedCategory = $this.Tag
        
        # Update button styles
        foreach ($btn in $categoryPanel.Controls) {
            if ($btn.Tag -eq $script:SelectedCategory) {
                $btn.BackColor = [System.Drawing.Color]::FromArgb(100, 150, 230)
                $btn.ForeColor = [System.Drawing.Color]::White
                $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
            } else {
                $btn.BackColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
                $btn.ForeColor = [System.Drawing.Color]::FromArgb(50, 70, 100)
                $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            }
        }
        
        # Filter and render apps
        $filtered = if ($script:SelectedCategory -eq "All") {
            $script:AllApps
        } else {
            $script:AllApps | Where-Object { $_.category -eq $script:SelectedCategory }
        }
        
        # Apply search filter if exists
        $searchTerm = $searchBox.Text.Trim()
        if (-not [string]::IsNullOrEmpty($searchTerm)) {
            $filtered = $filtered | Where-Object {
                $_.name -like "*$searchTerm*" -or $_.category -like "*$searchTerm*"
            }
        }
        
        Render-AppButtons -Apps $filtered
    })
    
    $categoryPanel.Controls.Add($catBtn)
}

# ── Scrollable panel that holds the app buttons ────────────────
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(0, 140)
$buttonPanel.Size = New-Object System.Drawing.Size(700, 335)
$buttonPanel.AutoScroll = $true
$form.Controls.Add($buttonPanel)

# Status label
$status = New-Object System.Windows.Forms.Label
$status.Text = "Ready. Click an application to install it."
$status.Location = New-Object System.Drawing.Point(0, 480)
$status.Size = New-Object System.Drawing.Size(700, 26)
$status.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 255)
$status.ForeColor = [System.Drawing.Color]::FromArgb(80, 110, 180)
$status.TextAlign = "MiddleCenter"
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($status)

# Credits label
$credits = New-Object System.Windows.Forms.Label
$credits.Text = "Built by Desiree Chingwaru and Odirile Mathepeo"
$credits.Location = New-Object System.Drawing.Point(0, 510)
$credits.Size = New-Object System.Drawing.Size(700, 22)
$credits.BackColor = [System.Drawing.Color]::White
$credits.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 150)
$credits.TextAlign = "MiddleCenter"
$credits.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$form.Controls.Add($credits)

# ── State ────────────────────────────────────────────────────
$script:AllApps = Get-Apps -JsonPath $AppsJsonPath

# ── Render buttons for a given app list ────────────────────────
function Render-AppButtons {
    param([array]$Apps)

    $buttonPanel.Controls.Clear()
    $index = 0

    foreach ($app in $Apps) {
        $col = $index % 2
        $row = [Math]::Floor($index / 2)

        $x = if ($col -eq 0) { 15 } else { 355 }
        $y = 10 + ($row * 42)

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $app.name
        $btn.Tag = $app
        $btn.Location = New-Object System.Drawing.Point($x, $y)
        $btn.Size = New-Object System.Drawing.Size(325, 36)
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 215, 245)
        $btn.FlatAppearance.BorderSize = 1
        $btn.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 255)
        $btn.ForeColor = [System.Drawing.Color]::FromArgb(25, 35, 80)
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $btn.TextAlign = "MiddleLeft"
        $btn.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
        $btn.Cursor = "Hand"

        # Left-click to install
        $btn.Add_Click({
            $clickedApp = $this.Tag
            $this.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
            $this.Enabled = $false
            $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

            try {
                Invoke-AppEntry -App $clickedApp -StatusLabel $status
                $this.BackColor = [System.Drawing.Color]::LightGreen
            } catch {
                $this.BackColor = [System.Drawing.Color]::LightCoral
            } finally {
                $form.Cursor = [System.Windows.Forms.Cursors]::Default
                $this.Enabled = $true
            }
        })

        # Right-click context menu
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        $openPathItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $openPathItem.Text = "Open Path in Explorer"
        $openPathItem.Tag = $app
        $openPathItem.Add_Click({
            Open-AppPath -App $this.Tag
        })
        
        $contextMenu.Items.Add($openPathItem)
        $btn.ContextMenuStrip = $contextMenu

        $buttonPanel.Controls.Add($btn)
        $index++
    }

    if ($Apps.Count -eq 0) {
        $noResults = New-Object System.Windows.Forms.Label
        $noResults.Text = "No applications match your search."
        $noResults.Location = New-Object System.Drawing.Point(15, 15)
        $noResults.Size = New-Object System.Drawing.Size(650, 30)
        $noResults.ForeColor = [System.Drawing.Color]::Gray
        $buttonPanel.Controls.Add($noResults)
    }
}

# ── Search filter ────────────────────────────────────────────
$searchBox.Add_TextChanged({
    $term = $searchBox.Text.Trim()
    
    $filtered = if ($script:SelectedCategory -eq "All") {
        $script:AllApps
    } else {
        $script:AllApps | Where-Object { $_.category -eq $script:SelectedCategory }
    }
    
    if (-not [string]::IsNullOrEmpty($term)) {
        $filtered = $filtered | Where-Object {
            $_.name -like "*$term*" -or $_.category -like "*$term*"
        }
    }
    
    Render-AppButtons -Apps $filtered
})

# ── Install All handler ─────────────────────────────────────────
$installAllBtn.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will install all standard software applications.`n`nThis process may take a significant amount of time.`n`nDo you want to continue?",
        "Install All Standard Software",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        $standardApps = $script:AllApps | Where-Object { $_.standard -eq $true }
        
        if ($standardApps.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No standard applications found to install.",
                "No Apps",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }
        
        $installAllBtn.Enabled = $false
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        
        $totalApps = $standardApps.Count
        $currentApp = 0
        
        foreach ($app in $standardApps) {
            $currentApp++
            $status.Text = "Installing ($currentApp/$totalApps): $($app.name)..."
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
            [System.Windows.Forms.Application]::DoEvents()
            
            try {
                Invoke-AppEntry -App $app -StatusLabel $status
                Start-Sleep -Milliseconds 500
            } catch {
                $status.Text = "Error installing $($app.name) - continuing..."
                $status.ForeColor = [System.Drawing.Color]::Red
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 1000
            }
        }
        
        $status.Text = "Installation complete! Installed $totalApps applications."
        $status.ForeColor = [System.Drawing.Color]::Green
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $installAllBtn.Enabled = $true
        
        [System.Windows.Forms.MessageBox]::Show(
            "All standard software installation completed!`n`nInstalled $totalApps applications.",
            "Installation Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
})

# ── Add Application dialog ──────────────────────────────────────
$addAppBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Add Application"
    $dlg.Size = New-Object System.Drawing.Size(480, 360)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $y = 15
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Name:"
    $lblName.Location = New-Object System.Drawing.Point(15, $y)
    $lblName.Size = New-Object System.Drawing.Size(100, 22)
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(120, $y)
    $txtName.Size = New-Object System.Drawing.Size(330, 22)
    $dlg.Controls.Add($txtName)

    $y += 35
    $lblPath = New-Object System.Windows.Forms.Label
    $lblPath.Text = "Path / UNC:"
    $lblPath.Location = New-Object System.Drawing.Point(15, $y)
    $lblPath.Size = New-Object System.Drawing.Size(100, 22)
    $dlg.Controls.Add($lblPath)

    $txtPath = New-Object System.Windows.Forms.TextBox
    $txtPath.Location = New-Object System.Drawing.Point(120, $y)
    $txtPath.Size = New-Object System.Drawing.Size(250, 22)
    $dlg.Controls.Add($txtPath)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "Browse..."
    $btnBrowse.Location = New-Object System.Drawing.Point(378, ($y - 1))
    $btnBrowse.Size = New-Object System.Drawing.Size(72, 24)
    $dlg.Controls.Add($btnBrowse)

    $btnBrowse.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Executables/Installers (*.exe;*.msi)|*.exe;*.msi|All files (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtPath.Text = $ofd.FileName
        }
    })

    $y += 35
    $lblArgs = New-Object System.Windows.Forms.Label
    $lblArgs.Text = "Arguments:"
    $lblArgs.Location = New-Object System.Drawing.Point(15, $y)
    $lblArgs.Size = New-Object System.Drawing.Size(100, 22)
    $dlg.Controls.Add($lblArgs)

    $txtArgs = New-Object System.Windows.Forms.TextBox
    $txtArgs.Location = New-Object System.Drawing.Point(120, $y)
    $txtArgs.Size = New-Object System.Drawing.Size(330, 22)
    $dlg.Controls.Add($txtArgs)

    $y += 35
    $lblWorkDir = New-Object System.Windows.Forms.Label
    $lblWorkDir.Text = "Working Dir:"
    $lblWorkDir.Location = New-Object System.Drawing.Point(15, $y)
    $lblWorkDir.Size = New-Object System.Drawing.Size(100, 22)
    $dlg.Controls.Add($lblWorkDir)

    $txtWorkDir = New-Object System.Windows.Forms.TextBox
    $txtWorkDir.Location = New-Object System.Drawing.Point(120, $y)
    $txtWorkDir.Size = New-Object System.Drawing.Size(330, 22)
    $dlg.Controls.Add($txtWorkDir)

    $y += 35
    $lblCategory = New-Object System.Windows.Forms.Label
    $lblCategory.Text = "Category:"
    $lblCategory.Location = New-Object System.Drawing.Point(15, $y)
    $lblCategory.Size = New-Object System.Drawing.Size(100, 22)
    $dlg.Controls.Add($lblCategory)

    $cmbCategory = New-Object System.Windows.Forms.ComboBox
    $cmbCategory.Location = New-Object System.Drawing.Point(120, $y)
    $cmbCategory.Size = New-Object System.Drawing.Size(330, 22)
    $cmbCategory.DropDownStyle = "DropDownList"
    $cmbCategory.Items.AddRange(@("Standard", "Mining", "Oil Processing", "IM", "Uninstallers"))
    $cmbCategory.SelectedIndex = 0
    $dlg.Controls.Add($cmbCategory)

    $y += 45
    $info = New-Object System.Windows.Forms.Label
    $info.Text = "Tip: for apps that need a 'copy first then run setup.exe'`nworkflow, edit apps.json directly and set 'type' to`n'copy-then-run' with 'destDir' and 'exeName'."
    $info.Location = New-Object System.Drawing.Point(15, $y)
    $info.Size = New-Object System.Drawing.Size(440, 55)
    $info.ForeColor = [System.Drawing.Color]::Gray
    $info.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $dlg.Controls.Add($info)

    $y += 65
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Location = New-Object System.Drawing.Point(280, $y)
    $btnSave.Size = New-Object System.Drawing.Size(85, 30)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(220, 235, 220)
    $dlg.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(375, $y)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 30)
    $dlg.Controls.Add($btnCancel)

    $btnCancel.Add_Click({ $dlg.Close() })

    $btnSave.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtName.Text) -or [string]::IsNullOrWhiteSpace($txtPath.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Name and Path are required.", "Missing Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $newApp = [PSCustomObject]@{
            name       = $txtName.Text.Trim()
            path       = $txtPath.Text.Trim()
            args       = $txtArgs.Text.Trim()
            workingDir = $txtWorkDir.Text.Trim()
            category   = $cmbCategory.SelectedItem.ToString()
            type       = "exe"
            standard   = $false
        }

        $script:AllApps = @($script:AllApps) + $newApp
        Save-Apps -Apps $script:AllApps -JsonPath $AppsJsonPath

        $searchBox.Text = ""
        $script:SelectedCategory = "All"
        Render-AppButtons -Apps $script:AllApps

        $status.Text = "Added: $($newApp.name)"
        $status.ForeColor = [System.Drawing.Color]::Green

        $dlg.Close()
    })

    $dlg.ShowDialog()
})

# ── Initial render ───────────────────────────────────────────
Render-AppButtons -Apps $script:AllApps

[System.Windows.Forms.Application]::Run($form)
