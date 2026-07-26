# Documentation Search

Search across all documentation content.

## Arguments
- `$ARGUMENTS` - Search query (supports patterns and filters)

## Instructions

1. **Parse the search query**:
   - Plain text: search in content
   - `title:term` - search in page titles
   - `code:term` - search in code blocks only
   - `heading:term` - search in headings only
   - `file:pattern` - filter by filename pattern

2. **Search the `docs/` directory**:
   - Use grep/ripgrep for efficient searching
   - Search all `.md` files
   - Include context around matches

3. **Present results**:
   - Group by file
   - Show line numbers
   - Highlight matching terms
   - Show surrounding context (2-3 lines)

4. **Provide summary**:
   - Total matches found
   - Files containing matches
   - Suggest related searches if few results

## Output Format

```
## Search Results for "kubernetes"

### docs/getting-started/installation.md
Line 42: ... deploy to **kubernetes** clusters ...
Line 58: ... kubernetes configuration file ...

### docs/docs/architecture.md
Line 15: ... built on **kubernetes** primitives ...

---
Found 3 matches in 2 files
```

## Advanced Search Examples

```
# Find all TODO comments
TODO

# Search only in code blocks
code:kubectl

# Find pages about specific topic
title:installation

# Search specific file pattern
file:getting-started/* deploy

# Combine filters
heading:configuration code:yaml
```

## Tips

- Use quotes for exact phrases: `"getting started"`
- Search is case-insensitive by default
- Results are sorted by relevance/file path
