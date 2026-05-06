# Trickplay Cleanup

Remove orphaned trickplay metadata folders from media libraries when actual media files are missing.

**Current Version:** 2.3

---

## Quick Start

### First Run
```powershell
.\Trickplay_Cleanup.ps1
```
Select library type (1 or 2), confirm, and done.

### Subsequent Runs
```powershell
.\Trickplay_Cleanup.ps1
```
Press Enter to auto-remove all using saved settings, or select a new type.

---

## Features

- **Interactive Mode** — Menu-driven interface, no CLI knowledge required
- **Auto-Remove** — Automatically deletes all trickplay folders (no per-item prompts)
- **Persistent Config** — Saves folder paths and preferences to `trickplay_config.json`
- **Settings Menu** — Toggle verbose, confirmation, and backup preferences
- **Logging** — Automatic log file in script directory: `Trickplay_cleanup_log.txt`
- **WhatIf Mode** — Preview deletions without changes (CLI mode: `-WhatIf`)
- **CLI Mode** — Fully parameterized for automation and Task Scheduler

---

## Usage

### Interactive Mode (Recommended)
```powershell
.\Trickplay_Cleanup.ps1
```

Menu:
- **1) Movies** — Flat folder structure
- **2) TV Shows** — Show/Season hierarchy
- **3) Settings** — Toggle preferences
- **0) Go Back** — Exit or return to menu

### CLI Mode

**Movies:**
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie
```

**TV Shows:**
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\TV Shows" -LibraryType TVShow
```

**Preview (WhatIf):**
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie -WhatIf
```

**Skip Confirmations:**
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie -Force
```

**Custom Log File:**
```powershell
.\Trickplay_Cleanup.ps1 -Root "V:\Movies" -LibraryType Movie -LogFile "C:\Logs\custom.log"
```

---

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-Root` | String | Media library path. Omit for interactive mode. |
| `-LibraryType` | Movie / TVShow | Library structure type. |
| `-LogFile` | String | Custom log file path. Default: script directory. |
| `-WhatIf` | Switch | Preview deletions without changes. |
| `-Force` | Switch | Skip confirmation prompts. |

---

## Settings

Toggle in the interactive Settings menu (option 3):

- **Verbose** — Show detailed output (default: true)
- **Confirm Before Delete** — Ask before removing items (default: false in interactive, true in CLI)
- **Auto Backup Config** — Backup config before updates (default: true)

Settings are saved in `trickplay_config.json` in the script directory.

---

## Log Files

**Default:** `Trickplay_cleanup_log.txt` in script directory

**Custom:** Use `-LogFile` parameter to specify a different path

Logs include timestamps and detailed removal information.

---

## Task Scheduler

To run automatically on a schedule:

```
Program:   powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Trickplay_Cleanup.ps1" -Root "V:\Movies" -LibraryType Movie
```

---

## How It Works

### Movie Libraries
Each subfolder is treated as one movie. If no media files are found, trickplay folders are removed.

### TV Show Libraries
Scans Show > Season structure. Removes trickplay from seasons with no media.

### Detected Patterns
- `*.trickplay` — Plex/Jellyfin dot-prefixed format
- `trickplay` — Plain folder name

### Media Extensions
`.mkv`, `.mp4`, `.m4v`, `.mov`, `.avi`, `.wmv`, `.mpg`, `.mpeg`, `.ts`, `.m2ts`, `.mts`, `.vob`, `.webm`, `.flv`, `.3gp`

---

## Changelog

### v2.3
- Interactive settings menu (toggle preferences)
- Auto-remove all trickplay (no per-item confirmation)
- Simplified UI (removed structure descriptions)
- Default log file to script directory
- GitHub link in menu

### v2.2
- Quick-select from saved config
- Automatic mode detection
- Smart log file reuse
- Cleaner interface

### v2.1
- PowerShell 5.1 compatibility fixes
- Ternary operator removal
- DateTime UTC fix

### v2.0
- Interactive mode
- Persistent configuration
- WhatIf mode
- Confirmation prompts
- Progress indicators
- Statistics tracking

### v1
- Unified script (replaces separate movie/TV scripts)
- CLI parameters
- Logging support
- Path validation

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Read/write access to media library path

---

## Project

- **GitHub:** https://github.com/Chr0mX/arr-scripts
- **Issues:** Report bugs or request features on GitHub
