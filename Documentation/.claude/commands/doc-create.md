# Documentation Page Creator

Create a new documentation page for the TAPPaaS MkDocs site.

## Arguments
- `$ARGUMENTS` - The page title or path (e.g., "Installation Guide" or "getting-started/installation")

## Instructions

1. **Parse the arguments** to determine:
   - Page title
   - Target location in `docs/` directory
   - Parent section (if any)

2. **Check if the file already exists** at the target location. If it does, ask before overwriting.

3. **Create the markdown file** with proper structure:
   - YAML frontmatter with title and description
   - Main heading matching the title
   - Placeholder sections appropriate for the content type
   - Admonition blocks for tips/warnings where appropriate

4. **Update `mkdocs.yml`** navigation if the page needs to be added to the nav structure.

5. **Report** what was created and any manual steps needed.

## Template Structure

```markdown
---
title: [Page Title]
description: [Brief description for SEO and social sharing]
---

# [Page Title]

[Introduction paragraph explaining what this page covers]

## Overview

[Content here]

## [Main Section]

[Content here]

## Next Steps

- [Link to related page](path/to/page.md)
```

## File Naming Conventions

- Use lowercase with hyphens: `my-page-title.md`
- Place in appropriate subdirectory based on content type:
  - `getting-started/` - Onboarding and setup guides
  - `docs/` - Technical documentation
  - `community/` - Community resources
  - `about/` - Project information
