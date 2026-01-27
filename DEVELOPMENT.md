# Developer Documentation

## Architecture Overview

### Design Principles

WingetUpgrade_v4.ps1 follows these design principles:

1. **Single Responsibility Principle** - Each function has one clear purpose
2. **Separation of Concerns** - UI, business logic, and state management are separated
3. **Error Handling First** - Comprehensive error capture and reporting
4. **Maintainability** - Clear naming, documentation, and modular structure

---

## Function Reference

### Core Functions

#### `Invoke-PackageUpgrade`
**Purpose:** Main orchestration function for package upgrades

**Responsibilities:**
- Initialize package status tracking
- Launch parallel upgrade jobs
- Monitor job progress
- Update real-time display
- Generate final summary

**Key Variables:**
- `$packageStatus` - Hashtable tracking state of each package
- `$packageJobs` - Hashtable of ThreadJob objects
- `$displayStartLine` - Console line where progress display begins

**Flow:**
```
1. Filter packages → Get-FilteredUpgradeList
2. Start jobs → Start-PackageUpgradeJob (foreach package)
3. Monitor loop:
   - Update status → Update-PackageJobStatus
   - Redraw display → Update-ProgressDisplay
   - Clean up completed jobs
4. Show summary → Show-UpgradeSummary
```

---

### Helper Functions

#### `Get-FilteredUpgradeList`
**Purpose:** Filter packages against skip list and initialize status

**Parameters:**
- `PackageList` - Array of packages to filter
- `SkipList` - Skip list object from JSON

**Returns:**
```powershell
@{
    PackageStatus = @{}     # Hashtable of package states
    UpgradeCount = 0        # Number of packages to upgrade
    SkipCount = 0           # Number of skipped packages
}
```

**Package Status Structure:**
```powershell
@{
    State = "Queued"           # Current state
    Icon = "⏸"                 # Display icon
    ErrorMessage = $null       # Error message if failed
    ErrorDetails = $null       # Stack trace if available
    StartTime = $null          # When upgrade started
    EndTime = $null            # When upgrade finished
}
```

---

#### `Start-PackageUpgradeJob`
**Purpose:** Launch a ThreadJob to upgrade a single package

**Parameters:**
- `PackageId` - Package identifier
- `DebugMode` - Enable debug output

**Returns:** ThreadJob object or `$null` on failure

**Job Output Protocol:**
Jobs communicate via structured output:
```
STATUS:Downloading:${PackageId}
STATUS:Completed:${PackageId}
STATUS:Failed:${PackageId}
ERROR:${PackageId}:${ErrorMessage}
ERRORDETAIL:${PackageId}:${StackTrace}
```

**Key Considerations:**
- Jobs run in separate runspace (must re-import modules)
- All PowerShell preference variables set to `SilentlyContinue`
- Package re-queried in job context to ensure fresh data

---

#### `Update-PackageJobStatus`
**Purpose:** Update package status based on job output

**Parameters:**
- `PackageStatus` - Status hashtable (modified in-place)
- `PackageJobs` - Job hashtable
- `SpinnerChars` - Array of spinner animation characters
- `SpinnerIndex` - Current spinner position

**Returns:**
```powershell
@{
    CompletedJobs = @()  # Array of completed package IDs
}
```

**Status State Machine:**
```
Queued → Processing → Downloading → Installing → Completed
                                                ↓
                                              Failed
```

**Error Extraction:**
Uses regex to parse structured output:
- `^ERROR:${PackageId}:(.*)` → ErrorMessage
- `^ERRORDETAIL:${PackageId}:(.*)` → ErrorDetails

---

#### `Update-ProgressDisplay`
**Purpose:** Render progress display in-place

**Parameters:**
- `PackageStatus` - Current package states
- `TotalJobs` - Total number of jobs
- `CompletedCount` - Number of completed jobs
- `DisplayStartLine` - Console line to start rendering
- `HasCurrentActivity` - Whether to show status summary

**Returns:** Number of lines rendered (for cursor positioning)

**Rendering Algorithm:**
```
1. Build content array:
   - Empty line
   - Separator (━━━)
   - Package lines (sorted)
   - Separator
   - Progress bar
   - Status summary (if active)
   - Empty line

2. For each line:
   - Position cursor
   - Clear line
   - Write colored content

3. Return cursor position delta
```

**Why Cursor Positioning?**
- Prevents screen flickering
- Enables smooth animations
- Maintains clean display during updates

---

#### `Show-UpgradeSummary`
**Purpose:** Display final upgrade results with error details

**Features:**
- Success/failure counts
- Detailed error information for failed packages
- Error categorization (future enhancement)

**Output Format:**
```
✨ Upgrade Complete
  ✅ X succeeded, ❌ Y failed

❌ Failed Packages:
  • Package.Id
    Reason: Error message
    Details: Stack trace
```

---

### Utility Functions

#### `Get-StateColor`
**Purpose:** Map package state to console color

**State Colors:**
- `Completed` → Green
- `Failed` → Red
- `Downloading` → Cyan
- `Installing` → Yellow
- `Processing` → White
- `Queued` → DarkGray

---

#### `Get-ProgressBar`
**Purpose:** Generate ASCII progress bar string

**Algorithm:**
```powershell
$percentage = ($CompletedCount / $TotalJobs) * 100
$filled = ($barLength * $CompletedCount) / $TotalJobs
$bar = "█" * $filled + "░" * ($barLength - $filled)
return "[$bar] $percentage% ($CompletedCount/$TotalJobs)"
```

---

#### `Get-StatusSummary`
**Purpose:** Generate status summary string

**Example Output:**
```
Status: Downloading 2, Installing 1, Completed 3
```

---

#### `Write-ColoredLine`
**Purpose:** Write a line with appropriate coloring

**Pattern Matching:**
- `^\[(.+)\] (.+) \((.+)\)$` → Package status line
- `^━` → Separator (Cyan)
- `^Upgrading` → Progress bar (Yellow)
- `^Status:` → Summary (Magenta)
- Default → Plain text

**Error Handling:**
- Try-catch for coloring failures
- Fallback to plain output
- Handles null/empty strings gracefully

---

## State Management

### Package Status Lifecycle

```
┌─────────┐
│ Queued  │ Initial state
└────┬────┘
     │
     v
┌───────────┐
│Processing │ Job started, no status yet
└─────┬─────┘
      │
      v
┌─────────────┐
│ Downloading │ STATUS:Downloading received
└──────┬──────┘
       │
       v
┌────────────┐
│Installing  │ STATUS:Installing received
└─────┬──────┘
      │
      ├─────> ┌───────────┐
      │        │ Completed │ SUCCESS
      │        └───────────┘
      │
      └─────> ┌────────┐
               │ Failed │ ERROR
               └────────┘
```

### Display Update Cycle

```
Main Loop (while jobs exist):
  │
  ├─> Update-PackageJobStatus
  │   └─> Update all package states
  │
  ├─> Calculate state hash
  │   └─> pkgId-state|pkgId-state|...
  │
  ├─> If hash changed:
  │   ├─> Update-ProgressDisplay
  │   └─> Reposition cursor
  │
  └─> Sleep 5ms
```

---

## Performance Considerations

### Threading Model
- **Main Thread:** UI updates and orchestration
- **ThreadJobs:** Individual package upgrades (N jobs = N packages)
- **No thread pool limit:** Can spawn many jobs simultaneously

**Memory Impact:**
- Each ThreadJob: ~5-10MB overhead
- Typical usage: 5-20 jobs → 50-200MB
- Consider batching for 100+ packages

### Display Performance
- **Update Frequency:** Every 5ms when state changes
- **Console I/O:** ~100-500ms per full redraw
- **Optimization:** State hash prevents unnecessary redraws

---

## Error Handling Strategy

### Levels of Error Capture

1. **Job Level** (ThreadJob scriptblock):
   ```powershell
   try {
       Update-WinGetPackage ...
   } catch {
       Write-Output "ERROR:${PackageId}:$($_.Exception.Message)"
       Write-Output "ERRORDETAIL:${PackageId}:$($_.ScriptStackTrace)"
   }
   ```

2. **Job Launch Level** (Start-PackageUpgradeJob):
   ```powershell
   try {
       $job = Start-ThreadJob ...
   } catch {
       Write-Host "Failed to start upgrade..."
       return $null
   }
   ```

3. **Display Level** (Write-ColoredLine, Update-ProgressDisplay):
   ```powershell
   try {
       [Console]::SetCursorPosition(...)
   } catch {
       # Silently ignore display errors
   }
   ```

### Error Categories (Future Enhancement)

Could categorize errors for better user guidance:
- **Network:** Connection issues, download failures
- **Permission:** Access denied, UAC issues
- **Installer:** Exit codes, corruption
- **Timeout:** Long-running operations

---

## Testing Guidelines

### Manual Testing Checklist

- [ ] Normal upgrade (multiple packages)
- [ ] All packages up-to-date
- [ ] Network disconnected (should fail gracefully)
- [ ] Skip list functionality
- [ ] Debug mode output
- [ ] Single package upgrade
- [ ] Console resize during operation
- [ ] Ctrl+C interruption

### Edge Cases

- **No packages to upgrade:** Should display friendly message
- **All packages skipped:** Should handle gracefully
- **Job start failure:** Should remove from status and continue
- **Console buffer overflow:** Should check `[Console]::BufferHeight`

---

## Future Enhancements

### Planned Features
- [ ] Configurable parallel job limit
- [ ] Log file output option
- [ ] Configuration file for settings
- [ ] Package upgrade history tracking
- [ ] Rollback capability
- [ ] Email notifications
- [ ] Silent mode (no UI)

### Technical Debt
- Consider using `System.Threading.Tasks` for better async control
- Evaluate alternative to console position manipulation (host buffer issues)
- Add Pester unit tests
- Add integration tests with mock packages

---

## Contribution Guidelines

### Code Style
- Use PascalCase for function names
- Use camelCase for variables
- Add `.SYNOPSIS` to all functions
- Keep functions under 100 lines
- Use `try-catch` for external calls
- Document complex logic with comments

### Pull Request Process
1. Test with multiple packages
2. Update CHANGELOG.md
3. Add documentation if adding features
4. Ensure all functions have `.SYNOPSIS`
5. Run syntax validation

---

## Debugging Tips

### Enable Verbose Mode
```powershell
.\WingetUpgrade_v4.ps1 -DebugMode $true
```

### Check Job Output
```powershell
# In debug mode, job IDs are printed
Get-Job -Id <ID> | Receive-Job
```

### Display Issues
If display gets corrupted:
1. Resize console window
2. Run `Clear-Host`
3. Re-run script

### Common Issues
- **Jobs hang:** Check network connection
- **Display flickers:** Reduce number of parallel jobs
- **Errors not showing:** Check `$ErrorActionPreference`

---

_This documentation was created for WingetUpgrade v4.0_
