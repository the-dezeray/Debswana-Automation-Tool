# Debswana Automation Tool - Quick Start Guide

## ⚡ 5-Minute Setup

### Step 1: Get the Application
- **Option A**: Download `debswana-automation-tool.exe` from network share
- **Option B**: Run from Python source with `python main.py`

### Step 2: Connect to Network
1. Ensure you're connected to **DEBS WiFi** (`debs.debswana.bw`)
2. Launch the application
3. Allow network connection check (auto-detects connectivity)

### Step 3: Start Using
- Browse applications by category
- Click "Install" on any application
- Use search to find specific apps

## 🎯 Key Features at a Glance

### 1. **Application Installation**
- Single-click installation
- Administrator support for elevated installs
- Progress tracking in status bar

### 2. **Application Management**
- Add new apps with `Ctrl+A` or "Add App" button
- Edit existing applications via right-click menu
- Categorize apps (Standard, Mining, Ore Processing, IM, Uninstallers)

### 3. **Network Integration**
- Auto-detects DEBS network connectivity
- Direct access to `\\10.50.93.5\g\` network share
- File dialogs start at network path by default

### 4. **Bulk Operations**
- "Install All Standard" for mass deployment
- Batch installation with progress tracking
- Failed installation reporting

## 🚀 Pro Tips

### Quick Navigation
- `Ctrl+F` → Focus search
- `Ctrl+A` → Add new application
- `↑/↓` → Navigate app list
- `Enter` → Install selected app

### Network Troubleshooting
If connection fails:
1. Click "Retry" in connection dialog
2. Use "Open \\10.50.93.5 in Explorer" to authenticate
3. Verify DEBS WiFi connection

### Adding Applications Efficiently
1. Press `Ctrl+A` to open add dialog
2. File browser automatically opens at `\\10.50.93.5\g\`
3. Select installer, fill details, save

## ❓ Common Questions

**Q: Do I need special permissions?**
A: Standard user permissions work for most operations. Some installations may require admin rights.

**Q: Can I use this offline?**
A: No, network connection to `\\10.50.93.5` is required for application data.

**Q: How do I update the application?**
A: Download the latest version from the network share or update source code.

**Q: Where are applications stored?**
A: Application definitions are stored at `\\10.50.93.5\g\DebswanaAutomationProject\apps.json`

## 📞 Getting Help

### Immediate Issues
1. Check network connection to DEBS WiFi
2. Verify `\\10.50.93.5` is accessible in File Explorer
3. Restart the application

### Technical Support
- Network issues: Contact IT department
- Application bugs: Report to development team
- Installation problems: Check INSTALLATION_GUIDE.md

---

**Remember**: This tool is designed for Debswana corporate network. All paths and configurations are optimized for `\\10.50.93.5` infrastructure.