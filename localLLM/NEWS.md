# localLLM (development)

## New Functions

- **`model_metadata(model)`** — returns all GGUF key-value metadata as a named character vector. Useful for inspecting model architecture, quantization type, and embedded chat template. Example: `model_metadata(model)["tokenizer.chat_template"]`.

## Bug Fixes

- **Fixed `apply_chat_template()` failing for Gemma 4 models** — Gemma 4 uses a `<|turn>` / `<turn|>` chat format not recognized by `llama_chat_apply_template()` (returns -1). The fallback now calls `common_chat_templates_apply()` from `common/chat.cpp`, which executes the Jinja2 template embedded in the model's GGUF directly. This works for any model with a valid Jinja2 template regardless of the C API whitelist. `enable_thinking` defaults to `true`, so Gemma 4 generates thinking content naturally without a pre-closed thought block. Tool calls and multimodal content are not handled.

- **Fixed stop token leaking in `generate()` and `generate_parallel()` for ChatML models (OLMo, Llama 3)** — Two separate issues fixed:
  - *Windowed find*: OLMo tokenizes `<|im_end|>` as 6 separate pieces, with the last piece being `>\n` (merging `>` and newline). The previous exact-suffix check failed because the response ended with `<|im_end|>\n` instead of exactly `<|im_end|>`. Changed to a windowed `find()` that searches within the last `stop.size() + 4` bytes and truncates at the match position. Applied to both `generate()` and `generate_parallel()`.
  - *`<|start_header_id|>` loop*: Llama 3.2 3B sometimes omits `<|eot_id|>` and jumps directly to `<|start_header_id|>` to begin a new turn, causing infinite repetition. Added `<|start_header_id|>` to `text_stop_strings` in both functions.
  - `generate()`'s stop list also expanded from `{"<turn|>", "<end_of_turn>"}` to `{"<turn|>", "<end_of_turn>", "<|eot_id|>", "<|im_end|>", "<|start_header_id|>"}` to match `generate_parallel()`.

## Backend

- **Upgraded llama.cpp backend from b8664 → b8766** — 102 builds of improvements. Gemma 4 audio conformer encoder support, various bug fixes. The Gemma 4 template issue is not fixed upstream in this version; our local fallback is the active workaround.

## Bug Fixes

- **Fixed verbosity not forwarded in `quick_llama()`** — `verbosity` parameter was accepted but silently dropped when passed through to `.generate_single()` and `.generate_multiple()`, so backend logging level had no effect during `quick_llama()` calls. Now correctly forwarded to `generate()` and `generate_parallel()`.

- **Fixed backend errors crashing R instead of being catchable** — All `Rcpp::stop()` calls in `src/interface.cpp` replaced with `Rf_error()`. `stop()` throws a C++ exception which crosses the C boundary (`.Call()` registration) and triggers `std::terminate()`, killing the R process. `Rf_error()` uses `longjmp` which R's condition system can intercept, so `tryCatch()` now works correctly for all backend errors including the OOM guard.

- **Fixed model-loading progress dots leaking to stderr with `verbosity = 0`** — `llama_model_load_from_file()` has its own `progress_callback` that prints dots to stderr independently of the log callback system. Now set to a no-op when `verbosity < 2` in `localllm_model_load_safe()`. Model loading is fully silent at the default generation verbosity.

## Behavior Changes

- **`generate_parallel(progress)` now defaults to `interactive()`** — previously defaulted to `TRUE`, which printed carriage-return-based progress bars to log files and `R CMD check` output. The new default shows the progress bar only in interactive R sessions and suppresses it in scripts and automated checks.
- **`quick_llama(progress)` now defaults to `interactive()`** — same rationale as above; no effect on single-prompt calls.

## API Changes

- **Removed `quick_llama(stream)` parameter** — the `stream` argument was present in the function signature but was never passed to any downstream function (it was placeholder code with a comment "available for future use"). Removed to avoid user confusion.

## Backend

- **New `localllm_set_verbosity()` C API** — added to the backend binary and wired through the proxy layer (`proxy.h/cpp`, `interface.cpp`, `init.cpp`). Enables per-call verbosity control at the C level (integer 0–3, negative = fully silent). Called automatically by `generate()`, `generate_parallel()`, `model_load()`, and `context_create()` before each C invocation.

- **C-layer OOM crash guard in `localllm_model_load_safe()`** — added a last-resort memory check that fires even when `check_memory = FALSE`. If the model file is larger than total physical RAM, the function now returns a clean error (`"Model file (X.X GB) exceeds total physical RAM (Y.Y GB)..."`) instead of proceeding to `llama_model_load_from_file()` and letting macOS OOM-kill the R process silently. The guard only blocks provably-impossible loads (file size > total RAM) and does not interfere with the existing R-layer check. Supported on macOS (`sysctl hw.memsize`), Linux (`/proc/meminfo MemTotal`), and Windows (`GlobalMemoryStatusEx`).

## Known Issues

- **R-layer `model_load()` messages not suppressed by `verbosity = 0`** — Two R-level `message()` calls in `api.R` ("Using cached model: ..." and the GPU/unified-memory info line) print unconditionally regardless of `verbosity`. The `verbosity` parameter controls only the C backend log level; these R-layer informational messages are a separate code path not yet gated on verbosity. Confirmed against Gemma 4 26B-A4B (IQ2_XXS) on 2026-04-12.

## Documentation

- **Verbosity dual-default design now documented** — `generate()` and `generate_parallel()` roxygen entries now explain why they default to `0L` (called in loops, per-call logs would be noisy) and cross-reference `model_load()`/`context_create()` (default `1L`, run once per session, warnings should be visible).

---

# localLLM 1.3.0

## Performance Fix: Parallel Generation Speedup Restored

- **Fixed `generate_parallel()` performance regression** introduced by llama.cpp b7825's new memory API
- The `llama_memory_seq_cp()` call was dropped during the b7825 migration, causing every parallel slot to re-decode the full prompt instead of sharing the prefix
- Restored prefix sharing via full-range copy (`p0=-1, p1=-1`), which is compatible with the new API
- **Benchmark result**: parallel generation is now ~1.4–1.6x faster than sequential (was 0.85x — slower — before this fix)

## Platform Support

- **Added Intel Mac binary** — `generate()` and `generate_parallel()` now work on Intel Macs (x86_64); GPU acceleration is not available on Intel Mac, CPU inference is used
- **Fixed `hardware_profile()` crash** on Linux and Windows when GPU diagnostic tools (`nvidia-smi`, `rocm-smi`, `clinfo`) are not installed

## Backend Upgrade: llama.cpp b7825 -> b8664

- **Upgraded llama.cpp backend** from b7825 (Jan 2026) to b8664 (Apr 2026)
- **~840 builds** of improvements, bug fixes, and new model support

### New Model Support (18 new architectures)

- Gemma 4, Qwen 3.5, Qwen 3.5 MoE, ERNIE 4.5
- Granite (standalone), Granite MoE, Granite Hybrid
- JAIS-2, DeepSeek OCR, GLM-DSA, EuroBERT
- Kanana-2, PaddleOCR-VL, ARWKV7, PLM
- BailingMoE, DOTS1, Arcee, AFMoE

### New Chat Templates

- DeepSeek OCR template
- Granite 4.0 template (with tool call support)

### Build System

- Added `vendor/cpp-httplib` dependency (required by updated `common/` library)
- Added license embedding support via `cmake/license.cmake`

## API Compatibility

**No changes to R-level API** - All existing R code continues to work without modification.

---

# localLLM 1.2.1

## Bug Fixes

- Fix CRAN NOTE: redirect model cache to `tempdir()` during automated checks
  so that `R CMD check` no longer creates `~/.cache/R/localLLM` in the home
  directory (CRAN policy violation).
- Update `hardware_profile()` example to use `\donttest{}` instead of
  `if (interactive())` guard, per CRAN best practices.

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

For more information about llama.cpp, see:
- [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)
- [llama.cpp documentation](https://github.com/ggml-org/llama.cpp)

# localLLM 1.1.0

Previous release notes (if any) would go here...
