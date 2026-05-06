# Trickplay Cleanup — PowerShell Scripts

Removes orphaned trickplay metadata folders from Plex media libraries when the actual media files are missing. Useful after bulk deletions or library reorganizations that leave behind dangling preview-thumbnail data.

---

## Scripts

| File | Status | Description |
|---|---|---|
| `Movies_trickplay_removal.ps1` | Legacy | Original script for movie libraries |
| `TVshows_trickplay_removal.ps1` | Legacy | Original script for TV show libraries |
| `Trickplay_Cleanup_v1.ps1` | **Current** | Unified, parameterized replacement for both |

> The legacy scripts are kept for reference. Use `Trickplay_Cleanup_v1.ps1` for all new usage.

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Read/write access to the media library path

---

## Usage

### Movie library
```powershell
.\Trickplay_Cleanup_v1.ps1 -Root "V:\Movies" -LibraryType Movie
```

### TV show library
```powershell
.\Trickplay_Cleanup_v1.ps1 -Root "V:\TV Shows" -LibraryType TVShow
```

### With file logging
```powershell
.\Trickplay_Cleanup_v1.ps1 -Root "V:\Movies" -LibraryType Movie -LogFile "C:\Logs\trickplay.log"
```

### Interactive mode (pause before exit)
```powershell
.\Trickplay_Cleanup_v1.ps1 -Root "V:\TV Shows" -LibraryType TVShow -Interactive
```

---

## Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-Root` | String | No | `V:\Movies` | Root path of the media library |
| `-LibraryType` | `Movie` \| `TVShow` | No | `Movie` | Library folder structure to expect |
| `-LogFile` | String | No | _(none)_ | Path to optional log file with timestamps |
| `-Interactive` | Switch | No | _(off)_ | Prompt "Press Enter to exit" at completion |

---

## How It Works

**Movie libraries** (`-LibraryType Movie`):
Each subfolder of `$Root` is treated as one movie. If it contains no media files, any `*.trickplay` or `trickplay` subfolder inside it is deleted.

**TV show libraries** (`-LibraryType TVShow`):
The script descends two levels (`Show > Season`). If a season folder contains no media files, its trickplay subfolders are deleted.

**Trickplay folder patterns matched:**
- `*.trickplay` — dot-prefixed format used by Plex
- `trickplay` — plain folder name (case-insensitive)

**Media extensions recognized:**
`.mkv`, `.mp4`, `.m4v`, `.mov`, `.avi`, `.wmv`, `.mpg`, `.mpeg`, `.ts`, `.m2ts`, `.mts`, `.vob`, `.webm`, `.flv`, `.3gp`

---

## Task Scheduler

To run on a schedule, omit `-Interactive`:

```
Program:   powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Trickplay_Cleanup_v1.ps1" -Root "V:\Movies" -LibraryType Movie -LogFile "C:\Logs\trickplay.log"
```

---

## Changelog

### v1 — `Trickplay_Cleanup_v1.ps1`

**Breaking changes:**
- Replaces `Movies_trickplay_removal.ps1` and `TVshows_trickplay_removal.ps1` with a single unified script
- Library type is now selected via `-LibraryType Movie|TVShow` parameter instead of running a separate file

**Security & safety:**
- Fixed `-Path` → `-LiteralPath` throughout (prevents wildcard injection on paths containing `*`, `?`, or `[]`)
- Added root path validation — script exits early with a clear error if the path does not exist

**New features:**
- `-Root` parameter replaces hardcoded paths
- `-LibraryType` parameter replaces separate script files
- `-LogFile` parameter adds optional timestamped file logging for audit trails
- `-Interactive` switch controls the "Press Enter to exit" prompt — off by default for automation safety

**Performance:**
- Trickplay folder detection consolidated from 2–3 `Get-ChildItem` calls into a single scan with combined filter

**Code quality:**
- `Has-MKV` replaced by `Test-HasMediaFile` — returns explicit `[bool]`, accepts configurable extension list, works for both library types
- `Get-TrickplayFolders`, `Remove-TrickplayFolder`, `Invoke-TrickplayCleanup` helper functions extracted — no duplicated logic between library types
- `Write-Log` function added — single call writes to both console and optional log file
- `Write-Host` replaced with `Write-Output` for pipeline compatibility
- Redundant `Where-Object { $_ }` filter removed
- `#Requires -Version 5.1` added
- Full comment-based help added (`Get-Help .\Trickplay_Cleanup_v1.ps1 -Full`)

---

### Legacy — `Movies_trickplay_removal.ps1` / `TVshows_trickplay_removal.ps1`

Original scripts with hardcoded paths (`V:\Movies`, `V:\TV Shows`). No parameters, no logging, interactive-only. Kept for reference.
