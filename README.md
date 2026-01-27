# WingetAutoUpgrade ⚡

Multi-threaded Windows Package Manager automation with real-time progress display and enhanced error handling.

## ✨ Features

- 🚀 **Parallel Execution** - Upgrade multiple packages simultaneously using ThreadJob
- 🎨 **Real-time Progress Display** - Animated spinners and progress bars with unified rendering
- 📊 **Status Summary** - Aggregated view of all package states
- ⚙️ **Skip List Support** - Configure packages to skip via JSON file
- 🔍 **Enhanced Error Handling** - Detailed error messages with stack traces (v4+)
- 🧩 **Modular Architecture** - Clean, maintainable code with 10+ helper functions (v4+)
- 📝 **Comprehensive Documentation** - All functions fully documented

## 📸 Preview

```
╔═══════════════════════════════════════════════════════╗
║      🚀 Winget Package Upgrade Script v4              ║
╚═══════════════════════════════════════════════════════╝
🔍 Checking for package updates...

📦 Found 3 package(s) to upgrade

  1. Discord.Discord 1.0.9035 → 1.0.9222
  2. Python.Python 3.11.0 → 3.12.0
  3. Node.js 18.0.0 → 20.0.0 (Skip)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[⠋] Discord.Discord (Downloading)
[⠸] Python.Python (Installing)
[✓] VSCode (Completed)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Upgrading packages... [████████░░░░░░░░░░░░] 40% (2/5)
Status: Downloading 1, Installing 1, Completed 2

✨ Upgrade Complete
  ✅ 4 succeeded
  ❌ 1 failed

❌ Failed Packages:
  • Some.Package
    Reason: Installer returned exit code 1603
    Details: at Update-WinGetPackage...
```

## 🚦 Requirements

- Windows 10/11
- PowerShell 5.1 or later
- [Windows Package Manager (winget)](https://github.com/microsoft/winget-cli)
- PowerShell modules:
  - `Microsoft.WinGet.Client`
  - `ThreadJob` (auto-installed if missing)

## 📦 Installation

1. Clone this repository:

   ```powershell
   git clone https://github.com/taka998/WingetAutoUpgrade.git
   cd WingetAutoUpgrade
   ```

2. Configure skip list (optional):
   ```powershell
   notepad WingetUpgrade_SkipLists.json
   ```

## 🎮 Usage

### Recommended: v4 (Latest - Refactored & Enhanced)

```powershell
.\WingetUpgrade_v4.ps1
```

### Legacy: v3 (Stable)

```powershell
.\WingetUpgrade_v3.ps1
```

### With debug mode:

```powershell
.\WingetUpgrade_v4.ps1 -DebugMode $true
```

## ⚙️ Configuration

Edit `WingetUpgrade_SkipLists.json` to skip specific packages:

```json
{
  "packages": [
    "Unity.Unity.6000",
    "SlackTechnologies.Slack",
    "Microsoft.Office"
  ]
}
```

## 📝 License

MIT License - feel free to use and modify!

## 📌 Version History

### v4.0 (Latest) - Major Refactoring ✨

**Code Quality Improvements:**

- 📦 Reduced main function from 380 lines to ~135 lines (64.5% reduction)
- 📉 Total script reduced from 1102 to ~746 lines (32.3% reduction)
- 🧩 Refactored into 10 focused helper functions
- 📝 Full documentation for all functions

**New Features:**

- 🔍 Enhanced error handling with detailed error messages
- 📋 Error stack traces for failed packages
- ⏱️ Timestamp tracking (StartTime/EndTime)
- 🎨 Unified progress display logic (prevents double rendering)
- 🛡️ Better null/empty string handling

**Technical Improvements:**

- Single-responsibility principle applied throughout
- Improved testability and maintainability
- Fixed PowerShell variable reference issues
- Cleaner, more readable code structure

### v3.0 - Stable Release

- Multi-threaded package upgrades
- Real-time progress display
- Skip list support
- Status summary

### v1-v2

Experimental versions (deprecated, kept for reference)

## 🏗️ Architecture (v4)

```
WingetUpgrade_v4.ps1
├── Helper Functions
│   ├── Get-FilteredUpgradeList      # Package filtering
│   ├── Start-PackageUpgradeJob      # ThreadJob initialization
│   ├── Update-PackageJobStatus      # Job state management
│   ├── Update-ProgressDisplay       # Unified progress rendering
│   ├── Show-UpgradeSummary          # Result summary with errors
│   ├── Get-StateColor               # State-based coloring
│   ├── Get-ProgressBar              # Progress bar generation
│   ├── Get-StatusSummary            # Status aggregation
│   └── Write-ColoredLine            # Colored output helper
│
├── Main Function
│   └── Invoke-PackageUpgrade        # Orchestration (~135 lines)
│
└── Main Execution
    ├── Module loading
    ├── Skip list import
    ├── Package detection
    └── Upgrade execution
```

## ⚠️ Known Limitations

### State Transition Issues

Currently, the `Installing` state is not properly reflected during package upgrades.

**Root Cause:**  
The Microsoft.WinGet.Client module does not provide a programmatically accessible API for querying installation state. While the module outputs progress information as text, this is directly rendered to the UI and cannot be parsed or utilized programmatically.

**Current Behavior:**

- State flow: `Queued` → `Downloading` → `Processing` → `Completed/Failed`
- The `Installing` state is defined in the code but never actually transitions

**Technical Details:**

```powershell
# The module writes progress directly to stdout
Update-WinGetPackage -InputObject $pkg -Mode Silent -Force
# ↑ There is no official way to retrieve state during this process
```

The state transition code is intentionally kept in the current script implementation. This is to ensure quick adaptation when the module provides a programmatically accessible state information API in future updates.

## 🔮 Future Improvements

### High Priority

- [ ] **Normalize State Transitions** - When Microsoft.WinGet.Client provides a state information API, properly display `Installing` and detailed progress states
- [ ] **Progress Percentage Display** - Show download/installation progress for each package

### Low Priority

- [ ] **Rollback Functionality** - Automatic rollback on upgrade failure
- [ ] **Update History Log** - Persistent logging and history management of upgrade results
- [ ] **Scheduled Execution** - Integration with Task Scheduler

_(This README was written with AI assistance)_

---

Made with ❤️ using PowerShell and winget
