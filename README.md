# Debswana Automation Tool (debsSoft-kit)

A Windows software center application for managing and installing applications within the Debswana corporate network.

## Overview

The Debswana Automation Tool provides a centralized interface for installing, managing, and tracking software applications on Windows systems within the Debswana corporate network. The application connects to a network server at `\\10.50.93.5\g\DebswanaAutomationProject\` to retrieve and manage application definitions.

## Features

- **Network Integration**: Automatically connects to Debswana corporate network resources
- **Application Categories**: Organizes applications into Standard, Mining, Ore Processing, IM, and Uninstallers categories
- **Search & Filter**: Quick search and category filtering for applications
- **Bulk Installation**: Install multiple standard applications at once
- **Network Status**: Real-time network connectivity monitoring
- **Admin Support**: Run installations with administrator privileges
- **Keyboard Shortcuts**: Efficient navigation with keyboard shortcuts

## Installation Instructions

### Prerequisites

1. **Python 3.8+** (Recommended: Python 3.11)
2. **Windows 10/11** operating system
3. **Debswana Corporate Network Access** (DEBS WiFi)
4. **Required Python packages**:
   - customtkinter
   - Pillow (PIL)

### Installation Methods

#### Method 1: Using uv Package Manager (Recommended)

```bash
# Install uv if not already installed
pip install uv

# Clone or navigate to the project directory
cd debswana-automation-tool

# Install dependencies
uv pip install -r pyproject.toml

# Run the application
python main.py
```

#### Method 2: Using pip

```bash
pip install customtkinter Pillow

# Run the application
python main.py
```

#### Method 3: Building Executable

```bash
# Build standalone executable
python build_exe.py

# Or use the batch file
build.bat

# The executable will be created in the 'dist' folder
```

### Network Requirements

- Must be connected to **DEBS corporate WiFi** (SSID: `debs.debswana.bw`)
- Network server must be accessible at `\\10.50.93.5`
- Appropriate network permissions to access shared resources

## User Manual

### Getting Started

1. **Launch the Application**: Run `main.py` or the compiled executable
2. **Network Connection**: The application will automatically check network connectivity
3. **Application Loading**: Once connected, applications will load from the network server

### Main Interface Components

#### 1. Sidebar Navigation
- **Categories**: Filter applications by category (All, Standard, Mining, Ore Processing, IM, Uninstallers)
- **Quick Tools**: Access additional utilities and settings
- **About**: Application information and version details
- **Keyboard Shortcuts**: Reference for quick navigation

#### 2. Main Application Area
- **Search Bar**: Search applications by name or category
- **Application Cards**: Each application is displayed as a card with name, category, and install button
- **Status Bar**: Shows current operation status and progress

### Using the Application

#### Installing Applications
1. Browse or search for the desired application
2. Click the "Install" button on the application card
3. Monitor progress in the status bar
4. For administrator installations, accept the UAC prompt if shown

#### Adding New Applications
1. Click the "Add App" button (or press Ctrl+A)
2. Fill in the application details:
   - **Name**: Application display name
   - **Path**: Installation file path (starts at network path `\\10.50.93.5\g\`)
   - **Arguments**: Command-line arguments (if needed)
   - **Working Directory**: Installation working directory
   - **Category**: Application category
3. Click "Save" to add to the network repository

#### Network Troubleshooting
If connection issues occur:
1. Ensure you're connected to DEBS WiFi
2. Use "Retry" button to recheck connection
3. Open network path in Explorer using the provided button
4. Contact IT support if server is unreachable

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+F | Focus search bar |
| Ctrl+A | Add new application |
| ↑/↓ | Navigate application list |
| Enter | Install selected application |
| Ctrl+I | Open About dialog |
| Ctrl+R | Open PC rename settings |
| Ctrl+L | Open installed programs list |
| Ctrl+W | Close application |

## Technical Specifications

### Image Assets
- **Logo**: 1024×1024 pixels (Debswana mini logo)
- **Animated GIFs**: 480×480 pixels (file transfer, download animations)
- **Icons**: Various PNG/SVG assets for UI elements

### Network Configuration
- **Primary Server**: `\\10.50.93.5`
- **Apps Repository**: `\\10.50.93.5\g\DebswanaAutomationProject\apps.json`
- **Network Protocol**: SMB/CIFS for file sharing

### Application Data Structure
Applications are stored in `apps.json` with the following structure:
```json
[
  {
    "name": "Application Name",
    "path": "\\\\server\\path\\to\\installer.exe",
    "args": "installation arguments",
    "category": "Standard",
    "type": "exe",
    "workingDir": "installation directory",
    "standard": true
  }
]
```

## Troubleshooting

### Common Issues

1. **Network Connection Failed**
   - Verify DEBS WiFi connection
   - Check if `\\10.50.93.5` is accessible in File Explorer
   - Ensure network permissions are granted

2. **Application Won't Start**
   - Verify Python installation
   - Check all dependencies are installed
   - Run as administrator if needed

3. **Installation Failures**
   - Verify installer file exists at specified path
   - Check administrator privileges for installation
   - Ensure sufficient disk space

4. **Missing Application List**
   - Check `apps.json` file exists on network server
   - Verify read permissions for network share
   - Restart application to reload data

### Logs and Diagnostics
- Application logs are printed to console when running from source
- Network connection status is displayed in the header
- Installation progress is shown in the status bar

## Development

### Project Structure
```
debswana-automation-tool/
├── main.py              # Main application GUI
├── app_logic.py         # Application logic and network operations
├── apps.json            # Application definitions (on network)
├── assets/              # Image and icon resources
├── build.bat            # Build script for Windows
├── build_exe.py         # PyInstaller build script
├── pyproject.toml       # Python project configuration
└── README.md            # This documentation
```

### Building from Source
```bash
# Install build dependencies
uv pip install pyinstaller

# Build executable
python build_exe.py

# Or use the batch script
build.bat
```

### Adding New Features
1. Modify `main.py` for GUI changes
2. Update `app_logic.py` for business logic
3. Add new assets to `assets/` folder
4. Update `apps.json` on network server for new applications

## Network Path Configuration

### Default Path Settings
When adding new applications, the path selection dialog starts at the network location:
- **Base Network Path**: `\\10.50.93.5\g\`
- **Apps Repository**: `\\10.50.93.5\g\DebswanaAutomationProject\`

### Changing Network Configuration
To modify network settings, edit `app_logic.py`:
```python
APPS_JSON_NETWORK = r"\\10.50.93.5\g\DebswanaAutomationProject\apps.json"
SERVER = r"\\10.50.93.5"
```

## Support

For technical support or issues:
1. Check the troubleshooting section above
2. Verify network connectivity and permissions
3. Contact IT department for network-related issues
4. For application bugs, report to development team

## Version History

- **v0.4**: Current version with enhanced UI and network connectivity checks
- **v0.3**: Added application categories and search functionality
- **v0.2**: Basic application management and installation
- **v0.1**: Initial release with core functionality

---

*Note: This application is designed specifically for Debswana corporate network environment. Network paths and configurations may require adjustment for different network setups.*