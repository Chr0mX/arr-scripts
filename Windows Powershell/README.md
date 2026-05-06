# Trickplay Cleanup — PowerShell Script

Removes orphaned trickplay metadata folders from media libraries when the actual media files are missing. Useful after bulk deletions or library reorganizations that leave behind dangling trickplay metadata (commonly created by Jellyfin/Plex media servers for preview thumbnails).

---

## Scripts

| File | Status | Description |
|---|---|---|
| `Movies_trickplay_removal.ps1` | Legacy | Original script for movie libraries |
| `TVshows_trickplay_removal.ps1` | Legacy | Original script for TV show libraries |
| `Trickplay_Cleanup.ps1` | **Current** | Interactive mode, config persistence, WhatIf, quick-select from saved config |

> **Recommended:** Use `Trickplay_Cleanup.ps1` for all new usage. Automatically remembers your folder and reuses saved settings on subsequent runs.

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Read/write access to the media library path

---

## Usage — Current (Recommended)

### Interactive mode (no arguments)
```powershell
.\Trickplay_Cleanup.ps1
```
Prompts you to select library type, folder path, and logging options. Saves preferences to `trickplay_config.json` for reuse.

**First run:** Answer all prompts, settings are saved.  
**Subsequent runs:** Press Enter at each prompt to use saved values, or type new values to override.

### CLI mode: Movie library
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie
```

### CLI mode: TV show library
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\TV Shows" -LibraryType TVShow
```

### Preview without deleting (WhatIf mode)
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie -WhatIf
```

### Skip confirmation prompts
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie -Force
```

### With file logging
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie -LogFile "C:\Logs\trickplay.log"
```

---

## Usage — v1 (Legacy Alternative)

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

## Parameters (Current)

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-Root` | String | No | _(from config)_ | Root path of the media library. Omit to use interactive mode. |
| `-LibraryType` | `Movie` \| `TVShow` | No | _(last used)_ | Library folder structure. Defaults to last selected mode from config. |
| `-LogFile` | String | No | _(none)_ | Path to optional log file with timestamps. |
| `-WhatIf` | Switch | No | _(off)_ | Preview deletions without making changes. |
| `-Force` | Switch | No | _(off)_ | Skip confirmation prompts before deletion. |

**Configuration file:** `trickplay_config.json` (created automatically in same directory as script)

**Quick-select behavior:**
- First run with no config: All prompts are mandatory
- Subsequent runs: Shows saved values, press Enter to reuse them
- You can always type new values to override saved settings

---

## Parameters (v1 — Legacy)

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-Root` | String | No | `V:\Movies` | Root path of the media library |
| `-LibraryType` | `Movie` \| `TVShow` | No | `Movie` | Library folder structure to expect |
| `-LogFile` | String | No | _(none)_ | Path to optional log file with timestamps |
| `-Interactive` | Switch | No | _(off)_ | Prompt "Press Enter to exit" at completion |

---

## How It Works

**Movies** (`-LibraryType Movie`):
Each subfolder of your root path is treated as one movie. If it contains no media files, any `*.trickplay` or `trickplay` subfolder inside it is deleted.

**TV Shows** (`-LibraryType TVShow`):
The script descends two levels (Show > Season). If a season folder contains no media files, its trickplay subfolders are deleted.

**Trickplay folder patterns matched:**
- `*.trickplay` — dot-prefixed format
- `trickplay` — plain folder name (case-insensitive)

**Media extensions recognized:**
`.mkv`, `.mp4`, `.m4v`, `.mov`, `.avi`, `.wmv`, `.mpg`, `.mpeg`, `.ts`, `.m2ts`, `.mts`, `.vob`, `.webm`, `.flv`, `.3gp`

---

## Task Scheduler / Automation

To run on a schedule (without interactive prompts), use the CLI mode with `-Root`:

```
Program:   powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Trickplay_Cleanup.ps1" -Root "V:\Movies" -LibraryType Movie -LogFile "C:\Logs\trickplay.log"
```

For TV shows:
```
Program:   powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Trickplay_Cleanup.ps1" -Root "V:\TV Shows" -LibraryType TVShow -LogFile "C:\Logs\trickplay.log"
```

---

## Documentation Files

- **`CODE_REVIEW.md`** — Detailed analysis of v1 with 15 identified issues, fixes, priorities, and code snippets
- **`NEW_FEATURES.md`** — Specifications for v2.0 features: interactive mode, config management, mapping logic, code examples
- **`config.example.json`** — Example configuration file structure for v2.0

---

## Changelog

### v2.2 — `Trickplay_Cleanup.ps1` (Current)

**New features (v2.2):**
- **Quick-select from saved config** — Press Enter at each prompt to reuse saved values
- **Automatic mode detection** — Shows saved library type with option to reuse
- **Smart log file reuse** — Shows previously used log file, press Enter to keep using it
- **Cleaner interface** — Hints show when saved values are available

**Existing features:**
- **Interactive mode** — Launch without arguments for step-by-step setup
- **Persistent configuration** — Folder paths saved to `trickplay_config.json` for quick reuse
- **WhatIf mode** — Preview deletions with `-WhatIf` before making changes
- **Confirmation prompts** — Ask before each deletion; skip with `-Force`
- **Progress indicators** — Visual progress bars for large library scans
- **Statistics tracking** — Detailed summary showing scanned folders, empty folders, removed items, failures
- **Independent library configs** — Separate saved paths for Movies and TV Shows

**Code improvements:**
- Robust config handling (no mutation of PSCustomObject)
- Safe path input (handles quoted paths, UNC shares, spaces)
- Error handling with clear error messages
- Comprehensive logging with timestamps
- Full help available via `Get-Help .\Trickplay_Cleanup.ps1`

---

### v1 — `Trickplay_Cleanup.ps1`

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
