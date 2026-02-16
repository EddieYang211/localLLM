# Development Guide

## Architecture Overview

This project uses a custom llama.cpp backend with modifications stored separately from the upstream submodule. This design allows us to:

1. Keep the upstream llama.cpp submodule clean (no local modifications)
2. Maintain our custom changes in version control
3. Support automated builds via GitHub Actions

## Directory Structure

```
localLLM/
├── backend/llama.cpp/          # Upstream llama.cpp submodule (unmodified)
├── custom_files/               # Our custom modifications
│   ├── localllm_capi.cpp      # Custom C API implementation
│   └── localllm_capi.h        # Custom C API header
└── scripts/                    # Build scripts
```

## Custom Modifications

All custom modifications to llama.cpp are maintained in the `custom_files/` directory:

- **`custom_files/localllm_capi.cpp`**: Custom C API implementation with:
  - Parallel inference support (`generate_parallel`)
  - First-token sampling fix for b7825
  - Position conflict resolution for strict consecutive position enforcement
  - Full prompt decoding instead of partial seq_cp (b7825 compatibility)

- **`custom_files/localllm_capi.h`**: Header file for the C API

## Build Process

### Local Development Build

The build process copies custom files into the backend directory:

```bash
cd backend/llama.cpp

# 1. Build llama.cpp libraries
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=Apple
make -j$(sysctl -n hw.ncpu)

# 2. Copy custom files
cp ../../custom_files/localllm_capi.cpp .
cp ../../custom_files/localllm_capi.h .

# 3. Build custom library (macOS)
./build_localllm.sh
```

### GitHub Actions Build

GitHub Actions automatically:

1. Checks out the repository with submodules
2. Copies `custom_files/localllm_capi.cpp` → `backend/llama.cpp/localllm_capi.cpp`
3. Builds the custom library for the target platform
4. Uploads the compiled binary as a release asset

**Important**: The `backend/llama.cpp` submodule must point to an upstream commit (e.g., `b7825`), NOT a local commit. GitHub Actions cannot fetch local commits from the submodule.

## Why This Architecture?

### Problem
Originally, we tried committing changes directly to the `backend/llama.cpp` submodule. This caused GitHub Actions to fail with:

```
fatal: remote error: upload-pack: not our ref 2099ad4d2...
fatal: Fetched in submodule path 'backend/llama.cpp', but it did not contain 2099ad4d2...
```

The local commit doesn't exist in the upstream ggerganov/llama.cpp repository, so CI cannot fetch it.

### Solution
- **Store custom code in `custom_files/`**: Version-controlled and always available
- **Keep submodule clean**: Points to upstream commits that CI can fetch
- **Copy at build time**: Build scripts copy custom files into the build directory

This approach ensures:
- ✅ CI can always checkout the submodule (points to public upstream commit)
- ✅ Custom modifications are tracked in git (in `custom_files/`)
- ✅ Local and CI builds work identically (same copy process)

## Making Changes

### To modify the C API:

1. **Edit `custom_files/localllm_capi.cpp`** (NOT `backend/llama.cpp/localllm_capi.cpp`)
2. Test locally by rebuilding
3. Commit only the `custom_files/` changes
4. Push to trigger CI build

### Example workflow:

```bash
# 1. Make changes
vim custom_files/localllm_capi.cpp

# 2. Test locally
cd backend/llama.cpp
./build_localllm.sh
# Copy to R package location for testing
cp build/bin/liblocalllm.dylib ~/Library/Application\ Support/org.R-project.R/R/localLLM/1.2.0/lib/

# 3. Run R tests
Rscript test_parallel_inference.R

# 4. Commit and push (only custom_files/)
git add custom_files/localllm_capi.cpp
git commit -m "Fix: description of the fix"
git push
```

## Common Issues

### Submodule shows "modified content"
This is normal during development. The submodule may have build artifacts or copied files. Don't commit these changes to the submodule.

```bash
# Clean submodule
git submodule update --init backend/llama.cpp
```

### CI fails with "not our ref"
The submodule is pointing to a local commit. Reset it to an upstream commit:

```bash
cd backend/llama.cpp
git reset --hard b7825  # or another upstream tag/commit
cd ../..
git add backend/llama.cpp
git commit -m "Reset submodule to upstream commit"
```

## Version History

### v1.2.0 → v1.2.1 (Current)
- Fixed first-token quality issue in `generate_parallel`
- Fixed seq_cp partial range restriction for llama.cpp b7825
- Transitioned to `custom_files/` architecture for CI compatibility

### v1.2.0
- Initial parallel inference support
- Position conflict fixes for b7825

## References

- Upstream llama.cpp: https://github.com/ggerganov/llama.cpp
- llama.cpp b7825 tag: https://github.com/ggerganov/llama.cpp/tree/b7825
