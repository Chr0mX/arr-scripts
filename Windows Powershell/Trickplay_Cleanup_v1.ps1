#Requires -Version 5.1

<#
.SYNOPSIS
    Removes orphaned trickplay folders from movie or TV show media libraries.

.DESCRIPTION
    Scans media library directories and removes trickplay metadata folders from
    directories that contain no actual media files. Supports both flat movie
    library structures and hierarchical TV show library structures.

.PARAMETER Root
    Root path of the media library. Defaults to "V:\Movies".

.PARAMETER LibraryType
    Type of media library structure: 'Movie' (flat) or 'TVShow' (show/season hierarchy).
    Defaults to 'Movie'.

.PARAMETER LogFile
    Optional path to a log file. When specified, output is written there in addition
    to the console.

.PARAMETER Interactive
    When specified, prompts the user to press Enter before the script exits.
    Omit this switch when running via Task Scheduler or other automation.

.EXAMPLE
    .\Trickplay_Cleanup_v1.ps1 -Root "V:\Movies" -LibraryType Movie

.EXAMPLE
    .\Trickplay_Cleanup_v1.ps1 -Root "V:\TV Shows" -LibraryType TVShow -LogFile "C:\Logs\trickplay.log" -Interactive
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Root = "V:\Movies",

    [Parameter(Mandatory = $false)]
    [ValidateSet('Movie', 'TVShow')]
    [string]$LibraryType = 'Movie',

    [Parameter(Mandatory = $false)]
    [string]$LogFile = $null,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

# Extensions that count as "media exists"
$MediaExtensions = @(
    ".mkv", ".mp4", ".m4v", ".mov", ".avi", ".wmv",
    ".mpg", ".mpeg", ".ts", ".m2ts", ".mts", ".vob",
    ".webm", ".flv", ".3gp"
)

function Write-Log {
    param([string]$Message)
    Write-Output $Message
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    }
}

function Test-HasMediaFile {
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

function Get-TrickplayFolders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    # Match both "*.trickplay" (Plex dot-prefixed) and plain "trickplay" folders
    Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*.trickplay" -or $_.Name -ieq "trickplay" }
}

function Remove-TrickplayFolder {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Folder
    )
    try {
        # Clear read-only/hidden attributes so Remove-Item can proceed
        Get-ChildItem -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }

        Remove-Item -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction Stop
        Write-Log "  Removed: $($Folder.FullName)"
    } catch {
        Write-Log "  Failed to remove: $($Folder.FullName) - $_"
    }
}

function Invoke-TrickplayCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanPath
    )
    if (-not (Test-HasMediaFile -Path $ScanPath -Extensions $MediaExtensions)) {
        $TrickplayFolders = Get-TrickplayFolders -Path $ScanPath
        if ($TrickplayFolders) {
            Write-Log "$ScanPath - No media found. Removing trickplay folders..."
            foreach ($Folder in $TrickplayFolders) {
                Remove-TrickplayFolder -Folder $Folder
            }
        }
    }
}

# --- Entry Point ---

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Root path not found or inaccessible: $Root"
    exit 1
}

Write-Log "Starting trickplay cleanup for $LibraryType library: $Root"

if ($LibraryType -eq 'Movie') {
    Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
        Invoke-TrickplayCleanup -ScanPath $_.FullName
    }
} else {
    # TVShow: traverse Show > Season hierarchy
    Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
        $ShowFolder = $_
        Get-ChildItem -LiteralPath $ShowFolder.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Invoke-TrickplayCleanup -ScanPath $_.FullName
        }
    }
}

Write-Log "Scan and cleanup complete."

if ($Interactive) {
    Read-Host "Press Enter to exit..."
}
