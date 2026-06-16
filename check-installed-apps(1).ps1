Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing

# ════════════════════════════════════════════════════════════
#  List of apps to check for.
#  Each entry is a hashtable describing HOW to detect it:
#    Type = "Registry"  -> match against Uninstall DisplayName (partial, case-insensitive)
#    Type = "File"      -> check if a specific file/path exists
#    Type = "Service"   -> check if a Windows service exists (and optionally is running)
# ════════════════════════════════════════════════════════════
$AppsToCheck = @(
    @{ Name = "Dell Command Update";        Type = "Registry"; Match = "Dell Command" },
    @{ Name = "Microsoft Office 2019";      Type = "Registry"; Match = "Microsoft Office Professional Plus 2019" },
    @{ Name = "Cisco AnyConnect / Secure Client"; Type = "File"; Path = "C:\Program Files (x86)\Cisco\Cisco Secure Client\vpnagent.exe" },
    @{ Name = "Adobe Acrobat Reader";       Type = "Registry"; Match = "Adobe Acrobat" },
    @{ Name = "SCCM Client";                Type = "Service"; ServiceName = "CcmExec" },
    @{ Name = "SCEP / Endpoint Protection"; Type = "Registry"; Match = "Endpoint Protection" },
    @{ Name = "Enterprise Vault";           Type = "Registry"; Match = "Enterprise Vault" },
    @{ Name = "SAP GUI";                    Type = "Registry"; Match = "SAP GUI" },
    @{ Name = "SAPscript Legacy Text Editor"; Type = "Registry"; Match = "SAPscript" },
    @{ Name = "CrowdStrike Falcon";         Type = "Registry"; Match = "CrowdStrike Sensor Platform" },
    @{ Name = "TITUS Classification";       Type = "Registry"; Match = "TITUS Classification" },
    @{ Name = "Qualys Agent";               Type = "Registry"; Match = "Qualys Cloud Security Agent" }
)

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

# ── XAML UI ──────────────────────────────────────────────────
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="App Install Checker" Height="560" Width="620"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
        FontFamily="Segoe UI">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="Application Install Status"
                       FontSize="18" FontWeight="Bold"
                       Foreground="#1E46B4" VerticalAlignment="Center"/>
            <Button x:Name="RefreshBtn" Content="Refresh"
                    Width="90" Height="28" Margin="20,0,0,0"/>
        </StackPanel>

        <ListView x:Name="ResultsList" Grid.Row="1" FontSize="12">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Status" Width="60">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <TextBlock Text="{Binding Status}"
                                           Foreground="{Binding StatusColor}"
                                           FontWeight="Bold"
                                           HorizontalAlignment="Center"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Application" Width="220" DisplayMemberBinding="{Binding AppName}"/>
                    <GridViewColumn Header="Installed Version" Width="160" DisplayMemberBinding="{Binding DisplayName}"/>
                    <GridViewColumn Header="Version" Width="100" DisplayMemberBinding="{Binding Version}"/>
                </GridView>
            </ListView.View>
        </ListView>

        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
            <TextBlock x:Name="SummaryText" FontWeight="Bold" VerticalAlignment="Center"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$resultsList = $window.FindName("ResultsList")
$refreshBtn  = $window.FindName("RefreshBtn")
$summaryText = $window.FindName("SummaryText")

# ── Run the check and populate the list ─────────────────────
function Update-Results {
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    $resultsList.Items.Clear()

    $installed = Get-InstalledPrograms
    $foundCount = 0

    foreach ($app in $AppsToCheck) {
        $found = $false
        $detail = "Not found"
        $version = ""

        switch ($app.Type) {
            "Registry" {
                $match = $installed | Where-Object { $_.DisplayName -like "*$($app.Match)*" } | Select-Object -First 1
                if ($match) {
                    $found = $true
                    $detail = $match.DisplayName
                    $version = $match.DisplayVersion
                }
            }
            "File" {
                if (Test-Path $app.Path) {
                    $found = $true
                    $detail = $app.Path
                    try { $version = (Get-Item $app.Path).VersionInfo.ProductVersion } catch {}
                }
            }
            "Service" {
                $svc = Get-Service -Name $app.ServiceName -ErrorAction SilentlyContinue
                if ($svc) {
                    $found = $true
                    $detail = "$($svc.DisplayName) ($($svc.Status))"
                }
            }
        }

        if ($found) {
            $foundCount++
            $resultsList.Items.Add([PSCustomObject]@{
                Status      = [char]0x2714   # check mark
                StatusColor = "Green"
                AppName     = $app.Name
                DisplayName = $detail
                Version     = $version
            })
        } else {
            $resultsList.Items.Add([PSCustomObject]@{
                Status      = [char]0x2716   # cross mark
                StatusColor = "Red"
                AppName     = $app.Name
                DisplayName = $detail
                Version     = ""
            })
        }
    }

    $summaryText.Text = "Found $foundCount of $($AppsToCheck.Count) applications installed."
    $window.Cursor = [System.Windows.Input.Cursors]::Arrow
}

$refreshBtn.Add_Click({ Update-Results })

Update-Results

$window.ShowDialog() | Out-Null
