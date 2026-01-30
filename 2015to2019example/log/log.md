# Progress Log System

## Purpose

This directory contains dated progress logs to ensure **session continuity** when conversations with Claude end unexpectedly or need to be restarted.

Each log captures:
- What was accomplished in the session
- Current state of the project
- Next steps / what we were about to do
- Any important decisions made

## How It Works

1. **Claude updates the log regularly** during work sessions
2. **When starting a new conversation**, Claude reads:
   - `CLAUDE.md` (rules)
   - `README.md` (project structure)
   - Latest log file in this directory (to pick up where we left off)
3. **Logs are dated** with format `YYYY-MM-DD_HHMM.md` for easy chronological sorting

## Log File Naming Convention

```
log/
├── log.md                    (this file - explains the system)
├── 2025-01-30_1530.md        (first log entry)
├── 2025-01-30_1745.md        (later same day)
├── 2025-01-31_0900.md        (next day)
└── ...
```

## What to Include in Each Log

1. **Session Summary** - Brief overview of what happened
2. **Files Created/Modified** - List of changes made
3. **Current Status** - Where are we in the project?
4. **Next Steps** - What should happen next?
5. **Open Questions** - Anything unresolved?

---

*This system ensures no work is lost between sessions.*
