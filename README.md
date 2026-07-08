# Zip-Dir

Quickly zip a directory — respects `.gitignore`, skips common junk by default, prefers 7-Zip, falls back to Windows `Compress-Archive`.

## Purpose

`zipdir folder` gives you a clean `.zip` in one command without thinking about what to exclude. It handles three layers of exclusion:

1. **Built-in blacklist** — `node_modules`, `.git`, `__pycache__`, `.DS_Store`, `.pyc`, etc.
2. **`.gitignore`** — your project's gitignore rules (uses `git ls-files` when git is available)
3. **`-Ignore`** — ad-hoc exclusions at invocation time

And one layer of forced inclusion (`-Allow`) that overrides all three.

## How it works (overall logic)

The script operates in a defined precedence order. Each step filters or extends the file list, with later steps overriding earlier ones:

| Precedence | Layer | What it does |
|------------|-------|-------------|
| 1 (lowest) | **Full file scan** | Recursively walks the source directory using a stack-based traversal, skipping known-junk directories (`node_modules`, `.git`, etc.) for performance. If `-Allow` is used, also scans those directories so Allow can find files there. |
| 2 | **Built-in file blacklist** | Removes common OS junk (`.DS_Store`, `Thumbs.db`) and cache extensions (`*.pyc`, `*.pyo`) from the file list. |
| 3 | **`.gitignore`** | When git is available and the source is a git repository, uses `git ls-files --cached --others --exclude-standard` for accurate gitignore resolution. When git is not available, falls back to manual pattern matching (handles `*`, `?`, `**`, `!` negation, and trailing `/` directory patterns). |
| 4 | **`-Allow`** | Re-includes files matching the given wildcard patterns. Searches the full candidate list (including files inside blacklisted directories) so it can override both `.gitignore` and the built-in blacklist. |
| 5 (highest) | **`-Ignore`** | Removes files matching the given wildcard patterns. Applied last, so it overrides everything including `-Allow`. |

Both `-Allow` and `-Ignore` accept semicolon-separated patterns: `-Allow "*.key;*.secret"`.

### 7-Zip integration

If 7-Zip (`7z.exe`) is found on the PATH or at common install paths (`C:\Program Files\7-Zip\7z.exe`, `C:\Program Files (x86)\7-Zip\7z.exe`), it is used for zipping with a file list. Otherwise, PowerShell's built-in `Compress-Archive` is used as a fallback.

## Usage

```powershell
zipdir .\MyProject              # uses .gitignore + built-in blacklist
zipdir ..\some\folder           # absolute or relative paths both work
zipdir .\MyProject -Allow "*.json"      # include even if gitignored/blacklisted
zipdir .\MyProject -Ignore "*.md;*.txt" # exclude even if allowed by gitignore
zipdir .\MyProject -Clean               # overwrite existing zip without prompt
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-ZipDir` | `string` (position 0, mandatory) | Directory to zip. Relative or absolute paths accepted. |
| `-Allow` | `string[]` | Wildcard patterns to force-include. Overrides `.gitignore` and the built-in blacklist. Semicolons delimit multiple patterns. |
| `-Ignore` | `string[]` | Wildcard patterns to force-exclude. Overrides everything including `-Allow`. Semicolons delimit multiple patterns. |
| `-Clean` | `switch` | Skip the overwrite prompt and delete the existing zip file if one exists. |

The output is saved as `<FolderName>.zip` in the current working directory.

## Installation (persistent, cross-reboot)

The recommended installation adds the function and alias to your PowerShell **profile**, making it available in every new PowerShell window.

### Step-by-step

1. **Open your profile** in a text editor:
   ```powershell
   notepad $PROFILE
   ```
   (If the file doesn't exist, create it.)

2. **Paste** the entire contents of `Zip-Dir.ps1` into the profile file and save.

3. **Reload** the profile in your current session:
   ```powershell
   . $PROFILE
   ```

4. **Use it** from any directory:
   ```powershell
   zipdir .\MyProject
   ```

### Alternative: dot-source from your profile

If you prefer keeping the script file separate, add this single line to `$PROFILE`:

```powershell
. C:\path\to\Zip-Dir.ps1
```

### How to find your PowerShell profile path

```powershell
$PROFILE
```

Typical paths:
- `C:\Users\<you>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` (PowerShell 5.1)
- `C:\Users\<you>\OneDrive\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` (OneDrive folder redirection)
- `C:\Users\<you>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` (PowerShell 7+)

## Built-in blacklist reference

| Category | Items excluded |
|----------|---------------|
| Directories | `node_modules`, `__pycache__`, `.git`, `.svn`, `.hg`, `.venv`, `venv`, `env`, `dist`, `build`, `.next`, `.nuxt`, `target`, `bin`, `obj`, `.idea`, `.vscode` |
| Files | `.DS_Store`, `Thumbs.db`, `desktop.ini`, `ehthumbs.db` |
| Extensions | `*.pyc`, `*.pyo` |

## Dependencies

- **7-Zip** (optional, recommended) — speeds up zipping and provides better compression. The script searches the PATH and common install directories. Download from [7-zip.org](https://7-zip.org).
- **git** (optional) — enables accurate `.gitignore` resolution. Falls back to manual pattern parsing if git is not available or the source is not a git repository.
- **PowerShell 5.1+** — required. `Compress-Archive` is used if 7-Zip is not found.
