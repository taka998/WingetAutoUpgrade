# Changelog

All notable changes to WingetAutoUpgrade will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2026-01-27

### Added
- Enhanced error handling with detailed error messages and stack traces
- `Get-FilteredUpgradeList` function for package filtering
- `Start-PackageUpgradeJob` function for ThreadJob initialization
- `Update-PackageJobStatus` function for job state management
- `Update-ProgressDisplay` function for unified progress rendering
- `Show-UpgradeSummary` function for detailed result summary
- `Get-StateColor` function for state-based coloring
- `Get-ProgressBar` function for progress bar generation
- `Get-StatusSummary` function for status aggregation
- `Write-ColoredLine` function for colored output
- Timestamp tracking (StartTime/EndTime) for each package
- Comprehensive error reporting with error categories
- Full documentation for all functions with `.SYNOPSIS` tags

### Changed
- **BREAKING**: Refactored `Invoke-PackageUpgrade` from 380 lines to ~135 lines (64.5% reduction)
- Reduced total script size from 1102 to ~746 lines (32.3% reduction)
- Unified progress display logic using single `Update-ProgressDisplay` function
- Improved error capture with `ERROR:` and `ERRORDETAIL:` output tags
- Enhanced null/empty string handling with `try-catch` blocks
- Fixed PowerShell variable reference issues using `${}` syntax

### Fixed
- Double rendering issue on initial display
- Progress display position drift
- Variable reference errors in string interpolation
- Missing error details for failed package upgrades
- Inconsistent display updates during progress rendering

### Removed
- `Initialize-ProgressDisplay` function (merged into `Update-ProgressDisplay`)
- Duplicate rendering logic
- Unused progress tracking fields (DownloadProgress, BytesDownloaded, BytesRequired)

## [3.0.0] - 2024-XX-XX

### Added
- Multi-threaded package upgrades using ThreadJob
- Real-time progress display with animated spinners
- Skip list support via JSON configuration
- Status summary aggregation
- Stylish console UI with Unicode box drawing

### Changed
- Switched from sequential to parallel execution
- Improved progress tracking and display

## [2.0.0] - Deprecated

Experimental version - no longer supported.

## [1.0.0] - Deprecated

Initial experimental version - no longer supported.

---

## Migration Guide

### From v3 to v4

v4 is fully backward compatible with v3. Simply replace:
```powershell
.\WingetUpgrade_v3.ps1
```
with:
```powershell
.\WingetUpgrade_v4.ps1
```

**Key improvements you'll notice:**
- More detailed error messages when packages fail
- Smoother progress display without flickering
- Better debugging information in debug mode

**No breaking changes** - all parameters and configuration files work the same way.
