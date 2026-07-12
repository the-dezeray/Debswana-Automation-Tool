# Debswana Automation Tool - Installation Guide

## Quick Start Installation

### Option 1: Using Pre-built Executable (Easiest)
1. Download the latest `debswana-automation-tool.exe` from the network share
2. Double-click the executable to run
3. No additional installation required

### Option 2: Running from Python Source
```bash
# 1. Ensure Python 3.8+ is installed
python --version

# 2. Install dependencies
pip install customtkinter Pillow

# 3. Run the application
python main.py
```

### Option 3: Using uv Package Manager
```bash
# 1. Install uv (if not already installed)
pip install uv

# 2. Install project dependencies
uv pip install -r pyproject.toml

# 3. Run the application
python main.py
```

## Network Configuration

### Prerequisites
- **Network Connection**: Must be connected to DEBS corporate WiFi (`debs.debswana.bw`)
- **Network Access**: Permissions to access `\\10.50.93.5\g\`
- **File Access**: Read/write access to `\\10.50.93.5\g\DebswanaAutomationProject\`

### First-Time Setup
1. **Connect to DEBS WiFi**: Ensure you're connected to the corporate network
2. **Verify Network Path**: Open File Explorer and navigate to `\\10.50.93.5\g\`
3. **Run Application**: Launch the Debswana Automation Tool
4. **Authentication**: If prompted, enter your network credentials

## Application Manual

### Basic Operations

#### 1. Launching the Application
- Double-click `main.py` or the compiled executable
- The application will automatically check network connectivity
- If connection fails, use the "Retry" button or open network path in Explorer

#### 2. Navigating the Interface
- **Left Sidebar**: Categories for filtering applications
- **Main Area**: Application cards with install buttons
- **Top Bar**: Search functionality and action buttons
- **Status Bar**: Current operation status and progress

#### 3. Installing Applications
1. Browse or search for the desired application
2. Click the "Install" button on the application card
3. Monitor progress in the status bar
4. For administrator installations, accept the UAC prompt if shown

#### 4. Adding New Applications
1. Click "Add App" button or press `Ctrl+A`
2. Fill in application details:
   - **Name**: Display name for the application
   - **Path**: Browse to select installer (starts at `\\10.50.93.5\g\`)
   - **Arguments**: Command-line arguments if needed
   - **Category**: Select appropriate category
3. Click "Save" to add to repository

### Advanced Features

#### Bulk Installation
- Click "Install All Standard" to install all standard applications
- Monitor progress in the status bar
- Failed installations will be reported separately

#### Application Management
- **Right-click** on any application card for options:
  - **Open Path**: Open the installer location in File Explorer
  - **Edit**: Modify application details
  - **Delete**: Remove application from repository (not implemented in current version)

#### Network Tools
- **Quick Tools**: Access proxy settings and other utilities
- **Connection Check**: Automatically verifies network connectivity
- **Server Explorer**: Open network server in File Explorer

## Troubleshooting

### Common Issues and Solutions

#### 1. "Network Connection Failed"
```
Symptoms: 
- Application shows "Checking connection..." indefinitely
- Unable to load application list
- Network status shows as disconnected

Solutions:
1. Verify WiFi connection to DEBS network
2. Click "Retry" button in connection dialog
3. Use "Open \\10.50.93.5 in Explorer" button to authenticate
4. Check if `\\10.50.93.5` is accessible in File Explorer
5. Contact IT for network permissions
```

#### 2. "Application Won't Start"
```
Symptoms:
- Python errors when running from source
- Executable fails to launch
- Missing dependency errors

Solutions:
1. For Python source: Install required packages
   pip install customtkinter Pillow
2. For executable: Ensure all required DLLs are present
3. Run as administrator if permission issues occur
4. Check Python version (requires 3.8+)
```

#### 3. "Installation Failed"
```
Symptoms:
- Installer launches but fails
- Permission denied errors
- File not found errors

Solutions:
1. Verify installer path exists on network
2. Run application as administrator
3. Check if installer requires special permissions
4. Ensure sufficient disk space
5. Verify network connectivity during installation
```

#### 4. "Missing Application List"
```
Symptoms:
- Empty application dashboard
- "No applications found" message
- Categories show empty

Solutions:
1. Check `apps.json` exists at network path
2. Verify read permissions for network share
3. Restart application to reload data
4. Check network connection is stable
```

### Network Path Configuration

#### Default Paths
- **Application Repository**: `\\10.50.93.5\g\DebswanaAutomationProject\apps.json`
- **File Dialog Start**: `\\10.50.93.5\g\` (when browsing for installers)
- **Network Server**: `\\10.50.93.5`

#### Modifying Network Settings
To change network configuration, edit `app_logic.py`:
```python
# Current settings
APPS_JSON_NETWORK = r"\\10.50.93.5\g\DebswanaAutomationProject\apps.json"
SERVER = r"\\10.50.93.5"

# Example modification for different server
# APPS_JSON_NETWORK = r"\\different-server\share\apps.json"
# SERVER = r"\\different-server"
```

## Building from Source

### Development Setup
```bash
# 1. Clone or download source code
git clone <repository-url>
cd debswana-automation-tool

# 2. Create virtual environment (optional but recommended)
python -m venv venv
venv\Scripts\activate  # Windows

# 3. Install development dependencies
pip install customtkinter Pillow pyinstaller

# 4. Run the application
python main.py
```

### Building Executable
```bash
# Method 1: Using build script
build.bat

# Method 2: Manual PyInstaller build
python build_exe.py

# The executable will be created in 'dist' folder
# Required assets are automatically included
```

### Adding New Features
1. **GUI Changes**: Modify `main.py`
2. **Business Logic**: Update `app_logic.py`
3. **Assets**: Add images/icons to `assets/` folder
4. **Application Data**: Update `apps.json` on network server

## Keyboard Shortcuts Reference

| Shortcut | Action | Description |
|----------|--------|-------------|
| `Ctrl+F` | Focus Search | Move cursor to search bar |
| `Ctrl+A` | Add Application | Open add application dialog |
| `↑` `↓` | Navigate List | Move selection up/down |
| `Enter` | Install Selected | Install currently selected app |
| `Ctrl+I` | About Dialog | Show application information |
| `Ctrl+R` | Rename PC | Open system rename settings |
| `Ctrl+L` | Installed Apps | Open Programs and Features |
| `Ctrl+W` | Close Application | Exit the application |

## Support and Resources

### Getting Help
1. **Network Issues**: Contact IT department
2. **Application Bugs**: Report to development team
3. **Installation Problems**: Check troubleshooting section above

### Additional Resources
- **Network Path**: `\\10.50.93.5\g\DebswanaAutomationProject\`
- **Source Code**: Available on network share
- **Documentation**: This guide and README.md

### Version Information
- **Current Version**: v0.4 (debsSoft-kit)
- **Python Version**: 3.8+ compatible
- **Platform**: Windows 10/11
- **Network**: Debswana corporate network only

---

**Note**: This application is designed specifically for the Debswana corporate environment. All network paths and configurations are optimized for the `\\10.50.93.5` server infrastructure.