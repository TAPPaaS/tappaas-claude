# Documentation Table of Contents Generator

Generate or update table of contents for documentation pages.

## Arguments
- `$ARGUMENTS` - Action and target:
  - `<file>` - Generate TOC for specific file
  - `all` - Generate TOC for all pages that need one
  - `index` - Create a master index page

## Instructions

1. **For single file**:
   - Read the markdown file
   - Extract all headings (h2 and below)
   - Generate a linked TOC at the top of the content section
   - Use proper anchor links

2. **For all files**:
   - Scan all docs/ markdown files
   - Identify pages with 4+ headings that lack a TOC
   - Offer to add TOC to each

3. **For index**:
   - Create a master documentation index
   - Organize by section/category
   - Include page descriptions

## TOC Format

```markdown
## On this page

- [Section One](#section-one)
  - [Subsection](#subsection)
- [Section Two](#section-two)
- [Section Three](#section-three)
```

## Anchor Generation Rules

MkDocs Material generates anchors by:
- Converting to lowercase
- Replacing spaces with hyphens
- Removing special characters
- Handling duplicates with `-1`, `-2` suffixes

Examples:
- `## Getting Started` -> `#getting-started`
- `## What's New?` -> `#whats-new`
- `## API Reference` -> `#api-reference`

## Notes

- MkDocs Material has built-in TOC in the right sidebar
- In-page TOC is useful for very long pages
- Consider using `hide: toc` in frontmatter for short pages
- The `toc_depth: 3` setting in mkdocs.yml controls sidebar depth
