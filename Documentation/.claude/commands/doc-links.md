# Documentation Link Checker

Validate all links in the documentation.

## Arguments
- `$ARGUMENTS` - Optional: specific file or directory to check (defaults to all docs)

## Instructions

1. **Scan documentation files** in the specified path or entire `docs/` directory.

2. **Extract all links** from markdown files:
   - Internal links: `[text](relative/path.md)`
   - Internal anchors: `[text](#heading-anchor)`
   - External links: `[text](https://example.com)`
   - Image references: `![alt](path/to/image.png)`

3. **Validate each link type**:

   ### Internal Links
   - Verify target file exists at the relative path
   - Check path is correct from the source file's location
   - Validate anchor links point to existing headings

   ### External Links
   - Attempt to fetch with HEAD request
   - Report any 4xx or 5xx status codes
   - Note any redirects (may want to update to final URL)
   - Skip if network unavailable (report as unchecked)

   ### Images
   - Verify image file exists
   - Check file extension is valid image type
   - Report missing alt text

4. **Generate report**:

```
## Link Check Report

### Summary
- Total links checked: X
- Valid: X
- Broken: X
- Warnings: X

### Broken Links (must fix)
| File | Line | Link | Issue |
|------|------|------|-------|
| docs/guide.md | 42 | [Setup](setup.md) | File not found |

### Warnings
| File | Line | Link | Issue |
|------|------|------|-------|
| docs/api.md | 15 | https://old.url | Redirects to https://new.url |

### External Links Checked
- https://codeberg.org/TAPPaaS - OK
- https://example.com/docs - OK
```

5. **Offer to fix** issues where possible:
   - Update redirected URLs
   - Remove or comment out broken links
   - Suggest correct paths for typos

## Link Patterns to Check

```
# Standard markdown links
[text](url)
[text](url "title")

# Reference-style links
[text][ref]
[ref]: url

# Auto-links
<https://example.com>

# Images
![alt](src)
![alt](src "title")
```
