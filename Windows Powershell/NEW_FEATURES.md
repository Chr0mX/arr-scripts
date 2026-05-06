# New Features: Interactive Mode + Config Management

## Feature 1: Interactive CLI Interface

### Description
When script is launched **without parameters**, it enters interactive mode instead of failing. User is prompted to:
1. Select library type (Movie or TVShow)
2. Input or select a folder path
3. Configure log file (optional)
4. Run cleanup

### Implementation Approach

#### Detection: CLI Arguments vs Interactive Mode
```powershell
# At script start, check if any parameters were provided
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = $null,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Movie', 'TVShow')]
    [string]$LibraryType = $null,
    
    ...
)

# Determine mode based on parameter presence
$UseCLIMode = $PSBoundParameters.Count -gt 0
$UseInteractiveMode = $PSBoundParameters.Count -eq 0

if ($UseInteractiveMode) {
    # Launch interactive menu
    Invoke-InteractiveMode
} else {
    # Use provided parameters
    Invoke-CLIMode
}
```

#### Interactive Menu Function
```powershell
function Invoke-InteractiveMode {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Trickplay Cleanup v2.0" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Step 1: Select library type
    Write-Host "Select media library type:" -ForegroundColor Yellow
    Write-Host "  1) Movies (flat directory structure)"
    Write-Host "  2) TV Shows (show/season hierarchy)"
    Write-Host ""
    
    $modeChoice = Read-Host "Enter choice (1 or 2)"
    
    if ($modeChoice -eq "1") {
        $selectedLibraryType = "Movie"
    } elseif ($modeChoice -eq "2") {
        $selectedLibraryType = "TVShow"
    } else {
        Write-Host "Invalid choice. Exiting." -ForegroundColor Red
        exit 1
    }
    
    # Load config to check for saved paths
    $config = Get-Configuration
    $savedPath = $config.libraries[$selectedLibraryType].rootPath
    
    # Step 2: Select folder path
    $selectedPath = Select-FolderPath -LibraryType $selectedLibraryType -SavedPath $savedPath
    
    # Step 3: Optional log file
    $logFile = Read-Host "Enter log file path (press Enter to skip)"
    if ([string]::IsNullOrWhiteSpace($logFile)) { $logFile = $null }
    
    # Step 4: Display summary and confirm
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Library Type: $selectedLibraryType"
    Write-Host "  Root Path: $selectedPath"
    Write-Host "  Log File: $(if ($logFile) { $logFile } else { 'None' })"
    Write-Host ""
    
    $confirm = Read-Host "Proceed with cleanup? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Cancelled by user." -ForegroundColor Yellow
        exit 0
    }
    
    # Save selections to config for next time
    Save-ConfigurationPreference -LibraryType $selectedLibraryType -Path $selectedPath -LogFile $logFile
    
    # Execute cleanup
    Invoke-Cleanup -Root $selectedPath -LibraryType $selectedLibraryType -LogFile $logFile -Interactive
}
```

---

## Feature 2: Folder Selection with Validation

### Description
Interactive folder picker that validates path exists and offers suggestions from config.

#### Implementation
```powershell
function Select-FolderPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType,
        
        [Parameter(Mandatory = $false)]
        [string]$SavedPath = $null
    )
    
    Write-Host ""
    Write-Host "Folder Selection:" -ForegroundColor Yellow
    
    # Show saved path if available
    if ($SavedPath -and (Test-Path -LiteralPath $SavedPath -PathType Container)) {
        Write-Host "  Last used: $SavedPath"
        Write-Host "  1) Use saved path"
        Write-Host "  2) Enter new path"
        Write-Host ""
        
        $choice = Read-Host "Enter choice (1 or 2)"
        
        if ($choice -eq "1") {
            return $SavedPath
        }
    }
    
    # Prompt for new path
    Write-Host "  Enter the full path to your $LibraryType library:"
    while ($true) {
        $userPath = Read-Host "  Path"
        
        # Normalize path
        $userPath = $userPath.Trim('"', "'", '\', '/')
        
        # Validate
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            Write-Host "  Path cannot be empty. Try again." -ForegroundColor Red
            continue
        }
        
        if (-not (Test-Path -LiteralPath $userPath -PathType Container)) {
            Write-Host "  Path not found or not accessible: $userPath" -ForegroundColor Red
            Write-Host "  Try again or enter a different path." -ForegroundColor Yellow
            continue
        }
        
        # Test read permissions
        try {
            Get-ChildItem -LiteralPath $userPath -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "  No read permission on path: $userPath" -ForegroundColor Red
            continue
        }
        
        return $userPath
    }
}
```

---

## Feature 3: Persistent Configuration

### Description
Configuration stored as JSON in same directory as script. Auto-loads on startup, auto-saves when updated.

#### Config File Location
```
Same directory as script:
  C:\Scripts\Trickplay_Cleanup_v2.ps1
  C:\Scripts\trickplay_config.json  ← Config lives here
```

#### Load Configuration
```powershell
function Get-Configuration {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $null
    )
    
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "trickplay_config.json"
    }
    
    # If config doesn't exist, create default
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $defaultConfig = @{
            version = "1.0"
            lastUpdated = (Get-Date -AsUTC).ToString("o")
            lastSelectedMode = "Movie"
            libraries = @{
                Movie = @{
                    rootPath = "V:\Movies"
                    logFile = $null
                    lastRunDate = $null
                    lastRunStats = @{
                        scannedFolders = 0
                        emptyFolders = 0
                        trickplayRemoved = 0
                        trickplayFailed = 0
                    }
                }
                TVShow = @{
                    rootPath = "V:\TV Shows"
                    logFile = $null
                    lastRunDate = $null
                    lastRunStats = @{
                        scannedFolders = 0
                        emptyFolders = 0
                        trickplayRemoved = 0
                        trickplayFailed = 0
                    }
                }
            }
            preferences = @{
                confirmBeforeDelete = $true
                autoBackupConfig = $true
                verbose = $true
            }
        }
        
        Save-Configuration -Config $defaultConfig -ConfigPath $ConfigPath
        return $defaultConfig
    }
    
    # Load existing config
    try {
        $config = Get-Content -LiteralPath $ConfigPath | ConvertFrom-Json
        return $config
    } catch {
        Write-Error "Failed to load config from $ConfigPath : $_"
        exit 1
    }
}
```

#### Save Configuration
```powershell
function Save-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $null
    )
    
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "trickplay_config.json"
    }
    
    try {
        # Backup existing config if preference is enabled
        if ($Config.preferences.autoBackupConfig -and (Test-Path -LiteralPath $ConfigPath)) {
            $backupPath = "$ConfigPath.backup"
            Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
        }
        
        $Config.lastUpdated = (Get-Date -AsUTC).ToString("o")
        
        # Convert to JSON with indentation
        $jsonConfig = $Config | ConvertTo-Json -Depth 10
        
        # Write with proper encoding
        Set-Content -LiteralPath $ConfigPath -Value $jsonConfig -Encoding UTF8 -Force
        
    } catch {
        Write-Error "Failed to save config to $ConfigPath : $_"
    }
}
```

#### Update Saved Preferences
```powershell
function Save-ConfigurationPreference {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType,
        
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile = $null
    )
    
    $config = Get-Configuration
    
    # Update library settings
    $config.libraries[$LibraryType].rootPath = $Path
    if ($LogFile) {
        $config.libraries[$LibraryType].logFile = $LogFile
    }
    
    # Update last used mode
    $config.lastSelectedMode = $LibraryType
    $config.libraries[$LibraryType].lastRunDate = (Get-Date -AsUTC).ToString("o")
    
    Save-Configuration -Config $config
}
```

#### Update Run Statistics
```powershell
function Update-RunStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Stats
    )
    
    $config = Get-Configuration
    
    $config.libraries[$LibraryType].lastRunStats = @{
        scannedFolders = $Stats.ScannedFolders
        emptyFolders = $Stats.EmptyFolders
        trickplayRemoved = $Stats.TrickplayRemoved
        trickplayFailed = $Stats.TrickplayFailed
    }
    
    $config.libraries[$LibraryType].lastRunDate = (Get-Date -AsUTC).ToString("o")
    
    Save-Configuration -Config $config
}
```

---

## Feature 4: Mapping Logic

### Description
Ensures Movie and TVShow folders are kept separate and configurable per-library.

#### Design
```powershell
function Get-LibraryPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Movie', 'TVShow')]
        [string]$LibraryType,
        
        [Parameter(Mandatory = $false)]
        [string]$CustomPath = $null
    )
    
    # If custom path provided, use it
    if ($CustomPath) {
        return $CustomPath
    }
    
    # Otherwise load from config
    $config = Get-Configuration
    $mappedPath = $config.libraries[$LibraryType].rootPath
    
    # Validate it exists
    if (-not (Test-Path -LiteralPath $mappedPath -PathType Container)) {
        Write-Error "Configured path for $LibraryType does not exist: $mappedPath`n  Please reconfigure using interactive mode."
        exit 1
    }
    
    return $mappedPath
}
```

**Benefits:**
- Each library type has independent configuration
- No risk of accidental cross-contamination
- User can have different settings for Movies vs TV
- Config persists between runs

---

## Feature 5: Behavior Rules

### Execution Flow

```powershell
# MAIN ENTRY POINT LOGIC
param(
    [Parameter(Mandatory = $false)]
    [string]$Root = $null,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Movie', 'TVShow')]
    [string]$LibraryType = $null,
    
    [Parameter(Mandatory = $false)]
    [string]$LogFile = $null,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

# Auto-load config on start
$config = Get-Configuration

# Determine execution mode
if ($PSBoundParameters.Count -eq 0) {
    # No arguments: Launch interactive mode
    Invoke-InteractiveMode
} else {
    # Arguments provided: Use CLI mode
    # - Root path is required if not in interactive mode
    if (-not $Root) {
        Write-Error "-Root parameter is required when running in CLI mode (without -Interactive)"
        exit 1
    }
    
    # Apply config defaults if not overridden
    if (-not $LibraryType) {
        $LibraryType = $config.lastSelectedMode
    }
    
    # Execute cleanup
    Invoke-Cleanup -Root $Root -LibraryType $LibraryType -LogFile $LogFile -WhatIf:$WhatIf
}
```

---

## Configuration Examples

### Example 1: First Run (Interactive)
```
User runs: .\Trickplay_Cleanup_v2.ps1 (no arguments)

Output:
  ========================================
    Trickplay Cleanup v2.0
  ========================================

  Select media library type:
    1) Movies (flat directory structure)
    2) TV Shows (show/season hierarchy)

  Enter choice (1 or 2): 1

  Folder Selection:
    Enter the full path to your Movie library:
    Path: V:\Movies

  Enter log file path (press Enter to skip): C:\Logs\trickplay_movies.log

  Summary:
    Library Type: Movie
    Root Path: V:\Movies
    Log File: C:\Logs\trickplay_movies.log

  Proceed with cleanup? (y/n): y

  [Script runs cleanup]
  
  Scan and cleanup complete.
  Summary:
    Scanned: 150 folders
    Empty (no media): 5
    Trickplay removed: 8/8
    Failed: 0
    Completed in 3.24 seconds

  Config saved for next run.
```

### Example 2: Subsequent Run (CLI)
```
User runs: .\Trickplay_Cleanup_v2.ps1
  (or .\Trickplay_Cleanup_v2.ps1 -LibraryType Movie)

Output:
  Loading config...
  Using saved path: V:\Movies
  Using saved log file: C:\Logs\trickplay_movies.log
  
  [Script runs cleanup with saved settings]
```

### Example 3: CLI with Override
```
User runs: .\Trickplay_Cleanup_v2.ps1 -Root "D:\Movies" -LibraryType Movie

Output:
  Using CLI path: D:\Movies
  [Script ignores config, uses provided path]
```

### Example 4: Dry-Run Mode
```
User runs: .\Trickplay_Cleanup_v2.ps1 -WhatIf

Output:
  [WhatIf] Would remove: V:\Movies\Movie1\trickplay
  [WhatIf] Would remove: V:\Movies\Movie5\.trickplay
  [WhatIf] Would remove: V:\TV Shows\Show1\Season1\trickplay
  
  Summary:
    Would scan: 150 folders
    Would process: 5 empty folders
    Would remove: 8 trickplay folders
    No changes made (WhatIf mode)
```

---

## Summary of New Features

| Feature | Benefit | Implementation Complexity |
|---------|---------|--------------------------|
| Interactive Mode | User-friendly, no CLI knowledge needed | Medium |
| Folder Selection | Prevents typos, validates access | Medium |
| Config Persistence | Remember user settings, audit trail | Medium |
| Mapping Logic | Keep libraries separate & organized | Low |
| Behavior Rules | Smart defaults, both CLI and GUI | Low |

**Total Lines of Code Added:** ~400-500 lines
**Estimated Effort:** 2-3 hours
