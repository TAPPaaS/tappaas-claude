# Documentation Reviewer

Review documentation for quality, consistency, and completeness.

## Arguments
- `$ARGUMENTS` - File path, directory, or "all" to review entire docs folder

## Instructions

1. **Read the target files** specified in the arguments (or all `.md` files in `docs/` if "all").

2. **Check each document for**:

   ### Content Quality
   - Clear and concise writing
   - Proper grammar and spelling
   - Consistent tone (technical but approachable)
   - Accurate technical information
   - Complete explanations (no unexplained jargon)

   ### Structure
   - Proper YAML frontmatter (title, description)
   - Logical heading hierarchy (h1 -> h2 -> h3)
   - Appropriate use of lists, tables, code blocks
   - Reasonable page length (not too long/short)

   ### MkDocs Material Features
   - Proper admonition syntax (`!!! note`, `!!! warning`, etc.)
   - Correct code block formatting with language hints
   - Working tab groups if used
   - Proper emoji syntax (`:material-icon-name:`)

   ### Links and References
   - All internal links use relative paths
   - Link text is descriptive (not "click here")
   - Images have alt text

   ### Consistency with Project
   - Terminology matches other docs
   - Code examples follow project conventions
   - Branding is consistent (TAPPaaS capitalization)

3. **Generate a review report** with:
   - Summary of files reviewed
   - Issues found (categorized by severity: error, warning, suggestion)
   - Specific line numbers and recommended fixes
   - Overall documentation health score

4. **Offer to fix** any issues that can be automatically corrected.

## Output Format

```
## Documentation Review Report

### Files Reviewed
- [x] docs/index.md
- [x] docs/getting-started/installation.md

### Issues Found

#### Errors (must fix)
- `file.md:15` - Broken internal link to `missing-page.md`

#### Warnings (should fix)
- `file.md:42` - Heading skips from h2 to h4

#### Suggestions (nice to have)
- `file.md:8` - Consider adding a description in frontmatter

### Summary
- Files reviewed: X
- Errors: X
- Warnings: X
- Suggestions: X
```
