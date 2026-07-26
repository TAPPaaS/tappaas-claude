# Documentation Navigation Manager

Manage the navigation structure in mkdocs.yml.

## Arguments
- `$ARGUMENTS` - Action to perform:
  - `show` - Display current navigation structure
  - `add <path> [section]` - Add a page to navigation
  - `remove <path>` - Remove a page from navigation
  - `reorder` - Interactive reordering
  - `sync` - Sync nav with actual files in docs/

## Instructions

1. **Read `mkdocs.yml`** to understand current navigation structure.

2. **Based on the action**:

   ### `show`
   - Display the current navigation as a tree
   - Indicate any pages in nav that don't exist as files
   - Indicate any files that aren't in nav

   ### `add <path> [section]`
   - Validate the markdown file exists
   - Add to specified section or suggest appropriate section
   - Use proper page title from frontmatter or filename

   ### `remove <path>`
   - Remove the entry from nav
   - Optionally ask if the file should also be deleted

   ### `reorder`
   - Show current structure
   - Ask user for desired changes
   - Update mkdocs.yml accordingly

   ### `sync`
   - Scan all .md files in docs/
   - Compare with nav entries
   - Report discrepancies:
     - Files not in nav (orphaned pages)
     - Nav entries without files (broken nav)
   - Offer to fix issues

3. **Update `mkdocs.yml`** with proper YAML formatting:
   - Preserve comments
   - Maintain consistent indentation (2 spaces)
   - Keep sections in logical order

4. **Validate changes** by checking YAML syntax.

## Navigation Structure Reference

```yaml
nav:
  - Home: index.md
  - Section Name:
    - Page Title: section/page.md
    - Nested Section:
      - Nested Page: section/nested/page.md
```

## Best Practices

- Keep navigation depth to 3 levels max
- Use descriptive section names
- Group related pages together
- Put most important/common pages first
- Use consistent naming conventions
