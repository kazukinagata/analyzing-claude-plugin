---
name: check-sessionstart
description: Report SessionStart hook output already present in this session.
---

This is an observation-only probe. Do not use tools, read files, inspect plugin contents, or run commands. Look only at the context already supplied to this session before this skill invocation. Report any line beginning with COWORK_SESSIONSTART_ verbatim, and state whether it arrived as SessionStart hook output. If none is present, reply NO_SESSIONSTART_MARKER. Do not guess or manufacture a marker.
