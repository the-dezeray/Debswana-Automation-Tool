Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ── Resolve paths ────────────────────────────────────────────
if (-not $ToolDir) { $ToolDir = (Get-Location).Path }
$AppsJsonPath = Join-Path $ToolDir "apps.json"
$LogoPath = Join-Path $ToolDir "image.png"

# ── Synchronized State ───────────────────────────────────────
$sync = [hashtable]::Synchronized(@{})
$sync.ToolDir = $ToolDir
$sync.AppsJsonPath = $AppsJsonPath
$sync.LogoPath = $LogoPath
$sync.SelectedCategory = "All"
$sync.SearchTerm = ""
$sync.InstalledCache = $null # List of registry apps
$sync.AppStatusMap = [hashtable]::Synchronized(@{}) # Map of Name -> IsInstalled
$sync.WifiStatus = $null

# ── Runspace Pool Setup ─────────────────────────────────────
$RunspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$RunspacePool.Open()

function Invoke-BackgroundWork {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$ArgumentList = @{}
    )
    $ps = [powershell]::Create().AddScript($ScriptBlock).AddParameters($ArgumentList)
    $ps.RunspacePool = $RunspacePool
    return @{
        PowerShell = $ps
        Handle = $ps.BeginInvoke()
    }
}

# ── Background Worker Tasks ──────────────────────────────────

$RefreshRegistryTask = {
    param($sync)

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
    
    # 1. Scan Registry (Fast)
    $registryPaths = @(
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" },
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
    )
    $registryApps = New-Object System.Collections.Generic.List[psobject]
    foreach ($registryPath in $registryPaths) {
        $regKey = $registryPath.Hive.OpenSubKey($registryPath.Path)
        if ($regKey) {
            foreach ($subKeyName in $regKey.GetSubKeyNames()) {
                $subKey = $regKey.OpenSubKey($subKeyName)
                if ($subKey) {
                    $displayName = $subKey.GetValue("DisplayName")
                    if ($displayName) {
                        $registryApps.Add([PSCustomObject]@{ DisplayName = $displayName })
                    }
                    $subKey.Close()
                }
            }
            $regKey.Close()
        }
    }
    $sync.InstalledCache = $registryApps

    $startApps = @()
    try {
        $startApps = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { $_.Name } | ForEach-Object {
            [PSCustomObject]@{ DisplayName = $_.Name }
        }
    } catch {
        $startApps = @()
    }

    # Get services in bulk like Python does (more efficient)
    $installedServices = @{}
    $serviceNames = @()
    foreach ($app in $sync.AllApps) {
        if ($app.checkType -eq "Service" -and $app.checkService) {
            $serviceNames += $app.checkService.Trim()
        }
    }
    
    if ($serviceNames.Count -gt 0) {
        $uniqueServices = $serviceNames | Sort-Object -Unique
        try {
            $installedServicesRaw = Get-Service -Name $uniqueServices -ErrorAction SilentlyContinue
            foreach ($service in $installedServicesRaw) {
                $installedServices[$service.Name.ToLower()] = $true
            }
        } catch {
            # Ignore service check errors
        }
    }

    # 2. Update Status Map for all apps (Matches Python logic exactly)
    foreach ($app in $sync.AllApps) {
        $isInstalled = $false
        $name = $app.name
        $checkType = $app.checkType
        $checkMatch = $app.checkMatch
        $checkPath = $app.checkPath
        $checkService = $app.checkService
        
        try {
            # 1. Primary Check based on checkType (matches Python)
            if ($checkType -eq "Registry" -and $checkMatch) {
                $isInstalled = Test-NameContains -Items $registryApps -Needle $checkMatch
            }
            elseif ($checkType -eq "File" -and $checkPath) {
                if ([System.IO.File]::Exists($checkPath)) {
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
                $isInstalled = Test-NameContains -Items $registryApps -Needle $name
            }

            # 3. Final Fallback: Check cached Start Menu apps (Windows 10+) (matches Python)
            if (-not $isInstalled) {
                $isInstalled = Test-NameContains -Items $startApps -Needle $name
            }

            # 4. Additional fallback: Check checkMatch in startApps too
            if (-not $isInstalled -and $checkMatch) {
                $isInstalled = Test-NameContains -Items $startApps -Needle $checkMatch
            }
        } catch {
            # If any error occurs, assume not installed
            $isInstalled = $false
        }
        
        $sync.AppStatusMap[$name] = $isInstalled
    }

    # 3. Trigger UI update
    $sync.Window.Dispatcher.Invoke({
        $statusText = $sync.Window.FindName("StatusText")
        $installedCount = ($sync.AppStatusMap.Values | Where-Object { $_ -eq $true }).Count
        $totalCount = $sync.AppStatusMap.Count
        $statusText.Text = "Status refreshed. Found $($registryApps.Count) registry apps, $($startApps.Count) start apps. $installedCount/$totalCount apps detected."
        
        # Trigger UI refresh
        $sb = $sync.Window.FindName("SearchBox")
        $temp = $sb.Text
        $sb.Text = $temp + " "
        $sb.Text = $temp
    })
}

$CheckWifiTask = {
    param($sync)
    try {
        $networks = netsh wlan show interfaces
        if ($networks -match "SSID\s+:\s+(.+)") {
            $currentSSID = $matches[1].Trim()
            $isDebs = $currentSSID -like "*debs*"
            $sync.WifiStatus = @{ Connected = $true; SSID = $currentSSID; IsDebs = $isDebs }
            
            $sync.Window.Dispatcher.Invoke({
                $connStatus = $sync.Window.FindName("ConnStatus")
                if ($isDebs) {
                    $connStatus.Text = "● DEBS WiFi Connected"
                    $connStatus.Foreground = "LightGreen"
                } else {
                    $connStatus.Text = "● Not Connected"
                    $connStatus.Foreground = "LightCoral"
                    # Show warning here directly since we are on the UI thread
                    # Show-WifiWarning (Can't call global function directly, but we can do it via Window events)
                }
            })
        }
    } catch {}
}

$InstallAppTask = {
    param($sync, $App)
    
    function Update-Status {
        param($Msg, $Color = "Black", $Progress = -1)
        $sync.Window.Dispatcher.Invoke({
            $statusText = $sync.Window.FindName("StatusText")
            $mainProgress = $sync.Window.FindName("MainProgress")
            $statusText.Text = $Msg
            $statusText.Foreground = $Color
            if ($Progress -ge 0) { $mainProgress.Value = $Progress }
        })
    }

    try {
        $Name = $App.name
        $Path = $App.path
        $Args = $App.args
        $WorkingDir = $App.workingDir
        
        Update-Status -Msg "Checking path for $Name..." -Color "DarkOrange" -Progress 10
        
        if (-not [System.IO.File]::Exists($Path) -and -not [System.IO.Directory]::Exists($Path)) {
             Update-Status -Msg "Cannot access: $Path" -Color "Red" -Progress 0
             return $false
        }

        if ($App.type -eq "copy-then-run") {
            Update-Status -Msg "Copying installation files for $Name..." -Color "DarkOrange" -Progress 30
            $DestDir = $App.destDir
            if (-not [System.IO.Directory]::Exists($DestDir)) {
                [System.IO.Directory]::CreateDirectory($DestDir) | Out-Null
            }
            robocopy $Path $DestDir /E /R:1 /W:1 /NJH /NJS /NDL /NC /NS /NP | Out-Null
            $exePath = Join-Path $DestDir $App.exeName
            if (-not [System.IO.File]::Exists($exePath)) {
                Update-Status -Msg "Files not copied correctly." -Color "Red" -Progress 0
                return $false
            }
            $Path = $exePath
            $WorkingDir = $DestDir
        }

        Update-Status -Msg "Launching installer: $Name..." -Color "DarkOrange" -Progress 60
        $si = New-Object System.Diagnostics.ProcessStartInfo
        $si.FileName = $Path
        if ($Args) { $si.Arguments = $Args }
        if ($WorkingDir) { $si.WorkingDirectory = $WorkingDir }
        if ($App.runAsAdmin) { $si.Verb = "runas" }
        $proc = [System.Diagnostics.Process]::Start($si)
        $proc.WaitForExit()
        
        Update-Status -Msg "Installation completed: $Name" -Color "Green" -Progress 100
        
        # Trigger refresh
        $sync.Window.Dispatcher.Invoke({
            Invoke-BackgroundWork -ScriptBlock $RefreshRegistryTask -ArgumentList @{ sync = $sync }
        })
        return $true
    } catch {
        Update-Status -Msg "Error: $($_.Exception.Message)" -Color "Red" -Progress 0
        return $false
    }
}

$BulkInstallTask = {
    param($sync, $Apps)
    
    function Update-Status {
        param($Msg, $Color = "Black", $Progress = -1)
        $sync.Window.Dispatcher.Invoke({
            $statusText = $sync.Window.FindName("StatusText")
            $mainProgress = $sync.Window.FindName("MainProgress")
            $statusText.Text = $Msg
            $statusText.Foreground = $Color
            if ($Progress -ge 0) { $mainProgress.Value = $Progress }
        })
    }

    $Total = $Apps.Count
    $Current = 0
    $Failures = New-Object System.Collections.Generic.List[psobject]

    foreach ($App in $Apps) {
        $Current++
        $ProgressBase = [int](($Current - 1) / $Total * 100)
        Update-Status -Msg "Installing ($Current/$Total): $($App.name)..." -Color "DarkOrange" -Progress $ProgressBase
        
        try {
            $Path = $App.path
            $Args = $App.args
            $WorkingDir = $App.workingDir
            
            if ($App.type -eq "copy-then-run") {
                $DestDir = $App.destDir
                if (-not [System.IO.Directory]::Exists($DestDir)) { [System.IO.Directory]::CreateDirectory($DestDir) | Out-Null }
                robocopy $Path $DestDir /E /R:1 /W:1 /NJH /NJS /NDL /NC /NS /NP | Out-Null
                $Path = Join-Path $DestDir $App.exeName
                $WorkingDir = $DestDir
            }

            if ([System.IO.File]::Exists($Path)) {
                $si = New-Object System.Diagnostics.ProcessStartInfo
                $si.FileName = $Path
                if ($Args) { $si.Arguments = $Args }
                if ($WorkingDir) { $si.WorkingDirectory = $WorkingDir }
                if ($App.runAsAdmin) { $si.Verb = "runas" }
                $proc = [System.Diagnostics.Process]::Start($si)
                $proc.WaitForExit()
                
                if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) { # 3010 is often "Success, reboot required"
                    $Failures.Add([PSCustomObject]@{ Name = $App.name; Error = "Exit Code: $($proc.ExitCode)" })
                }
            } else {
                $Failures.Add([PSCustomObject]@{ Name = $App.name; Error = "Path not found: $Path" })
            }
        } catch {
            $Failures.Add([PSCustomObject]@{ Name = $App.name; Error = $_.Exception.Message })
        }
    }

    $sync.Window.Dispatcher.Invoke({
        if ($Failures.Count -gt 0) {
            # Call the summary function in the main scope
            # Since we can't call main scope functions, we define the dialog logic here or trigger it.
            $summaryXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Installation Summary" Height="400" Width="500" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Some installations failed:" FontSize="16" FontWeight="Bold" Foreground="Red" Margin="0,0,0,10"/>
        <DataGrid Grid.Row="1" ItemsSource="{Binding}" AutoGenerateColumns="False" IsReadOnly="True" Background="White">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Application" Binding="{Binding Name}" Width="150"/>
                <DataGridTextColumn Header="Error" Binding="{Binding Error}" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>
        <Button Name="CloseSummaryBtn" Grid.Row="2" Content="Close" Height="30" Width="80" HorizontalAlignment="Right" Margin="0,10,0,0"/>
    </Grid>
</Window>
"@
            $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader([xml]$summaryXaml)))
            $dlg.Owner = $sync.Window
            $dlg.DataContext = $Failures
            $dlg.FindName("CloseSummaryBtn").Add_Click({ $dlg.Close() })
            $dlg.ShowDialog() | Out-Null
        }
    })

    Update-Status -Msg "Bulk installation complete." -Color "Green" -Progress 100
    # Trigger refresh
    $sync.Window.Dispatcher.Invoke({
        Invoke-BackgroundWork -ScriptBlock $RefreshRegistryTask -ArgumentList @{ sync = $sync }
    })
}

# ── XAML Definition ──────────────────────────────────────────
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Desiree Software Center" Height="750" Width="1000"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#E6F0FF" FontFamily="Segoe UI">
    <Grid>
        <Grid.RowDefinitions><RowDefinition Height="60"/><RowDefinition Height="*"/><RowDefinition Height="60"/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

        <Border Grid.Row="0" Grid.ColumnSpan="2" Background="#4682B4">
            <Grid>
                <TextBlock Text="   Debswana IT Automation Tool" Foreground="White" FontSize="22" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <TextBlock x:Name="ConnStatus" Text="● Checking Connection..." Foreground="White" FontSize="14" FontWeight="Bold" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,20,0"/>
            </Grid>
        </Border>

        <Border Grid.Row="1" Grid.Column="0" Background="White" BorderBrush="LightGray" BorderThickness="0,0,1,0">
            <StackPanel Margin="10,20,10,10">
                <TextBlock Text="CATEGORIES" FontSize="11" FontWeight="Bold" Foreground="Gray" Margin="5,0,0,10"/>
                <ItemsControl x:Name="CategoryList">
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <Button Content="{Binding Name}" Tag="{Binding Name}" Margin="0,2" Height="35" HorizontalContentAlignment="Left" Padding="10,0,0,0" Cursor="Hand" Style="{StaticResource {x:Static ToolBar.ButtonStyleKey}}">
                                <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="3"/></Style></Button.Resources>
                            </Button>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
                <Button x:Name="RefreshStatusBtn" Content="🔄 Refresh Status" Margin="0,150,0,5" Height="35" Cursor="Hand" Background="White"/>
                <TextBlock Text="Built by Desiree Chingwaru, Odirile Mathepeo" FontSize="10" Foreground="Gray" TextWrapping="Wrap" Margin="5,10,5,10"/>
                <Image x:Name="SidebarLogo" Width="160" Stretch="Uniform" Margin="0,10,0,0"/>
            </StackPanel>
        </Border>

        <Grid Grid.Row="1" Grid.Column="1" Margin="20">
            <Grid.RowDefinitions><RowDefinition Height="50"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Grid Grid.Row="0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="350"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBox x:Name="SearchBox" Grid.Column="0" Height="35" VerticalContentAlignment="Center" Padding="10,0,0,0" FontSize="14" />
                <Button x:Name="InstallAllBtn" Grid.Column="2" Content="⚡ Install All Standard" Width="160" Height="35" Margin="10,0,0,0" Background="#4682B4" Foreground="White" FontWeight="Bold" Cursor="Hand"/>
                <Button x:Name="AddAppBtn" Grid.Column="3" Content="+ Add App" Width="100" Height="35" Margin="10,0,0,0" Background="White" Cursor="Hand"/>
            </Grid>
            <ScrollViewer Grid.Row="1" Margin="0,10,0,0" VerticalScrollBarVisibility="Auto">
                <ItemsControl x:Name="AppDashboard">
                    <ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Columns="2" VerticalAlignment="Top"/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <Border Margin="5" Padding="10" Background="{Binding BgColor}" BorderBrush="LightGray" BorderThickness="1" CornerRadius="5">
                                <Grid>
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="100"/></Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0"><TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold"/><TextBlock Text="{Binding Category}" FontSize="11" Foreground="Gray"/></StackPanel>
                                    <Button Grid.Column="1" Content="{Binding ActionText}" Tag="{Binding}" Background="{Binding ActionColor}" Foreground="White" Height="35" Cursor="Hand"/>
                                </Grid>
                            </Border>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ScrollViewer>
        </Grid>

        <Border Grid.Row="2" Grid.ColumnSpan="2" Background="Transparent" Padding="20,10,20,10">
            <StackPanel><ProgressBar x:Name="MainProgress" Height="10" Minimum="0" Maximum="100" Value="0" Margin="0,0,0,5"/><TextBlock x:Name="StatusText" Text="Ready." FontSize="12" FontWeight="Bold"/></StackPanel>
        </Border>
    </Grid>
</Window>
"@

# ── UI Loading & Element Mapping ──────────────────────────────
$reader = New-Object System.Xml.XmlNodeReader([xml]$xaml)
$sync.Window = [Windows.Markup.XamlReader]::Load($reader)

$connStatus = $sync.Window.FindName("ConnStatus")
$categoryList = $sync.Window.FindName("CategoryList")
$refreshStatusBtn = $sync.Window.FindName("RefreshStatusBtn")
$sidebarLogo = $sync.Window.FindName("SidebarLogo")
$searchBox = $sync.Window.FindName("SearchBox")
$installAllBtn = $sync.Window.FindName("InstallAllBtn")
$addAppBtn = $sync.Window.FindName("AddAppBtn")
$appDashboard = $sync.Window.FindName("AppDashboard")
$mainProgress = $sync.Window.FindName("MainProgress")
$statusText = $sync.Window.FindName("StatusText")

# ── Helper Functions ─────────────────────────────────────────

function Update-UI {
    $sync.Window.Dispatcher.Invoke({
        $term = $searchBox.Text.Trim().ToLower()
        $filtered = if ($sync.SelectedCategory -eq "All") { $sync.AllApps } 
                    else { $sync.AllApps | Where-Object { $_.category -eq $sync.SelectedCategory } }
        
        if ($term) { $filtered = $filtered | Where-Object { $_.name.ToLower().Contains($term) -or $_.category.ToLower().Contains($term) } }

        $appDashboard.ItemsSource = $filtered | ForEach-Object {
            $isInstalled = [bool]$sync.AppStatusMap[$_.name]
            [PSCustomObject]@{
                Name = $_.name
                Category = $_.category
                BgColor = switch ($_.category) {
                    "Standard"     { "#E1F0FF" }
                    "Mining"       { "#C8E6FF" }
                    "IM"           { "#D2EBFF" }
                    "Uninstallers" { "#B4DCFF" }
                    default        { "White" }
                }
                ActionText = if ($isInstalled) { "Installed" } else { "Install" }
                ActionColor = if ($isInstalled) { "MediumSeaGreen" } else { "#4682B4" }
                RawApp = $_
            }
        }
    })
}

function Show-WifiWarning {
    $warnXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Corporate WiFi Required" Height="300" Width="500" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <Grid Margin="30">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Connect to DEBS WiFi" FontSize="18" FontWeight="Bold" Foreground="#2D465F"/>
        <TextBlock Grid.Row="1" Text="This tool uses Debswana network locations. Accessing installers and shared paths will not work unless you are connected to the corporate DEBS WiFi." 
                   TextWrapping="Wrap" FontSize="13" Margin="0,15,0,15"/>
        <Button Name="OkBtn" Grid.Row="2" Content="OK" Width="100" Height="30" HorizontalAlignment="Right" Background="#4682B4" Foreground="White"/>
    </Grid>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader([xml]$warnXaml)))
    $dlg.Owner = $sync.Window
    $dlg.FindName("OkBtn").Add_Click({ $dlg.Close() })
    $dlg.ShowDialog() | Out-Null
}

# ── Event Handlers ───────────────────────────────────────────

$appDashboard.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler]{
    $app = $_.OriginalSource.Tag.RawApp
    if ($app) { Invoke-BackgroundWork -ScriptBlock $InstallAppTask -ArgumentList @{ sync = $sync; App = $app } }
})

$categoryList.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler]{
    $sync.SelectedCategory = $_.OriginalSource.Tag
    Update-UI
})

$searchBox.Add_TextChanged({ Update-UI })

$refreshStatusBtn.Add_Click({
    $statusText.Text = "Refreshing status..."
    Invoke-BackgroundWork -ScriptBlock $RefreshRegistryTask -ArgumentList @{ sync = $sync }
})

$installAllBtn.Add_Click({
    $standardApps = $sync.AllApps | Where-Object { $_.standard -eq $true -or $_.category -eq "Standard" }
    if ($standardApps.Count -eq 0) { return }

    $bulkXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Bulk Installation" Height="600" Width="500" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Select apps to install:" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
        <ScrollViewer Grid.Row="1" BorderBrush="LightGray" BorderThickness="1">
            <ItemsControl Name="StandardAppList">
                <ItemsControl.ItemTemplate><DataTemplate><CheckBox Content="{Binding name}" IsChecked="{Binding IsSelected}" Margin="5" FontSize="14"/></DataTemplate></ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>
        <Button Name="StartBulkBtn" Grid.Row="2" Content="Start Installation" Height="35" Width="150" HorizontalAlignment="Right" Margin="0,10,0,0" Background="#4682B4" Foreground="White" FontWeight="Bold"/>
    </Grid>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader([xml]$bulkXaml)))
    $dlg.Owner = $sync.Window
    $uiModel = $standardApps | ForEach-Object { [PSCustomObject]@{ name = $_.name; IsSelected = $true; RawApp = $_ } }
    $dlg.FindName("StandardAppList").ItemsSource = $uiModel
    $dlg.FindName("StartBulkBtn").Add_Click({
        $selected = $uiModel | Where-Object { $_.IsSelected } | ForEach-Object { $_.RawApp }
        if ($selected) { Invoke-BackgroundWork -ScriptBlock $BulkInstallTask -ArgumentList @{ sync = $sync; Apps = $selected } }
        $dlg.Close()
    })
    $dlg.ShowDialog() | Out-Null
})

$addAppBtn.Add_Click({
    $addAppXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Add Application" Height="400" Width="450" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <StackPanel Margin="0,0,0,10"><TextBlock Text="Name:"/><TextBox Name="AppName" Height="25"/></StackPanel>
        <StackPanel Grid.Row="1" Margin="0,0,0,10"><TextBlock Text="Path:"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBox Name="AppPath" Height="25"/><Button Name="BrowseBtn" Grid.Column="1" Content="..." Width="30" Margin="5,0,0,0"/></Grid></StackPanel>
        <StackPanel Grid.Row="2" Margin="0,0,0,10"><TextBlock Text="Args:"/><TextBox Name="AppArgs" Height="25"/></StackPanel>
        <StackPanel Grid.Row="3" Margin="0,0,0,10"><TextBlock Text="Category:"/><ComboBox Name="AppCategory"><ComboBoxItem Content="Standard" IsSelected="True"/><ComboBoxItem Content="Mining"/><ComboBoxItem Content="Oil Processing"/><ComboBoxItem Content="IM"/><ComboBoxItem Content="Uninstallers"/></ComboBox></StackPanel>
        <Button Name="SaveBtn" Grid.Row="5" Content="Save" Height="35" Width="100" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
    </Grid>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader([xml]$addAppXaml)))
    $dlg.Owner = $sync.Window
    $dlg.FindName("BrowseBtn").Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dlg.FindName("AppPath").Text = $ofd.FileName }
    })
    $dlg.FindName("SaveBtn").Add_Click({
        $newApp = @{ name = $dlg.FindName("AppName").Text; path = $dlg.FindName("AppPath").Text; args = $dlg.FindName("AppArgs").Text; category = $dlg.FindName("AppCategory").Text; type = "exe"; standard = ($dlg.FindName("AppCategory").Text -eq "Standard") }
        $sync.AllApps += $newApp
        [System.IO.File]::WriteAllText($sync.AppsJsonPath, ($sync.AllApps | ConvertTo-Json -Depth 5))
        Update-UI
        $dlg.Close()
    })
    $dlg.ShowDialog() | Out-Null
})

# ── Startup Logic ────────────────────────────────────────────

if (Test-Path $LogoPath) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit(); $bitmap.UriSource = New-Object System.Uri($LogoPath, [System.UriKind]::Absolute); $bitmap.EndInit()
        $sidebarLogo.Source = $bitmap
    } catch {}
}

$categories = @("All", "Standard", "Mining", "Oil Processing", "IM", "Uninstallers")
$categoryList.ItemsSource = $categories | ForEach-Object { [PSCustomObject]@{ Name = $_ } }

if (Test-Path $sync.AppsJsonPath) {
    $raw = [System.IO.File]::ReadAllText($sync.AppsJsonPath)
    try { $sync.AllApps = $raw | ConvertFrom-Json } catch { $sync.AllApps = @() }
} else { $sync.AllApps = @() }

# Pre-populate map with false to avoid nulls
foreach ($app in $sync.AllApps) { $sync.AppStatusMap[$app.name] = $false }

Invoke-BackgroundWork -ScriptBlock $RefreshRegistryTask -ArgumentList @{ sync = $sync }
Invoke-BackgroundWork -ScriptBlock $CheckWifiTask -ArgumentList @{ sync = $sync }

$sync.Window.Add_Loaded({
    Update-UI
    # WiFi Warning check after a slight delay, but using a Timer to not block UI
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Add_Tick({
        $timer.Stop()
        if ($sync.WifiStatus -and -not $sync.WifiStatus.IsDebs) { Show-WifiWarning }
    }.GetNewClosure())
    $timer.Start()
})

$sync.Window.ShowDialog() | Out-Null
$RunspacePool.Close(); $RunspacePool.Dispose()
        
