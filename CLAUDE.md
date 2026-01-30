# CLAUDE.md - AI Assistant Instructions

**READ THIS FILE FIRST EVERY TIME YOU ENTER THIS PROJECT.**

**THEN read the latest log file in `log/` to pick up where we left off.**

This file contains critical rules and instructions for Claude (AI assistant) when working on this project. These rules are non-negotiable and must be followed at all times.

---

## CRITICAL RULES

### Rule 1: NEVER DELETE DATA, CODE, OR FILES
Under **no circumstances** are you ever to DELETE data, code, or any files in this project directory structure. This includes:
- CSV data files
- Code scripts (Python, R, Stata, etc.)
- Documentation files
- Any other project files

If something needs to be deprecated, rename it with a prefix like `_deprecated_` or `_old_` instead of deleting.

### Rule 2: FOLDER BOUNDARIES - NEVER LEAVE THESE TWO FOLDERS

You are **ONLY** permitted to work within these two folder paths:

1. **READ-ONLY Data Folder (Dropbox):**
   ```
   C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\
   ```
   - This folder is for **READING CSV files ONLY**
   - **DO NOT** create, modify, or save any files here
   - **DO NOT** write output files here

2. **Code & Output Folder (GitHub):**
   ```
   C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\
   ```
   - This is where **ALL new code and files** must be saved
   - Save Python scripts to: `code/python/`
   - Save R scripts to: `code/R/`
   - Save Stata scripts to: `code/stata/`
   - Output data files go here (create `data/` or `output/` subfolder as needed)

**Under NO circumstances are you to EVER LEAVE these two folders.**

### Rule 3: Data Flow Direction
```
[Dropbox - READ ONLY] ──READ──> [Your Process] ──WRITE──> [GitHub Repository]
```

### Rule 4: GIT PUSH RESTRICTIONS
Claude may **ONLY** perform the following git operations:
- `git status` - Check repository status
- `git add` - Stage files for commit
- `git commit` - Commit staged changes locally

**Claude is NEVER permitted to run `git push`.**

Only the user decides when to push commits to GitHub. When commits are ready, Claude should inform the user and let them run `git push origin main` themselves.

### Rule 5: MAINTAIN PROGRESS LOGS
Claude must regularly update progress logs in the `log/` directory to ensure session continuity:
- Create new log entries with format `YYYY-MM-DD_HHMM.md`
- Log what was accomplished, files changed, current status, and next steps
- When starting a new session, read the latest log to resume work seamlessly

---

## Git & GitHub Guidance

Since the user is new to GitHub, provide clear step-by-step guidance for:

1. **Checking status:** `git status`
2. **Staging changes:** `git add <filename>` or `git add .`
3. **Committing:** `git commit -m "descriptive message"`
4. **Pushing:** `git push origin main` *(User runs this manually)*

Always explain what each git command does before running it.

---

## Project Context

- **Purpose:** Fuzzy merge of Puerto Rico Act 22 Individual Investor Annual Reports
- **Data Sources:** Two CSV files covering 2015-2018 and 2019 filings
- **Challenge:** No direct ID linkage; must use location, financial, and business data for matching

---

## Amendment Log

*New rules will be added below as they arise:*

| Date | Rule Added |
|------|------------|
| 2025-01-30 | Initial rules: No deletion, folder boundaries, read/write separation |
| 2025-01-30 | Rule 4: Claude may stage and commit, but NEVER push to GitHub |
| 2025-01-30 | Rule 5: Maintain progress logs in `log/` for session continuity |

---

*This file will be amended regularly with new rules as they come along.*
