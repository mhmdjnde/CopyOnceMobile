---
name: flutter-ui
description: Design or implement responsive Flutter user interfaces, screens, widgets, themes, animations, and platform-adaptive layouts
---

Create or modify the Flutter UI requested in $ARGUMENTS.

Before editing:

1. Read CLAUDE.md.
2. Inspect the existing theme, reusable widgets, and related screens.
3. Identify phone, tablet, and web layout requirements.
4. Present a short UI plan.

Implementation rules:

- Use the existing design system and theme.
- Do not hardcode colors repeatedly.
- Create reusable widgets when an element appears more than once.
- Support narrow mobile and wide web layouts.
- Include loading, empty, error, and success states when relevant.
- Use proper spacing, typography, and visual hierarchy.
- Avoid unnecessary animations.
- Add semantic labels and accessible touch targets.
- Do not add packages without explaining why.

After editing:

- Run `dart format .`
- Run `flutter analyze`
- Report the changed files and remaining issues.
