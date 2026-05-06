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
    2.3 - Interactive settings menu, auto-remove all, simplified UI, GitHub link
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
$ScriptVersion = "2.3"
$ScriptName = "Trickplay_Cleanup"
$GitHubUrl = "https://github.com/Chr0mX/arr-scripts/tree/main/Windows%20Powershell"

# Configuration and log files in same directory as script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "trickplay_config.json"
$DefaultLogFile = Join-Path -Path $ScriptDir -ChildPath "Trickplay_cleanup_log.txt"

# Error handling: pause on any unhandled errors
trap {
    Write-Output ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR OCCURRED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Output ""
    Write-Output "Script execution failed. Press Enter to exit..."
    Read-Host
    exit 1
}

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

# Auto-remove flag: set to true when user confirms in interactive mode
$Script:AutoRemove = $false

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)][object]$InputObject)
    process {
        if ($null -eq $InputObject)                          { return $null }
        if ($InputObject -is [string] -or
            $InputObject -is [ValueType])                    { return $InputObject }
        if ($InputObject -is [System.Collections.IEnumerable]) {
            return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
        }
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $hash
    }
}

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
        # ConvertFrom-Json returns PSCustomObject which is not mutable in PS 5.1.
        # Convert the full object tree to hashtables so properties can be freely set.
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
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
        lastUpdated      = ([datetime]::UtcNow).ToString("o")
        lastSelectedMode = "Movie"
        libraries        = @{
            Movie  = @{
                rootPath    = $null
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
                rootPath    = $null
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

        $Config.lastUpdated = ([datetime]::UtcNow).ToString("o")
        $jsonConfig = $Config | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $ConfigPath -Value $jsonConfig -Encoding UTF8 -Force

    } catch {
        Write-Error "Failed to save config: $_"
    }
}

function Read-ConfigValue {
    # Safely reads a value from either a hashtable or PSCustomObject
    param($Object, [string]$Key, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.ContainsKey($Key)) { return $Object[$Key] } else { return $Default }
    }
    $val = $Object.PSObject.Properties[$Key]
    if ($null -eq $val) { return $Default }
    return $val.Value
}

function Build-LibraryEntry {
    # Builds a fresh hashtable for one library entry, merging existing values
    param($Existing, [string]$NewPath = $null, [string]$NewLogFile = $null, $NewStats = $null)
    $stats = Read-ConfigValue $Existing 'lastRunStats'
    return @{
        rootPath    = if ($NewPath)    { $NewPath }    else { Read-ConfigValue $Existing 'rootPath' }
        logFile     = if ($NewLogFile) { $NewLogFile } else { Read-ConfigValue $Existing 'logFile' }
        lastRunDate = if ($NewStats)   { ([datetime]::UtcNow).ToString("o") } else { Read-ConfigValue $Existing 'lastRunDate' }
        lastRunStats = @{
            scannedFolders   = if ($NewStats) { $NewStats.ScannedFolders }   else { Read-ConfigValue $stats 'scannedFolders'   0 }
            emptyFolders     = if ($NewStats) { $NewStats.EmptyFolders }     else { Read-ConfigValue $stats 'emptyFolders'     0 }
            trickplayRemoved = if ($NewStats) { $NewStats.TrickplayRemoved } else { Read-ConfigValue $stats 'trickplayRemoved' 0 }
            trickplayFailed  = if ($NewStats) { $NewStats.TrickplayFailed }  else { Read-ConfigValue $stats 'trickplayFailed'  0 }
        }
    }
}

function Save-ConfigurationPreference {
    <#
    .SYNOPSIS
        Saves updated folder path and log file for a library type.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$LogFile = $null
    )

    $existing   = Get-Configuration
    $otherType  = if ($LibraryType -eq 'Movie') { 'TVShow' } else { 'Movie' }
    $existingLib  = Read-ConfigValue (Read-ConfigValue $existing 'libraries') $LibraryType
    $otherLib     = Read-ConfigValue (Read-ConfigValue $existing 'libraries') $otherType
    $prefs        = Read-ConfigValue $existing 'preferences'

    $newConfig = @{
        version          = Read-ConfigValue $existing 'version' '1.0'
        lastUpdated      = ([datetime]::UtcNow).ToString("o")
        lastSelectedMode = $LibraryType
        libraries        = @{
            $LibraryType = Build-LibraryEntry $existingLib -NewPath $Path -NewLogFile $LogFile
            $otherType   = Build-LibraryEntry $otherLib
        }
        preferences      = @{
            confirmBeforeDelete = Read-ConfigValue $prefs 'confirmBeforeDelete' $true
            autoBackupConfig    = Read-ConfigValue $prefs 'autoBackupConfig'    $true
            verbose             = Read-ConfigValue $prefs 'verbose'             $true
        }
    }

    Save-Configuration -Config $newConfig
}

function Update-RunStatistics {
    <#
    .SYNOPSIS
        Saves run statistics for a library type into the config.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LibraryType
    )

    $existing  = Get-Configuration
    $otherType = if ($LibraryType -eq 'Movie') { 'TVShow' } else { 'Movie' }
    $existingLib = Read-ConfigValue (Read-ConfigValue $existing 'libraries') $LibraryType
    $otherLib    = Read-ConfigValue (Read-ConfigValue $existing 'libraries') $otherType
    $prefs       = Read-ConfigValue $existing 'preferences'

    $newConfig = @{
        version          = Read-ConfigValue $existing 'version' '1.0'
        lastUpdated      = ([datetime]::UtcNow).ToString("o")
        lastSelectedMode = Read-ConfigValue $existing 'lastSelectedMode' $LibraryType
        libraries        = @{
            $LibraryType = Build-LibraryEntry $existingLib -NewStats $Script:Stats
            $otherType   = Build-LibraryEntry $otherLib
        }
        preferences      = @{
            confirmBeforeDelete = Read-ConfigValue $prefs 'confirmBeforeDelete' $true
            autoBackupConfig    = Read-ConfigValue $prefs 'autoBackupConfig'    $true
            verbose             = Read-ConfigValue $prefs 'verbose'             $true
        }
    }

    Save-Configuration -Config $newConfig
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

    Write-Host ""
    Write-Host "Folder path for $LibraryType library:" -ForegroundColor Yellow

    # Offer saved path only if it exists on disk
    if ($SavedPath -and (Test-Path -LiteralPath $SavedPath -PathType Container)) {
        Write-Host "  Last used: $SavedPath"
        Write-Host "  1) Use saved path"
        Write-Host "  2) Enter a different path"
        Write-Host ""

        $choice = Read-Host "  Choice (1 or 2)"

        if ($choice -eq "1") {
            return $SavedPath
        }
    }

    # Prompt for path — paste-friendly
    Write-Host ""
    Write-Host "  Paste or type the full folder path:"
    Write-Host "  (You can copy the path from Explorer's address bar and paste it here)"
    Write-Host ""

    while ($true) {
        $userPath = Read-Host "  Path"

        # Strip surrounding quotes that Explorer/cmd add when copying paths with spaces
        $userPath = $userPath.Trim()
        if (($userPath.StartsWith('"') -and $userPath.EndsWith('"')) -or
            ($userPath.StartsWith("'") -and $userPath.EndsWith("'"))) {
            $userPath = $userPath.Substring(1, $userPath.Length - 2)
        }

        # Remove trailing slash only (preserve leading \\ for UNC paths)
        $userPath = $userPath.TrimEnd('\', '/')

        if ([string]::IsNullOrWhiteSpace($userPath)) {
            Write-Host "  [!] Path cannot be empty. Try again." -ForegroundColor Red
            continue
        }

        if (-not (Test-RootPath -RootPath $userPath)) {
            Write-Host "  [!] Folder not found or not accessible. Check the path and try again." -ForegroundColor Yellow
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
        Removes trickplay folder with error handling. Auto-removes when user confirms cleanup.
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

    # In interactive mode with confirmation, we auto-remove all (no per-item confirmation)
    # In -Force mode, we also auto-remove all
    # Otherwise, ask for confirmation (CLI mode without -Force)
    if (-not ($Script:AutoRemove -or $Force)) {
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
    $modeText = if ($WhatIf) { 'WhatIf (no changes will be made)' } else { 'Live' }
    Write-Log "Mode: $modeText"
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
    $modeText = if ($WhatIf) { 'WhatIf (no changes will be made)' } else { 'Live' }
    Write-Log "Mode: $modeText"
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
# SETTINGS MENU
# ============================================================================

function Invoke-SettingsMenu {
    <#
    .SYNOPSIS
        Displays and allows user to modify preferences.
    #>
    try {
        $config = Get-Configuration
        $prefs = Read-ConfigValue $config 'preferences' @{}

        while ($true) {
            Write-Output ""
            Write-Host "Settings:" -ForegroundColor Cyan
            Write-Output ""
            Write-Output "  Verbose: $(Read-ConfigValue $prefs 'verbose' $true)"
            Write-Output "  1) Toggle Verbose"
            Write-Output ""
            Write-Output "  Confirm Before Delete: $(Read-ConfigValue $prefs 'confirmBeforeDelete' $true)"
            Write-Output "  2) Toggle Confirm Before Delete"
            Write-Output ""
            Write-Output "  Auto Backup Config: $(Read-ConfigValue $prefs 'autoBackupConfig' $true)"
            Write-Output "  3) Toggle Auto Backup Config"
            Write-Output ""
            Write-Output "  0) Go Back"
            Write-Output ""
            Write-Host "  $GitHubUrl" -ForegroundColor DarkGray
            Write-Output ""

            $choice = Read-Host "Enter choice (0-3)"

            if ($choice -eq "0") {
                Write-Output "Returning to main menu..."
                return
            } elseif ($choice -eq "1") {
                $prefs.verbose = -not (Read-ConfigValue $prefs 'verbose' $true)
                $config.preferences = $prefs
                Save-Configuration -Config $config
                Write-Host "Verbose set to: $($prefs.verbose)" -ForegroundColor Green
            } elseif ($choice -eq "2") {
                $prefs.confirmBeforeDelete = -not (Read-ConfigValue $prefs 'confirmBeforeDelete' $true)
                $config.preferences = $prefs
                Save-Configuration -Config $config
                Write-Host "Confirm Before Delete set to: $($prefs.confirmBeforeDelete)" -ForegroundColor Green
            } elseif ($choice -eq "3") {
                $prefs.autoBackupConfig = -not (Read-ConfigValue $prefs 'autoBackupConfig' $true)
                $config.preferences = $prefs
                Save-Configuration -Config $config
                Write-Host "Auto Backup Config set to: $($prefs.autoBackupConfig)" -ForegroundColor Green
            } else {
                Write-Host "Invalid choice. Try again." -ForegroundColor Red
            }
        }
    } catch {
        Write-Output ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Output ""
        Write-Output "Press Enter to return to menu..."
        Read-Host
    }
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

function Invoke-InteractiveMode {
    <#
    .SYNOPSIS
        Launches interactive menu for user to select library and options.
        Allows pressing Enter to use saved config values if available.
    #>
    try {
        Write-Output ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  $ScriptName v$ScriptVersion" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Output ""

        # Load saved config
        $config = Get-Configuration
        $savedMode = Read-ConfigValue $config 'lastSelectedMode' $null

        # Step 1: Select library type (or use saved)
        if ($savedMode -and ($savedMode -eq 'Movie' -or $savedMode -eq 'TVShow')) {
            Write-Host "Library type:" -ForegroundColor Yellow
            Write-Output "  Saved: $savedMode"
            Write-Output "  1) Movies"
            Write-Output "  2) TV Shows"
            Write-Output "  3) Settings"
            Write-Output ""
            Write-Output "  0) Go Back"
            Write-Output ""

            $modeChoice = Read-Host "Enter choice or press Enter"

            if ([string]::IsNullOrWhiteSpace($modeChoice)) {
                $selectedLibraryType = $savedMode
                Write-Output "Using saved: $savedMode"
            } elseif ($modeChoice -eq "1") {
                $selectedLibraryType = "Movie"
            } elseif ($modeChoice -eq "2") {
                $selectedLibraryType = "TVShow"
            } elseif ($modeChoice -eq "3") {
                Invoke-SettingsMenu
                return
            } elseif ($modeChoice -eq "0") {
                Write-Output "Returning to main menu..."
                return
            } else {
                Write-Host "Invalid choice. Try again." -ForegroundColor Red
                Invoke-InteractiveMode
                return
            }
        } else {
            Write-Host "Select media library type:" -ForegroundColor Yellow
            Write-Output "  1) Movies"
            Write-Output "  2) TV Shows"
            Write-Output "  3) Settings"
            Write-Output ""
            Write-Output "  0) Go Back"
            Write-Output ""

            $modeChoice = Read-Host "Enter choice (1, 2, 3, or 0)"

            if ($modeChoice -eq "1") {
                $selectedLibraryType = "Movie"
            } elseif ($modeChoice -eq "2") {
                $selectedLibraryType = "TVShow"
            } elseif ($modeChoice -eq "3") {
                Invoke-SettingsMenu
                return
            } elseif ($modeChoice -eq "0") {
                Write-Output "Exiting..."
                exit 0
            } else {
                Write-Host "Invalid choice. Try again." -ForegroundColor Red
                Invoke-InteractiveMode
                return
            }
        }

        Write-Output ""

        # Step 2: Select folder path (or auto-use saved if available)
        $libraries   = Read-ConfigValue $config 'libraries' @{}
        $savedLib    = Read-ConfigValue $libraries $selectedLibraryType @{}
        $savedPath   = Read-ConfigValue $savedLib 'rootPath'

        # If we have a saved path, use it directly without prompting
        if ($savedPath -and (Test-Path -LiteralPath $savedPath -PathType Container)) {
            $selectedPath = $savedPath
            Write-Output "Using saved path: $selectedPath"
        } else {
            $selectedPath = Select-FolderPath -LibraryType $selectedLibraryType -SavedPath $savedPath
        }

        # Step 3: Optional log file (auto-use saved, default to script directory)
        Write-Output ""
        $savedLogFile = Read-ConfigValue $savedLib 'logFile'
        if ($savedLogFile) {
            # Auto-use saved log file, but show it so user knows
            $selectedLogFile = $savedLogFile
            Write-Output "Using saved log file: $selectedLogFile"
        } else {
            # No saved log file, default to script directory log file
            $selectedLogFile = $DefaultLogFile
            Write-Output "Using default log file: $selectedLogFile"
        }

        # Step 4: Confirm
        Write-Output ""
        Write-Host "Summary:" -ForegroundColor Cyan
        Write-Output "  Library Type: $selectedLibraryType"
        Write-Output "  Root Path: $selectedPath"
        Write-Output "  Log File: $(if ($selectedLogFile) { $selectedLogFile } else { 'None' })"
        Write-Output ""

        $confirm = Read-Host "Proceed with cleanup? (y/n, default is y)"
        if ([string]::IsNullOrWhiteSpace($confirm)) {
            $confirm = 'y'
        }
        if ($confirm -ne 'y') {
            Write-Host "Cancelled by user." -ForegroundColor Yellow
            exit 0
        }

        # Save preferences
        Save-ConfigurationPreference -LibraryType $selectedLibraryType -Path $selectedPath -LogFile $selectedLogFile

        # Set flag to auto-remove all trickplay folders without per-item confirmation
        $Script:AutoRemove = $true

        # Execute cleanup
        $script:LogFile = $selectedLogFile
        Ensure-LogDirectory
        Write-Log "Trickplay_Cleanup v$ScriptVersion started in interactive mode"
        Invoke-Cleanup -Root $selectedPath -Type $selectedLibraryType
        Write-Log "Cleanup completed."
    } catch {
        Write-Output ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Output ""
        Write-Output "Press Enter to exit..."
        Read-Host
        exit 1
    }
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

try {
    # Determine execution mode: check if Root was explicitly provided (not just defaulted)
    $isInteractiveMode = -not $PSBoundParameters.ContainsKey('Root')

    if ($isInteractiveMode) {
        # Interactive mode (no -Root parameter provided)
        Invoke-InteractiveMode
    } else {
        # CLI mode (Root parameter provided)
        if ([string]::IsNullOrWhiteSpace($Root)) {
            Write-Error "-Root parameter cannot be empty when running in CLI mode" -ErrorAction Stop
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
} catch {
    Write-Output ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Output ""
    Write-Output "Press Enter to exit..."
    Read-Host
    exit 1
}
