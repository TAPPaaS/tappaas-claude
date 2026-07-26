# Documentation Statistics

Generate statistics and analytics about the documentation.

## Arguments
- `$ARGUMENTS` - Optional focus area:
  - (none) - Full statistics report
  - `coverage` - Documentation coverage analysis
  - `freshness` - Last update dates
  - `complexity` - Readability metrics

## Instructions

1. **Scan all documentation files** in `docs/` directory.

2. **Generate statistics**:

   ### Basic Metrics
   - Total number of pages
   - Total word count
   - Average words per page
   - Total code blocks
   - Total images

   ### Structure Analysis
   - Pages per section
   - Navigation depth
   - Orphaned pages (not in nav)
   - Missing pages (in nav but no file)

   ### Content Analysis
   - Pages with/without descriptions
   - Pages with/without frontmatter
   - Heading structure compliance
   - Code block languages used

   ### Freshness (from git)
   - Most recently updated pages
   - Pages not updated in 30+ days
   - Pages not updated in 90+ days

   ### Complexity
   - Average sentence length
   - Technical term density
   - Reading level estimate

3. **Present report**:

```
## Documentation Statistics

### Overview
| Metric | Value |
|--------|-------|
| Total Pages | 24 |
| Total Words | 15,432 |
| Avg Words/Page | 643 |
| Code Blocks | 87 |
| Images | 12 |

### By Section
| Section | Pages | Words |
|---------|-------|-------|
| Getting Started | 4 | 2,100 |
| Documentation | 12 | 8,500 |
| Community | 3 | 1,200 |
| About | 3 | 800 |

### Health Indicators
- [x] All nav entries have files
- [x] All pages have descriptions
- [ ] 3 pages missing frontmatter
- [ ] 5 pages not updated in 90+ days

### Recommendations
1. Add descriptions to: page1.md, page2.md
2. Review stale pages: old-guide.md
3. Consider splitting long page: installation.md (2,400 words)
```

## Use Cases

- Track documentation growth over time
- Identify gaps in documentation
- Find pages needing updates
- Report on documentation efforts
