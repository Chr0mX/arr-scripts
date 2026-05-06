$Root = "V:\TV Shows"

# Function to safely check if .mkv exists
function Has-MKV {
    param($Path)
    try {
        Get-ChildItem -Path $Path -File -Recurse -ErrorAction Stop | Where-Object { $_.Extension -ieq ".mkv" }
    } catch {
        # Ignore folders/files with invalid characters
        return $null
    }
}

# Get all show folders
Get-ChildItem -Path $Root -Directory | ForEach-Object {
    $ShowFolder = $_

    # Get all season folders
    Get-ChildItem -Path $ShowFolder.FullName -Directory | ForEach-Object {
        $SeasonFolder = $_

        $HasMKV = Has-MKV $SeasonFolder.FullName

        if (-not $HasMKV) {
            $TrickplayType = $null
            $TrickplayFolder = $null

            # Check for .trickplay folders
            $DotTrickplay = Get-ChildItem -Path $SeasonFolder.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*.trickplay" }
            if ($DotTrickplay) {
                $TrickplayType = ".trickplay"
                $TrickplayFolder = $DotTrickplay
            } else {
                # Check for plain trickplay folder
                $PlainTrickplay = Get-ChildItem -Path $SeasonFolder.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq "trickplay" }
                if ($PlainTrickplay) {
                    $TrickplayType = "trickplay"
                    $TrickplayFolder = $PlainTrickplay
                }
            }

            if ($TrickplayType -and $TrickplayFolder) {
                Write-Output "$($SeasonFolder.FullName) - Type: $TrickplayType"

                # Remove the trickplay folder safely
                foreach ($Folder in $TrickplayFolder) {
                    try {
                        # Clear read-only / hidden attributes
                        Get-ChildItem -LiteralPath $Folder.FullName -Recurse -Force | ForEach-Object {
                            $_.Attributes = 'Normal'
                        }

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
}

# Pause at the end
Write-Host "Scan and cleanup complete."
Read-Host "Press Enter to exit..."
