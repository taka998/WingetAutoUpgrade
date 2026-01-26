# WingetAutoUpgrade ⚡

Multi-threaded Windows Package Manager automation with real-time progress display.

## ✨ Features

- 🚀 **Parallel Execution** - Upgrade multiple packages simultaneously using ThreadJob
- 🎨 **Real-time Progress Display** - Animated spinners and progress bars
- 📊 **Status Summary** - Aggregated view of all package states
- ⚙️ **Skip List Support** - Configure packages to skip via JSON file

## 📸 Preview

```
╔═══════════════════════════════════════════════════════╗
║      🚀 Winget Package Upgrade Script v3              ║
╚═══════════════════════════════════════════════════════╝
🔍 Checking for package updates...

📦 Found 3 package(s) to upgrade

  1. Discord.Discord 1.0.9035 → 1.0.9221
  2. Python.Python 3.11.0 → 3.12.0
  3. Node.js 18.0.0 → 20.0.0 (Skip)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[⠋] Discord.Discord (Downloading)
[⠸] Python.Python (Installing)
[✓] VSCode (Completed)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Upgrading packages... [████████░░░░░░░░░░░░] 40% (2/5)
Status: Downloading 1, Installing 1, Completed 2
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

```powershell
.\WingetUpgrade_v3.ps1
```

### With debug mode:
```powershell
.\WingetUpgrade_v3.ps1 -DebugMode $true
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

## 📌 Note

v1 and v2 are old experimental versions. They're kept for reference but will be removed eventually. Use v3.

_(This README was written with AI assistance)_

---

Made with ❤️ using PowerShell and winget
