# Code Review: Trickplay_Cleanup_v1.ps1

## Analysis & Suggested Improvements

### CRITICAL ISSUES

#### 1. **Write-Log Function Missing Error Handling for File Operations**
**Problem:** The `Write-Log` function calls `Add-Content` without error handling. If the log file path is invalid, inaccessible, or the drive is full, the script continues silently.

**Why it matters:** 
- Silent failures undermine audit trail integrity
- User expects logging to work if `-LogFile` is specified
- Disk full or permission issues aren't reported

**Suggested fix:**
```powershell
function Write-Log {
    param([string]$Message)
    Write-Output $Message
    if ($LogFile) {
        try {
            Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -ErrorAction Stop
        } catch {
            Write-Error "Failed to write to log file '$LogFile': $_" -ErrorAction Continue
        }
    }
}
```

#### 2. **No Log Directory Creation**
**Problem:** If `-LogFile "C:\Logs\trickplay.log"` is specified but `C:\Logs` doesn't exist, the script fails silently.

**Why it matters:** 
- User experience is degraded without clear feedback
- Log file feature is unreliable

**Suggested fix:**
```powershell
if ($LogFile) {
    $LogDir = Split-Path -Parent $LogFile
    if (-not (Test-Path -LiteralPath $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        } catch {
            Write-Error "Cannot create log directory: $LogDir - $_"
            exit 1
        }
    }
}
```

---

### HIGH PRIORITY ISSUES

#### 3. **No Input Validation on Root Parameter**
**Problem:** If user passes an invalid path string (e.g., `"V:\Movies\"` with trailing backslash or UNC path like `"\\server\share"`), behavior is unpredictable.

**Why it matters:**
- UNC paths require additional handling
- Trailing backslashes can cause `Get-ChildItem` to behave unexpectedly
- No feedback to user about why the scan produced no results

**Suggested fix:**
```powershell
# Normalize path: remove trailing slashes
$Root = $Root.TrimEnd('\', '/')

# Validate before proceeding
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Root path not found or inaccessible: $Root"
    exit 1
}

# Check for permission to read
try {
    Get-ChildItem -LiteralPath $Root -ErrorAction Stop | Out-Null
} catch {
    Write-Error "No read permission on root path: $Root - $_"
    exit 1
}
```

#### 4. **No Deletion Confirmation or Dry-Run Mode**
**Problem:** Script immediately deletes folders without asking for confirmation or showing what will be deleted.

**Why it matters:**
- Irreversible action without preview
- User might have accidentally run wrong folder
- No way to test behavior first

**Suggested fix:** Add optional switches:
```powershell
param(
    ...existing params...,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,  # Preview without deleting
    
    [Parameter(Mandatory = $false)]
    [switch]$Force    # Skip confirmation
)

# Then in Remove-TrickplayFolder:
if ($WhatIf) {
    Write-Log "  [WHATIF] Would remove: $($Folder.FullName)"
    return
}

if (-not $Force) {
    $response = Read-Host "Remove trickplay folder: $($Folder.FullName)? (y/n)"
    if ($response -ne 'y') {
        Write-Log "  Skipped: $($Folder.FullName)"
        return
    }
}
```

#### 5. **No Statistics or Summary Report**
**Problem:** Script logs deletions but doesn't provide summary (total items removed, errors, time taken).

**Why it matters:**
- Hard to verify cleanup effectiveness
- No metrics for troubleshooting
- Users want to know "how much was removed"

**Suggested fix:**
```powershell
$Script:Stats = @{
    ScannedFolders = 0
    EmptyFolders = 0
    TrickplayFound = 0
    TrickplayRemoved = 0
    TrickplayFailed = 0
}

# Then track in each function:
# In Invoke-TrickplayCleanup:
$Script:Stats.ScannedFolders++
if ($TrickplayFolders) {
    $Script:Stats.EmptyFolders++
    $Script:Stats.TrickplayFound += @($TrickplayFolders).Count
}

# In Remove-TrickplayFolder (in catch block):
if ($failed) { $Script:Stats.TrickplayFailed++ }
else { $Script:Stats.TrickplayRemoved++ }

# At end:
Write-Log "`nSummary:`n  Scanned: $($Script:Stats.ScannedFolders) folders`n  Empty (no media): $($Script:Stats.EmptyFolders)`n  Trickplay removed: $($Script:Stats.TrickplayRemoved)/$($Script:Stats.TrickplayFound)`n  Failed: $($Script:Stats.TrickplayFailed)"
```

---

### MEDIUM PRIORITY ISSUES

#### 6. **Recursive Attribute Clearing Can Affect Unintended Files**
**Problem:** `Get-ChildItem ... -Recurse -Force | ForEach { $_.Attributes = 'Normal' }` strips attributes from ALL nested files, including legitimate ones.

**Why it matters:**
- Could remove hidden/system flags from important files
- Might interfere with backup/archive attributes
- Overly broad permission change

**Suggested fix:**
```powershell
# Only clear the target folder's own attributes, not recursively
try {
    $(Get-Item -LiteralPath $Folder.FullName -Force).Attributes = 'Normal'
    
    # Then remove
    Remove-Item -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction Stop
    Write-Log "  Removed: $($Folder.FullName)"
} catch {
    # If folder is locked, try removing children first
    ...
}
```

#### 7. **No Recursion Limit on Media File Search**
**Problem:** `Test-HasMediaFile` uses `-Recurse` without limit. For deep folder structures, this is slow.

**Why it matters:**
- Performance degrades on large libraries with deep hierarchies
- Scans unnecessary subdirectories
- Movie/TV folders typically have media at depth 0-1

**Suggested fix:**
```powershell
param(
    ...,
    [Parameter(Mandatory = $false)]
    [int]$MaxSearchDepth = 2
)

# Use custom recursion instead of -Recurse:
function Get-FilesRecursive {
    param($Path, $Extensions, $CurrentDepth = 0, $MaxDepth)
    
    if ($CurrentDepth -ge $MaxDepth) { return }
    
    Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
        Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
        Select-Object -First 1
    
    if ($null -eq $_) {
        Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-FilesRecursive -Path $_.FullName -Extensions $Extensions -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
            }
    }
}
```

---

### BEST PRACTICES & RECOMMENDATIONS

#### 8. **Add Progress Indicator for Large Libraries**
**Problem:** No feedback during long scans.

**Suggested fix:**
```powershell
$totalFolders = (Get-ChildItem -LiteralPath $Root -Directory).Count
$current = 0

Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
    $current++
    Write-Progress -Activity "Scanning media library" -Status "$($_.Name)" -PercentComplete (($current / $totalFolders) * 100)
    Invoke-TrickplayCleanup -ScanPath $_.FullName
}
Write-Progress -Activity "Scanning media library" -Completed
```

#### 9. **Add Exclusion/Inclusion Patterns**
**Problem:** No way to skip certain folders or only process specific ones.

**Suggested fix:**
```powershell
param(
    ...,
    [Parameter(Mandatory = $false)]
    [string[]]$Exclude = @(),  # Regex patterns to skip
    
    [Parameter(Mandatory = $false)]
    [string[]]$Include = @()   # Only process matching names
)

# In main loop:
if ($Exclude -and $_ -match ($Exclude -join '|')) { continue }
if ($Include -and $_ -notmatch ($Include -join '|')) { continue }
```

#### 10. **Add Media Extension Customization**
**Problem:** Media extensions are hardcoded. Plex adds new codecs regularly.

**Suggested fix:**
```powershell
param(
    ...,
    [Parameter(Mandatory = $false)]
    [string[]]$MediaExtensions = @(
        ".mkv", ".mp4", ".m4v", ".mov", ".avi", ".wmv",
        ".mpg", ".mpeg", ".ts", ".m2ts", ".mts", ".vob",
        ".webm", ".flv", ".3gp"
    )
)
```

#### 11. **Add Execution Time Tracking**
**Problem:** User can't tell if script is slow or hanged.

**Suggested fix:**
```powershell
$startTime = Get-Date
...main logic...
$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds
Write-Log "Completed in $([math]::Round($duration, 2)) seconds"
```

#### 12. **Improve Error Messages with Context**
**Problem:** Generic error messages like "Failed to remove: path - error" don't help debug.

**Suggested fix:**
```powershell
catch {
    Write-Log "  Failed to remove: $($Folder.FullName)"
    Write-Log "  Error: $($_.Exception.Message)"
    Write-Log "  Category: $($_.CategoryInfo.Category)"
    # Offer remediation hint
    if ($_.Exception.Message -match 'permission|denied|access') {
        Write-Log "  Hint: Check folder permissions or that the folder is not in use"
    }
}
```

---

### CODE QUALITY IMPROVEMENTS

#### 13. **Extract Cleanup Logic Into Separate Mode Functions**
**Problem:** Movie vs TVShow logic is intermixed in main entry point.

**Suggested fix:**
```powershell
function Invoke-MovieCleanup {
    param([string]$Root)
    Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
        Invoke-TrickplayCleanup -ScanPath $_.FullName
    }
}

function Invoke-TVShowCleanup {
    param([string]$Root)
    Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
        $ShowFolder = $_
        Get-ChildItem -LiteralPath $ShowFolder.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Invoke-TrickplayCleanup -ScanPath $_.FullName
        }
    }
}

# Then main logic:
if ($LibraryType -eq 'Movie') {
    Invoke-MovieCleanup -Root $Root
} else {
    Invoke-TVShowCleanup -Root $Root
}
```

#### 14. **Add Version Info**
**Problem:** Script doesn't identify itself.

**Suggested fix:**
```powershell
$ScriptVersion = "2.0"
$ScriptAuthor = "Your Name"

# In help:
<#
.VERSION
    2.0 - Added interactive mode, config persistence, improvements to error handling
#>

# Command to show version:
if ($Version) {
    Write-Output "Trickplay_Cleanup v$ScriptVersion"
    exit 0
}
```

#### 15. **Add Comment-Based Help for All Functions**
**Problem:** Helper functions lack documentation.

**Suggested fix:**
```powershell
<#
.SYNOPSIS
    Tests if a directory contains media files of specified extensions.

.PARAMETER Path
    Directory to scan recursively.

.PARAMETER Extensions
    Array of file extensions (lowercase, including dot).

.OUTPUTS
    [bool] True if at least one matching file exists, else false.
#>
function Test-HasMediaFile { ... }
```

---

## Summary Table

| Issue | Severity | Category | Effort |
|-------|----------|----------|--------|
| Missing Write-Log error handling | Critical | Error Handling | Low |
| No log directory creation | Critical | Error Handling | Low |
| No root path validation | High | Input Validation | Low |
| No dry-run/whatif mode | High | Safety | Medium |
| No summary statistics | High | UX | Medium |
| Recursive attribute clearing | Medium | Safety | Low |
| No recursion limit on media search | Medium | Performance | Medium |
| No progress indicator | Medium | UX | Low |
| No exclusion patterns | Medium | Flexibility | Medium |
| Hardcoded media extensions | Medium | Maintainability | Low |
| No execution time tracking | Low | UX | Low |
| Error messages lack context | Low | Debugging | Low |
| Cleanup logic could be extracted | Low | Code Quality | Low |
| Missing version info | Low | Metadata | Low |
| Missing function help docs | Low | Documentation | Low |

---

## Recommended Implementation Priority

**v2 (Must have):**
- Write-Log error handling + log directory creation
- Root path validation improvements
- WhatIf mode
- Summary statistics

**v2.1 (Should have):**
- Dry-run confirmation
- Progress indicator
- Better error messages with context
- Execution time tracking

**v3 (Nice to have):**
- Media extension customization
- Exclusion/inclusion patterns
- Recursive search depth limit
- Version info command
