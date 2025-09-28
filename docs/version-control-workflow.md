# Versioning and Release Checklist

This document tracks the workflow we follow when preparing a new localLLM release.

## Repository layout

- `custom_files/` – authoring area for the public C API (`localllm_capi.*`)
- `backend/llama.cpp/` – fork of `llama.cpp` used for building shared libraries
- `localLLM/` – R package sources
- GitHub Releases – distribution point for the prebuilt shared libraries (`localllm.dll`, `liblocalllm.so`, etc.)

## Before every release

1. Synchronise source files
   ```bash
   cp custom_files/localllm_capi.cpp backend/llama.cpp/localllm_capi.cpp
   cp custom_files/localllm_capi.h   backend/llama.cpp/localllm_capi.h
   ```

2. Bump versions in:
   - `localLLM/DESCRIPTION` (`Version:` field)
   - `localLLM/R/install.R` (`.lib_version` and `.base_url`)

3. Verify consistency
   ```bash
   diff custom_files/localllm_capi.cpp backend/llama.cpp/localllm_capi.cpp
   grep -R "1\.0\.XX" localLLM/ --include='*.R' --include='DESCRIPTION'
   ```

4. Run `R CMD check --as-cran localLLM_*.tar.gz` and ensure only the expected NOTE remains (new submission).

## Release steps

1. Commit the changes and push to `main`.
2. Tag the release, e.g. `git tag v1.0.63 && git push origin v1.0.63`.
3. GitHub Actions builds the binary bundles and attaches them to the release (`liblocalllm_macos_arm64.zip`, etc.).
4. Update the README if the default model or backend commit changes.
5. Optionally submit to CRAN once binaries are available.

Keep this checklist updated whenever the build or publishing process evolves.
