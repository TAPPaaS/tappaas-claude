# Documentation Builder

Build and serve the MkDocs documentation site locally.

## Arguments
- `$ARGUMENTS` - Action to perform:
  - `serve` - Start local development server (default)
  - `build` - Build static site to `site/` directory
  - `check` - Run strict build to check for errors
  - `clean` - Remove built files

## Instructions

1. **Check prerequisites**:
   - Verify Python is available
   - Check if virtual environment exists or should be created
   - Ensure dependencies from `requirements.txt` are installed

2. **Based on the action**:

   ### `serve` (default)
   ```bash
   # Activate venv if exists, then:
   mkdocs serve
   ```
   - Starts local server at http://127.0.0.1:8000
   - Enables live reload for editing
   - Report the URL to the user

   ### `build`
   ```bash
   mkdocs build
   ```
   - Builds static site to `site/` directory
   - Report build statistics (pages, time)
   - Check for any warnings during build

   ### `check`
   ```bash
   mkdocs build --strict
   ```
   - Build with strict mode to catch all warnings as errors
   - Report any issues found:
     - Missing pages referenced in nav
     - Broken internal links
     - Invalid syntax
   - Useful before deploying

   ### `clean`
   ```bash
   rm -rf site/
   ```
   - Remove built files
   - Confirm before deletion

3. **Handle common issues**:
   - Missing dependencies: offer to run `pip install -r requirements.txt`
   - Port in use: suggest alternative port with `--dev-addr`
   - Missing files referenced in nav: list them and offer to create

4. **Setup instructions** if environment not ready:
   ```bash
   # Create virtual environment
   python -m venv venv
   source venv/bin/activate  # or venv\Scripts\activate on Windows

   # Install dependencies
   pip install -r requirements.txt
   ```

## Dependencies

From `requirements.txt`:
- mkdocs
- mkdocs-material
- mkdocs-minify-plugin
- pymdown-extensions

## Notes

- The site is configured to deploy via GitHub Actions (see `.github/workflows/deploy.yml`)
- Production builds are automatic on push to main branch
- Local serving is for development and preview only
