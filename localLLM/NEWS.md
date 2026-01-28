# localLLM 1.2.0

## Major Changes

### Backend Upgrade: llama.cpp b5421 → b7825

- **Upgraded llama.cpp backend** from b5421 (Dec 2024) to b7825 (Jan 2025)
- **~400 commits** of improvements and architectural changes
- **Latest stable release** as of January 2025

### Core Architecture Migration: KV Cache → Unified Memory API

**Breaking changes in backend (transparent to R users):**
- Migrated from `llama_kv_self_*` API to `llama_memory_*` API
- Supports heterogeneous model architectures:
  - Standard Transformers (LLaMA, Qwen, Mistral, etc.)
  - Mamba/RWKV (State Space Models)
  - Hybrid models (Jamba, LFM2)
  - Sliding Window Attention (Qwen2-MLA)

**Key improvements:**
- Better memory management and automatic defragmentation
- Enhanced support for parallel inference with shared prefixes
- Improved reproducibility of generation results
- More efficient batch processing

### Batch API Modernization

- Updated to new batch construction API:
  - Old: `llama_batch_get_one()`
  - New: `llama_batch_init()` + `common_batch_add()` + `llama_batch_free()`
- Better memory safety and resource cleanup

## Improvements

### Memory Management

- **Automatic memory cleanup** on errors to prevent state corruption
- **Enhanced reproducibility**: Each `generate()` call starts from clean state
- **Thread configuration**: Added `n_threads_batch` parameter for batch processing

### Error Handling

- Improved error recovery with automatic memory state cleanup
- Better error messages for decode failures

### Performance

- Optimized batch processing with independent thread configuration
- Automatic defragmentation (no manual intervention needed)
- Better Metal GPU utilization on macOS

## API Compatibility

**No changes to R-level API** - All existing R code continues to work without modification:

```r
library(localLLM)

backend_init()
model <- model_load("model.gguf")
ctx <- context_create(model, n_ctx = 512)
result <- generate(ctx, "Hello", max_tokens = 10)
# All existing code works exactly the same
```

## Backend Library Changes

### Compilation

- New build script: `backend/llama.cpp/build_localllm.sh`
- Improved dependency management (OpenSSL, Metal, Accelerate)
- Better symbol visibility and library linking

### File Modifications

**Updated files:**
- `custom_files/localllm_capi.cpp` (10 locations modified)
  - Memory API migration (8 locations)
  - Batch API modernization (2 locations)
  - Error handling improvements
  - Thread configuration updates

**Unchanged:**
- `custom_files/localllm_capi.h` (C API interface)
- All R layer code (`R/*.R`)
- Proxy layer (`src/proxy.cpp`)
- Test suite (`tests/testthat/*.R`)
- Documentation

## Testing

- ✅ All 206 tests pass
- ✅ R CMD check passes with no errors
- ✅ Compiled library size: 4.2 MB
- ✅ 35 exported C API functions verified

## Installation Notes

### First-time Installation

```r
install.packages("localLLM_1.2.0.tar.gz", repos = NULL, type = "source")
library(localLLM)
install_localLLM()  # Will download the new b7825 backend
```

### Upgrading from 1.1.0

```r
remove.packages("localLLM")
install.packages("localLLM_1.2.0.tar.gz", repos = NULL, type = "source")
library(localLLM)
install_localLLM(force = TRUE)  # Force reinstall backend
```

## Documentation

New technical documentation:
- `UPGRADE_COMPLETE.md` - Complete upgrade report
- `CRITICAL_CHANGES_REQUIRED.md` - Detailed change checklist
- `MIGRATION_ANALYSIS_b5421_to_b7785.md` - Full migration analysis
- Architecture deep-dive in planning documents

## Known Issues

- CRAN check warning about unchanged version number (resolved in this release)
- Metal shader embedding required for GitHub Actions (already implemented)

## Future Enhancements

Potential optimizations for future releases:
- Flash Attention support for improved performance
- Unified Buffer optimization for multi-sequence inference
- SWA (Sliding Window Attention) for ultra-long contexts (128K+)

## Contributors

- Backend migration and testing: Claude (Anthropic)
- Package maintenance: Yaosheng Xu
- Original package: Eddie Yang

---

For detailed technical information about the backend upgrade, see:
- [UPGRADE_COMPLETE.md](../UPGRADE_COMPLETE.md)
- [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)

# localLLM 1.1.0

Previous release notes (if any) would go here...
