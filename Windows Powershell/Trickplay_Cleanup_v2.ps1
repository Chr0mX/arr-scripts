#Requires -Version 5.1

<#
.SYNOPSIS
    Removes orphaned trickplay folders from movie or TV show media libraries with interactive mode and persistent config.

.DESCRIPTION
    Scans media library directories and removes trickplay metadata folders from directories that contain
    no actual media files. Supports both flat movie library structures and hierarchical TV show library structures.

    Features:
    - Interactive mode when launched without arguments
    - Persistent configuration with folder path mapping
    - WhatIf (dry-run) mode for preview before deletion
    - Confirmation prompts before removal
    - Comprehensive logging and statistics
    - CLI mode for automation and Task Scheduler

.PARAMETER Root
    Root path of the media library. When specified, runs in CLI mode instead of interactive mode.

.PARAMETER LibraryType
    Type of media library structure: 'Movie' (flat) or 'TVShow' (show/season hierarchy).
    Defaults to last selected mode from config, or 'Movie' if config doesn't exist.

.PARAMETER LogFile
    Optional path to a log file. When specified, output is written there in addition to the console.

.PARAMETER WhatIf
    Preview deletions without actually removing folders. Useful to verify script behavior.

.PARAMETER Force
    Skip confirmation prompts before deletion. Use with caution.

.EXAMPLE
    .\Trickplay_Cleanup_v2.ps1
    Launches interactive mode to select library and folder.

.EXAMPLE
    .\Trickplay_Cleanup_v2.ps1 -Root "V:\Movies" -LibraryType Movie
    CLI mode: cleanup movies using command-line parameters.

.EXAMPLE
    .\Trickplay_Cleanup_v2.ps1 -Root "V:\TV Shows" -LibraryType TVShow -WhatIf
    Preview what would be deleted without making changes.

.VERSION
    2.0 - Added interactive mode, config persistence, WhatIf mode, improved error handling, statistics
#>

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
    [switch]$Force
)

# Script metadata
$ScriptVersion = "2.0"
$ScriptName = "Trickplay_Cleanup"

# Configuration file in same directory as script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "trickplay_config.json"

# Default media extensions
$DefaultMediaExtensions = @(
    ".mkv", ".mp4", ".m4v", ".mov", ".avi", ".wmv",
    ".mpg", ".mpeg", ".ts", ".m2ts", ".mts", ".vob",
    ".webm", ".flv", ".3gp"
)

# Statistics tracking
$Script:Stats = @{
    ScannedFolders    = 0
    EmptyFolders      = 0
    TrickplayFound    = 0
    TrickplayRemoved  = 0
    TrickplaySkipped  = 0
    TrickplayFailed   = 0
}

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

function Get-Configuration {
    <#
    .SYNOPSIS
        Loads configuration from JSON file, creating defaults if needed.
    #>
    param([string]$ConfigPath = $ConfigFilePath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return New-DefaultConfiguration -ConfigPath $ConfigPath
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        return $config
    } catch {
        Write-Error "Failed to load config from $ConfigPath : $_"
        exit 1
    }
}

function New-DefaultConfiguration {
    <#
    .SYNOPSIS
        Creates and saves a default configuration.
    #>
    param([string]$ConfigPath = $ConfigFilePath)

    $default = @{
        version          = "1.0"
        lastUpdated      = (Get-Date -AsUTC).ToString("o")
        lastSelectedMode = "Movie"
        libraries        = @{
            Movie  = @{
                rootPath    = "V:\Movies"
                logFile     = $null
                lastRunDate = $null
                lastRunStats = @{
                    scannedFolders   = 0
                    emptyFolders     = 0
                    trickplayRemoved = 0
                    trickplayFailed  = 0
                }
            }
            TVShow = @{
                rootPath    = "V:\TV Shows"
                logFile     = $null
                lastRunDate = $null
                lastRunStats = @{
                    scannedFolders   = 0
                    emptyFolders     = 0
                    trickplayRemoved = 0
                    trickplayFailed  = 0
                }
            }
        }
        preferences      = @{
            confirmBeforeDelete = $true
            autoBackupConfig    = $true
            verbose             = $true
        }
    }

    Save-Configuration -Config $default -ConfigPath $ConfigPath
    return $default
}

function Save-Configuration {
    <#
    .SYNOPSIS
        Saves configuration to JSON file with optional backup.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [string]$ConfigPath = $ConfigFilePath
    )

    try {
        # Backup existing config
        if ($Config.preferences.autoBackupConfig -and (Test-Path -LiteralPath $ConfigPath)) {
            $backupPath = "$ConfigPath.backup"
            Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
        }

        $Config.lastUpdated = (Get-Date -AsUTC).ToString("o")
        $jsonConfig = $Config | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $ConfigPath -Value $jsonConfig -Encoding UTF8 -Force

    } catch {
        Write-Error "Failed to save config: $_"
    }
}

function Save-ConfigurationPreference {
    <#
    .SYNOPSIS
        Updates and saves user preferences to config.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$LogFile = $null
    )

    $config = Get-Configuration
    $config.libraries[$LibraryType].rootPath = $Path
    if ($LogFile) {
        $config.libraries[$LibraryType].logFile = $LogFile
    }
    $config.lastSelectedMode = $LibraryType
    Save-Configuration -Config $config
}

function Update-RunStatistics {
    <#
    .SYNOPSIS
        Updates config with run statistics.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType
    )

    $config = Get-Configuration
    $config.libraries[$LibraryType].lastRunStats = @{
        scannedFolders   = $Script:Stats.ScannedFolders
        emptyFolders     = $Script:Stats.EmptyFolders
        trickplayRemoved = $Script:Stats.TrickplayRemoved
        trickplayFailed  = $Script:Stats.TrickplayFailed
    }
    $config.libraries[$LibraryType].lastRunDate = (Get-Date -AsUTC).ToString("o")
    Save-Configuration -Config $config
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes message to console and optionally to log file with timestamp.
    #>
    param([string]$Message)

    Write-Output $Message

    if ($LogFile) {
        try {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -LiteralPath $LogFile -Value "[$timestamp] $Message" -ErrorAction Stop
        } catch {
            Write-Error "Failed to write to log file '$LogFile': $_" -ErrorAction Continue
        }
    }
}

function Ensure-LogDirectory {
    <#
    .SYNOPSIS
        Creates log directory if it doesn't exist.
    #>
    if (-not $LogFile) { return }

    $LogDir = Split-Path -Parent $LogFile
    if (-not (Test-Path -LiteralPath $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            Write-Log "Created log directory: $LogDir"
        } catch {
            Write-Error "Cannot create log directory '$LogDir': $_"
            exit 1
        }
    }
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function Test-RootPath {
    <#
    .SYNOPSIS
        Validates that root path exists and is accessible.
    #>
    param([string]$RootPath)

    # Normalize path
    $RootPath = $RootPath.TrimEnd('\', '/')

    # Check existence
    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        Write-Error "Root path not found or is not a directory: $RootPath"
        return $false
    }

    # Check read permissions
    try {
        Get-ChildItem -LiteralPath $RootPath -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "No read permission on root path: $RootPath - $_"
        return $false
    }

    return $true
}

function Select-FolderPath {
    <#
    .SYNOPSIS
        Interactive folder selection with validation and saved path option.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType,

        [string]$SavedPath = $null
    )

    Write-Output ""
    Write-Output "Folder Selection:" -ForegroundColor Yellow

    # Show saved path option
    if ($SavedPath -and (Test-Path -LiteralPath $SavedPath -PathType Container)) {
        Write-Output "  Last used: $SavedPath"
        Write-Output "  1) Use saved path"
        Write-Output "  2) Enter new path"
        Write-Output ""

        $choice = Read-Host "  Enter choice (1 or 2)"

        if ($choice -eq "1") {
            return $SavedPath
        }
    }

    # Prompt for new path
    Write-Output ""
    Write-Output "  Enter the full path to your $LibraryType library:"

    while ($true) {
        $userPath = Read-Host "  Path"

        # Normalize
        $userPath = $userPath.Trim('"', "'", '\', '/')

        if ([string]::IsNullOrWhiteSpace($userPath)) {
            Write-Output "  [!] Path cannot be empty. Try again." -ForegroundColor Red
            continue
        }

        if (-not (Test-RootPath -RootPath $userPath)) {
            Write-Output "  [!] Try again with a valid path." -ForegroundColor Yellow
            continue
        }

        return $userPath
    }
}

# ============================================================================
# MEDIA FILE DETECTION
# ============================================================================

function Test-HasMediaFile {
    <#
    .SYNOPSIS
        Tests if directory contains media files of specified extensions.
    .OUTPUTS
        [bool] True if at least one matching file exists, else false.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Extensions
    )

    try {
        return [bool](
            Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop |
                Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
                Select-Object -First 1
        )
    } catch {
        return $false
    }
}

# ============================================================================
# TRICKPLAY DETECTION & REMOVAL
# ============================================================================

function Get-TrickplayFolders {
    <#
    .SYNOPSIS
        Finds all trickplay metadata folders matching known patterns.
    .OUTPUTS
        [System.IO.DirectoryInfo[]] Array of trickplay folders, or $null if none found.
    #>
    param([string]$Path)

    Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*.trickplay" -or $_.Name -ieq "trickplay" }
}

function Remove-TrickplayFolder {
    <#
    .SYNOPSIS
        Removes trickplay folder with optional confirmation and error handling.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Folder
    )

    # WhatIf mode
    if ($WhatIf) {
        Write-Log "  [WHATIF] Would remove: $($Folder.FullName)"
        return
    }

    # Ask for confirmation if not -Force
    if (-not $Force) {
        $response = Read-Host "  Remove '$($Folder.Name)'? (y/n)"
        if ($response -ne 'y') {
            Write-Log "  Skipped: $($Folder.FullName)"
            $Script:Stats.TrickplaySkipped++
            return
        }
    }

    # Attempt removal
    try {
        # Clear attributes so removal can proceed
        Get-ChildItem -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }

        Remove-Item -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction Stop
        Write-Log "  Removed: $($Folder.FullName)"
        $Script:Stats.TrickplayRemoved++

    } catch {
        Write-Log "  [ERROR] Failed to remove: $($Folder.FullName)"
        Write-Log "    Reason: $($_.Exception.Message)"

        if ($_.Exception.Message -match 'permission|denied|access') {
            Write-Log "    Hint: Check folder permissions or that it's not in use"
        }

        $Script:Stats.TrickplayFailed++
    }
}

function Invoke-TrickplayCleanup {
    <#
    .SYNOPSIS
        Scans a single folder for trickplay metadata and removes it if no media exists.
    #>
    param([string]$ScanPath)

    $Script:Stats.ScannedFolders++

    if (-not (Test-HasMediaFile -Path $ScanPath -Extensions $DefaultMediaExtensions)) {
        $TrickplayFolders = @(Get-TrickplayFolders -Path $ScanPath)

        if ($TrickplayFolders.Count -gt 0) {
            $Script:Stats.EmptyFolders++
            $Script:Stats.TrickplayFound += $TrickplayFolders.Count

            Write-Log "$ScanPath - No media found. Removing trickplay folders..."
            foreach ($Folder in $TrickplayFolders) {
                Remove-TrickplayFolder -Folder $Folder
            }
        }
    }
}

# ============================================================================
# CLEANUP ORCHESTRATION
# ============================================================================

function Invoke-MovieCleanup {
    <#
    .SYNOPSIS
        Scans movie library (flat structure) for orphaned trickplay folders.
    #>
    param([string]$Root)

    Write-Log "Scanning Movie library: $Root"
    Write-Log "Mode: $($WhatIf ? 'WhatIf (no changes will be made)' : 'Live')"
    Write-Log ""

    $folders = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue
    $totalCount = @($folders).Count

    if ($totalCount -eq 0) {
        Write-Log "No folders found in: $Root"
        return
    }

    $current = 0
    foreach ($folder in $folders) {
        $current++
        Write-Progress -Activity "Scanning movie library" -Status $folder.Name -PercentComplete (($current / $totalCount) * 100)
        Invoke-TrickplayCleanup -ScanPath $folder.FullName
    }

    Write-Progress -Activity "Scanning movie library" -Completed
}

function Invoke-TVShowCleanup {
    <#
    .SYNOPSIS
        Scans TV show library (show/season hierarchy) for orphaned trickplay folders.
    #>
    param([string]$Root)

    Write-Log "Scanning TV Show library: $Root"
    Write-Log "Mode: $($WhatIf ? 'WhatIf (no changes will be made)' : 'Live')"
    Write-Log ""

    $shows = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue
    $totalCount = 0

    # Count total for progress bar
    foreach ($show in $shows) {
        $totalCount += @(Get-ChildItem -LiteralPath $show.FullName -Directory -ErrorAction SilentlyContinue).Count
    }

    if ($totalCount -eq 0) {
        Write-Log "No shows/seasons found in: $Root"
        return
    }

    $current = 0
    foreach ($show in $shows) {
        $seasons = Get-ChildItem -LiteralPath $show.FullName -Directory -ErrorAction SilentlyContinue

        foreach ($season in $seasons) {
            $current++
            Write-Progress -Activity "Scanning TV library" -Status "$($show.Name) / $($season.Name)" -PercentComplete (($current / $totalCount) * 100)
            Invoke-TrickplayCleanup -ScanPath $season.FullName
        }
    }

    Write-Progress -Activity "Scanning TV library" -Completed
}

function Invoke-Cleanup {
    <#
    .SYNOPSIS
        Main cleanup orchestrator.
    #>
    param(
        [string]$Root,
        [string]$Type
    )

    $startTime = Get-Date

    if ($Type -eq 'Movie') {
        Invoke-MovieCleanup -Root $Root
    } else {
        Invoke-TVShowCleanup -Root $Root
    }

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    # Display summary
    Write-Log ""
    Write-Log "Summary:"
    Write-Log "  Scanned folders: $($Script:Stats.ScannedFolders)"
    Write-Log "  Empty folders (no media): $($Script:Stats.EmptyFolders)"

    if ($WhatIf) {
        Write-Log "  Would remove: $($Script:Stats.TrickplayRemoved) trickplay folders"
    } else {
        Write-Log "  Removed: $($Script:Stats.TrickplayRemoved)/$($Script:Stats.TrickplayFound) trickplay folders"
        Write-Log "  Failed: $($Script:Stats.TrickplayFailed)"
    }

    Write-Log "  Skipped: $($Script:Stats.TrickplaySkipped)"
    Write-Log "  Duration: $([math]::Round($duration, 2)) seconds"
    Write-Log ""

    if (-not $WhatIf) {
        Update-RunStatistics -LibraryType $Type
    }
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

function Invoke-InteractiveMode {
    <#
    .SYNOPSIS
        Launches interactive menu for user to select library and options.
    #>
    Write-Output ""
    Write-Output "========================================" -ForegroundColor Cyan
    Write-Output "  $ScriptName v$ScriptVersion" -ForegroundColor Cyan
    Write-Output "========================================" -ForegroundColor Cyan
    Write-Output ""

    # Load saved config
    $config = Get-Configuration

    # Step 1: Select library type
    Write-Output "Select media library type:" -ForegroundColor Yellow
    Write-Output "  1) Movies (flat directory structure)"
    Write-Output "  2) TV Shows (show/season hierarchy)"
    Write-Output ""

    $modeChoice = Read-Host "Enter choice (1 or 2)"

    if ($modeChoice -eq "1") {
        $selectedLibraryType = "Movie"
    } elseif ($modeChoice -eq "2") {
        $selectedLibraryType = "TVShow"
    } else {
        Write-Output "Invalid choice. Exiting." -ForegroundColor Red
        exit 1
    }

    # Step 2: Select folder path
    $savedPath = $config.libraries[$selectedLibraryType].rootPath
    $selectedPath = Select-FolderPath -LibraryType $selectedLibraryType -SavedPath $savedPath

    # Step 3: Optional log file
    Write-Output ""
    $logFileInput = Read-Host "Enter log file path (press Enter to skip)"
    if ([string]::IsNullOrWhiteSpace($logFileInput)) {
        $selectedLogFile = $null
    } else {
        $selectedLogFile = $logFileInput
    }

    # Step 4: Confirm
    Write-Output ""
    Write-Output "Summary:" -ForegroundColor Cyan
    Write-Output "  Library Type: $selectedLibraryType"
    Write-Output "  Root Path: $selectedPath"
    Write-Output "  Log File: $(if ($selectedLogFile) { $selectedLogFile } else { 'None' })"
    Write-Output ""

    $confirm = Read-Host "Proceed with cleanup? (y/n)"
    if ($confirm -ne 'y') {
        Write-Output "Cancelled by user." -ForegroundColor Yellow
        exit 0
    }

    # Save preferences
    Save-ConfigurationPreference -LibraryType $selectedLibraryType -Path $selectedPath -LogFile $selectedLogFile

    # Execute cleanup
    $script:LogFile = $selectedLogFile
    Ensure-LogDirectory
    Write-Log "Trickplay_Cleanup v$ScriptVersion started in interactive mode"
    Invoke-Cleanup -Root $selectedPath -Type $selectedLibraryType
    Write-Log "Cleanup completed."
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

# Determine execution mode: check if Root was explicitly provided (not just defaulted)
$isInteractiveMode = -not $PSBoundParameters.ContainsKey('Root')

if ($isInteractiveMode) {
    # Interactive mode (no -Root parameter provided)
    Invoke-InteractiveMode
} else {
    # CLI mode (Root parameter provided)
    if ([string]::IsNullOrWhiteSpace($Root)) {
        Write-Error "-Root parameter cannot be empty when running in CLI mode"
        exit 1
    }

    if (-not $LibraryType) {
        $config = Get-Configuration
        $LibraryType = $config.lastSelectedMode
    }

    # Validate root path
    if (-not (Test-RootPath -RootPath $Root)) {
        exit 1
    }

    # Prepare logging
    $script:LogFile = $LogFile
    Ensure-LogDirectory

    Write-Log "Trickplay_Cleanup v$ScriptVersion started in CLI mode"
    Write-Log "Library Type: $LibraryType"
    Write-Log "Root Path: $Root"
    if ($LogFile) { Write-Log "Log File: $LogFile" }
    if ($WhatIf) { Write-Log "Mode: WhatIf (no changes)" }
    Write-Log ""

    # Execute cleanup
    Invoke-Cleanup -Root $Root -Type $LibraryType

    Write-Log "Cleanup completed."
}
