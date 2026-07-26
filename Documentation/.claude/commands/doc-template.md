# Documentation Template Generator

Generate documentation pages from predefined templates.

## Arguments
- `$ARGUMENTS` - Template type and parameters:
  - `guide <title>` - How-to guide template
  - `reference <title>` - API/reference documentation
  - `tutorial <title>` - Step-by-step tutorial
  - `concept <title>` - Conceptual explanation
  - `troubleshoot <title>` - Troubleshooting guide
  - `release <version>` - Release notes template
  - `list` - Show all available templates

## Instructions

1. **Parse arguments** to determine template type and title.

2. **Generate appropriate template** based on type:

   ### Guide Template (`guide`)
   Task-oriented documentation for completing a specific goal.

   ### Reference Template (`reference`)
   Technical specifications, API docs, configuration options.

   ### Tutorial Template (`tutorial`)
   Learning-oriented, step-by-step instructions for beginners.

   ### Concept Template (`concept`)
   Understanding-oriented explanation of ideas and architecture.

   ### Troubleshoot Template (`troubleshoot`)
   Problem-solution format for common issues.

   ### Release Template (`release`)
   Changelog format with features, fixes, breaking changes.

3. **Create the file** with proper naming and location.

4. **Update navigation** if requested.

## Template: Guide

```markdown
---
title: How to [Action]
description: Learn how to [achieve goal] in TAPPaaS
---

# How to [Action]

This guide shows you how to [achieve specific goal].

## Prerequisites

Before you begin, ensure you have:

- [ ] Prerequisite 1
- [ ] Prerequisite 2

## Steps

### Step 1: [First action]

[Instructions]

### Step 2: [Second action]

[Instructions]

## Verification

To verify everything is working:

1. [Check step]
2. [Expected result]

## Next steps

- [Related guide](link)
- [Advanced topic](link)
```

## Template: Tutorial

```markdown
---
title: "Tutorial: [Topic]"
description: A hands-on tutorial for learning [topic] in TAPPaaS
---

# Tutorial: [Topic]

**Time to complete**: X minutes
**Skill level**: Beginner / Intermediate / Advanced

## What you'll learn

By the end of this tutorial, you will:

- Learning outcome 1
- Learning outcome 2

## Before you start

You'll need:

- Requirement 1
- Requirement 2

## Part 1: [Section]

[Detailed instructions with explanations]

!!! tip
    Helpful tip for learners

## Part 2: [Section]

[Continue building on previous section]

## Summary

In this tutorial, you learned how to:

- Accomplishment 1
- Accomplishment 2

## Next steps

Ready to learn more? Try these tutorials:

- [Next tutorial](link)
```

## Template: Troubleshooting

```markdown
---
title: Troubleshooting [Topic]
description: Solutions for common [topic] issues in TAPPaaS
---

# Troubleshooting [Topic]

## Common Issues

### Issue: [Problem description]

**Symptoms**: What the user observes

**Cause**: Why this happens

**Solution**:

1. Step to fix
2. Step to fix

---

### Issue: [Another problem]

**Symptoms**: What the user observes

**Cause**: Why this happens

**Solution**:

```bash
# Command to fix
```

## Getting More Help

If you're still experiencing issues:

- Check the [FAQ](link)
- Ask in [Community](link)
- Open an [Issue](link)
```
