---
name: flutter-review
description: Review Flutter and Dart changes for correctness, architecture, security, performance, privacy, testing, and maintainability
---

Review the current uncommitted changes.

Check for:

- Incorrect behavior and edge cases
- Architecture violations
- Business logic inside widgets
- Missing loading or error states
- Unsafe asynchronous code
- Missing mounted checks after await
- Undisposed controllers or streams
- Unnecessary widget rebuilds
- Hardcoded secrets
- Clipboard content in logs
- Broken authentication or authorization assumptions
- Missing tests
- Mobile and web layout problems

Prioritize findings as:

1. Critical
2. High
3. Medium
4. Low

For every finding, include:

- File and location
- Why it matters
- A concrete correction

Do not modify files unless explicitly asked.
