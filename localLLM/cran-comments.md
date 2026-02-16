## Version 1.2.0 Submission

This is a major update submission (version 1.2.0) with significant backend improvements and new features.

## R CMD check results

0 errors ✓ | 0 warnings ✓ | 1 note

* NOTE: unable to verify current time (system-specific timing check, not a package issue)

## Test environments

* local macOS install (ARM64), R 4.4.1
* win-builder (R-devel, R-release, R-oldrelease) - all PASSED ✓
* GitHub Actions:
  - ubuntu-latest (R-release)
  - macOS-latest (R-release)
  - windows-latest (R-release)

## Win-builder check results

✓ Windows Server 2022 (R-devel)
✓ Windows Server 2022 (R-release)
✓ Windows Server 2022 (R-oldrelease)

All platforms: 0 errors, 0 warnings, 1 note (time verification only)

## What's new in version 1.2.0

### Major Changes
* Upgraded llama.cpp backend from b5421 to b7825 (~400 commits of improvements)
* Migrated to unified Memory API (from deprecated KV Cache API)
* Improved parallel inference performance
* Enhanced reproducibility and memory management
* Better support for hybrid model architectures (Transformers, Mamba, RWKV)

### API Compatibility
* **No breaking changes** to R-level API - all existing user code continues to work
* Backend changes are transparent to R users
* Enhanced error handling and automatic cleanup

## Note about C++17

The package requires C++17 as specified in SystemRequirements.
Successfully compiled and tested on:
- Windows (win-builder: devel, release, oldrelease)
- macOS (Intel and ARM64)
- Linux (Ubuntu via GitHub Actions)

## Note about package architecture

This package uses a lightweight architecture where the C++ backend library
(llama.cpp) is downloaded at runtime via `install_localLLM()` rather than
bundled with the package. This design:
- Reduces CRAN package size to ~165 KB (vs. potential 100+ MB with bundled backend)
- Simplifies cross-platform distribution
- Allows platform-optimized builds (Metal for macOS, CUDA for Windows/Linux)
- Users must explicitly call `install_localLLM()` after package installation

The package itself contains only:
- R interface code
- Rcpp wrapper code
- Documentation and tests
- No large binary files

## Downstream dependencies

There are currently no downstream dependencies for this package.

## Additional checks performed

* All 206 tests pass
* All examples run successfully
* Vignettes build without errors
* Documentation is complete and up-to-date
* No code/documentation mismatches
* No non-ASCII characters in code
