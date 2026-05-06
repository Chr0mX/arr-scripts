$Root = "V:\Movies"

# Extensions that count as "media exists"
$MediaExtensions = @(
    ".mkv", ".mp4", ".m4v", ".mov", ".avi", ".wmv",
    ".mpg", ".mpeg", ".ts", ".m2ts", ".mts", ".vob",
    ".webm", ".flv", ".3gp"
)

# Function to safely check if any media file exists
function Has-MediaFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string[]]$Extensions
    )

    try {
        return [bool](
            Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction Stop |
                Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
                Select-Object -First 1
        )
    } catch {
        # Ignore folders/files with invalid characters
        return $false
    }
}

# Get all movie folders (each folder = one movie)
Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
    $MovieFolder = $_

    $HasMedia = Has-MediaFile -Path $MovieFolder.FullName -Extensions $MediaExtensions

    if (-not $HasMedia) {
        $TrickplayFolders = @()

        # *.trickplay folders
        $TrickplayFolders += Get-ChildItem -LiteralPath $MovieFolder.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*.trickplay" }

        # plain "trickplay" folder
        $TrickplayFolders += Get-ChildItem -LiteralPath $MovieFolder.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq "trickplay" }

        $TrickplayFolders = $TrickplayFolders | Where-Object { $_ } | Select-Object -Unique

        if ($TrickplayFolders.Count -gt 0) {
            Write-Output "$($MovieFolder.FullName) - No media found. Removing trickplay folders..."

            foreach ($Folder in $TrickplayFolders) {
                try {
                    # Clear read-only / hidden attributes
                    Get-ChildItem -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.Attributes = 'Normal' }

                    # Remove the folder
                    Remove-Item -LiteralPath $Folder.FullName -Recurse -Force -ErrorAction Stop
                    Write-Output "Removed: $($Folder.FullName)"
                } catch {
                    Write-Output "Failed to remove: $($Folder.FullName) - $_"
                }
            }
        }
    }
}

Write-Host "Scan and cleanup complete."
Read-Host "Press Enter to exit..."