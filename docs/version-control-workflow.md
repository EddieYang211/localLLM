# Versioning and Release Checklist

This document tracks the workflow we follow when preparing a new localLLM release.

## Branch strategy

**Main development branch:** `master`
- All development happens directly on `master`
- Releases are tagged from `master`
- No long-lived feature branches (unless needed for experimental work)

## Repository layout

- `custom_files/` – authoring area for the public C API (`localllm_capi.*`) and custom CMake configuration
- `backend/llama.cpp/` – Git submodule pointing to the upstream `llama.cpp` repository (kept clean, files copied during build)
- `localLLM/` – R package sources
- GitHub Releases – distribution point for the prebuilt shared libraries (`localllm.dll`, `liblocalllm.so`, etc.)

## Before every release

1. **Edit source files in `custom_files/` only**
   - Modify `custom_files/localllm_capi.cpp` and `custom_files/localllm_capi.h` as needed
   - Keep `backend/llama.cpp/` submodule clean (GitHub Actions will copy files automatically during build)
   - If you accidentally edited files in `backend/llama.cpp/`, copy them back to `custom_files/`:
     ```bash
     cp backend/llama.cpp/localllm_capi.cpp custom_files/
     cp backend/llama.cpp/localllm_capi.h custom_files/
     git -C backend/llama.cpp reset --hard HEAD  # Clean the submodule
     ```

2. Bump versions in:
   - `localLLM/DESCRIPTION` (`Version:` field)
   - `localLLM/R/install.R` (`.lib_version` and `.base_url`)

3. Verify consistency
   ```bash
   # Ensure submodule is clean (should show no modifications)
   git status backend/llama.cpp

   # Verify version numbers are updated
   grep -R "1\.0\.XX" localLLM/ --include='*.R' --include='DESCRIPTION'
   ```

4. Run `R CMD check --as-cran localLLM_*.tar.gz` and ensure only the expected NOTE remains (new submission).

## Release steps

1. Commit the changes and push to `master`:
   ```bash
   git add custom_files/ localLLM/
   git commit -m "Release v1.0.XX: Description of changes"
   git push origin master
   ```

2. Create and push a release tag:
   ```bash
   git tag -a v1.0.XX -m "Release v1.0.XX"
   git push origin v1.0.XX
   ```

3. GitHub Actions automatically:
   - Copies files from `custom_files/` to `backend/llama.cpp/`
   - Builds binary bundles for all platforms
   - Attaches them to the release (`liblocalllm_macos_arm64.zip`, etc.)

4. Update the README if the default model or backend commit changes.

5. Optionally submit to CRAN once binaries are available.

## Daily development workflow

For non-release commits (bug fixes, new features, documentation updates):

```bash
# Make changes to files
git add .
git commit -m "feat: Add support for new feature"
# or
git commit -m "fix: Resolve issue with tokenization"
# or
git commit -m "docs: Update README examples"

# Push to GitHub
git push origin master
```

## Updating the llama.cpp submodule

To update to a newer version of llama.cpp:

```bash
# Navigate to the submodule
cd backend/llama.cpp

# Fetch latest changes from upstream
git fetch origin

# Checkout the desired commit or tag
git checkout <commit-hash-or-tag>

# Return to main project
cd ../..

# Commit the submodule update
git add backend/llama.cpp
git commit -m "chore: Update llama.cpp to <version>"
git push origin master
```

**Important:** Test thoroughly after updating llama.cpp, as API changes may require updates to `custom_files/localllm_capi.cpp`.

## Troubleshooting

### Submodule has uncommitted changes

If `git status` shows `modified: backend/llama.cpp (modified content)`:

```bash
# Option 1: You accidentally edited files in the submodule - save them first
cp backend/llama.cpp/localllm_capi.* custom_files/

# Option 2: Reset the submodule to clean state
cd backend/llama.cpp
git reset --hard HEAD
git clean -fd
cd ../..
```

### Build fails on GitHub Actions

1. Check that `custom_files/` contains the latest versions of your C API files
2. Verify the submodule is at the expected commit: `git submodule status`
3. Review the GitHub Actions logs for specific errors

Keep this checklist updated whenever the build or publishing process evolves.
