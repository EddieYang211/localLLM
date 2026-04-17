# localLLM Future Feature Roadmap

> Based on llama.cpp b8766 (2026-04-12) capability analysis.
> These features are available in the llama.cpp backend and can be exposed to R users by adding bridge code.

---

## 1. Embedding Extraction (Priority: HIGH)

**What**: Convert text into numerical vectors (e.g., 4096-dim float array). Semantically similar texts produce similar vectors.

**Use cases for R users**:
- Semantic search: find most relevant paragraphs in a document corpus
- Text clustering and classification
- RAG (Retrieval-Augmented Generation): retrieve relevant context before LLM generation
- Similarity scoring between text pairs

**llama.cpp API (stable C API in llama.h)**:
```c
void    llama_set_embeddings(ctx, true);              // enable embedding mode
int     llama_model_n_embd(model);                    // get embedding dimension
float * llama_get_embeddings_ith(ctx, i);             // per-token embedding
float * llama_get_embeddings_seq(ctx, seq_id);        // pooled sequence embedding (MEAN/CLS/LAST)
```

Pooling types: `LLAMA_POOLING_TYPE_NONE`, `MEAN`, `CLS`, `LAST`, `RANK`

**Changes needed**:

| Layer | File | Changes |
|-------|------|---------|
| C bridge | `localllm_capi.cpp/h` | Add ~3 functions: `localllm_get_embedding()`, `localllm_model_n_embd()` |
| Proxy | `proxy.h/cpp` | Add ~2 function pointers |
| Rcpp | `interface.cpp` | Add ~1 wrapper, return `NumericVector` |
| R | new function | `get_embedding(model, text)` returning numeric vector |

**Core logic**: tokenize -> fill batch (logits=1) -> decode -> copy from `llama_get_embeddings_ith()`

**Estimated effort**: ~150-200 lines across 4 files

**API stability**: HIGH - uses only stable llama.h C API

---

## 2. Structured Output / Grammar Constraints (Priority: HIGH)

**What**: Force model output to conform to a specific format. E.g., specify "output must be a JSON object with name (string) and age (integer)" — the model cannot produce invalid JSON.

**Use cases for R users**:
- Reliable JSON output, directly parseable with `jsonlite::fromJSON()`
- BNF grammar to define arbitrary formats (CSV, SQL, etc.)
- Eliminate format hallucination issues

**llama.cpp API**:
- BNF Grammar string: set via `common_params_sampling.grammar` field
  - Type changed from `std::string` to `common_grammar` struct in b8664:
    ```cpp
    sparams.grammar = common_grammar(COMMON_GRAMMAR_TYPE_USER, grammar_str);
    ```
- JSON Schema -> Grammar: automatic conversion in `common/json-schema-to-grammar.h` (internal C++ API)

**Changes needed**:

| Layer | File | Changes |
|-------|------|---------|
| C bridge | `localllm_capi.cpp/h` | Modify `localllm_generate()` to accept `grammar` string param |
| Proxy | `proxy.h/cpp` | Update function signature |
| Rcpp | `interface.cpp` | Pass through grammar parameter |
| R | `generate()` | Add `grammar = NULL` parameter |

**Estimated effort**:
- BNF Grammar only: ~50 lines
- BNF + JSON Schema: ~150 lines

**API stability**: LOW - depends on `common/` internal API (`common_grammar` struct), may break on llama.cpp upgrades

---

## 3. Reasoning / Thinking Support (Priority: MEDIUM)

**What**: Support "thinking" models (DeepSeek-R1, QwQ, etc.) that reason inside `<think>...</think>` tags before giving a final answer. Reasoning budget controls how many tokens the model spends "thinking".

**Use cases for R users**:
- Use thinking models, see the reasoning process
- Control thinking budget: `reasoning_budget = 1024`
- Separate thinking content from final answer

**llama.cpp API** (in `common_params_sampling`):
```cpp
int32_t reasoning_budget_tokens = -1;                 // -1 = disabled
std::vector<llama_token> reasoning_budget_start;      // <think> token sequence
std::vector<llama_token> reasoning_budget_end;        // </think> token sequence
std::vector<llama_token> reasoning_budget_forced;     // forced end sequence
```

**Changes needed**:

| Layer | File | Changes |
|-------|------|---------|
| C bridge | `localllm_capi.cpp/h` | Modify `localllm_generate()` to accept `reasoning_budget`; set `sparams.reasoning_budget_tokens`; distinguish thinking vs answer in generation loop |
| Proxy | `proxy.h/cpp` | Update function signature |
| Rcpp | `interface.cpp` | Pass through parameter |
| R | `generate()` | Add `reasoning_budget = -1` param; return list with `$thinking` and `$answer` |

**Key difficulty**: Auto-detecting thinking start/end tokens varies by model. This logic lives in `common/` autoparser (unstable internal API).

**Estimated effort**: ~200-300 lines

**API stability**: LOW - depends on `common/` internal API for autoparser and reasoning budget sampler

---

## 4. Self-Speculative Decoding (Priority: MEDIUM)

**What**: Speed up text generation without a separate draft model. The model "skips" some layers to quickly guess multiple tokens, then verifies with the full model. Correct guesses are accepted in bulk. Typically 1.5-2x speedup with identical output quality.

**Use cases for R users**:
- 50-100% faster generation (task-dependent)
- Completely transparent — output is identical
- No extra model needed

**llama.cpp API** (in `common/speculative.h`):
```cpp
common_speculative * common_speculative_init(ctx);
common_speculative_gen(spec, ...);
```

Also available at sampler level:
```cpp
// Batch draft-verify-accept in one call
std::vector<llama_token> common_sampler_sample_and_accept_n(
    gsmpl, ctx, idxs, draft, grammar_first);
```

**Changes needed**:

| Layer | File | Changes |
|-------|------|---------|
| C bridge | `localllm_capi.cpp/h` | Major rewrite of generation loop: current single-token loop -> speculative batch guess/verify/accept loop |
| Proxy | `proxy.h/cpp` | Possibly new function or flag |
| R | `generate()` | Add `speculative = FALSE` parameter |

**Key difficulty**: Requires rewriting the core generation loop in `localllm_generate()` and `localllm_generate_parallel()`. High risk of introducing bugs.

**Estimated effort**: ~300-500 lines, core logic refactor

**API stability**: LOW - depends on `common/speculative.h` (unstable internal API)

---

## 5. Multimodal / Vision (Priority: LOW)

**What**: Let models "see" images (LLaVA, InternVL, Phi-4 Vision, DeepSeek OCR, PaddleOCR-VL, etc.). Users pass an image, and the model describes it or answers questions about it.

**Use cases for R users**:
- Image captioning and description
- OCR (optical character recognition)
- Visual question answering
- Document understanding

**llama.cpp API** (separate `mtmd` module):
```cpp
mtmd_context * mtmd_init(model, ...);
mtmd_tokenize(ctx, image_path, ...);   // image -> tokens
// Then feed tokens into normal decode pipeline
```

Supported models in b8664: InternVL, DeepSeek OCR, Phi-4 Vision, LightOnOCR, Nemotron Nano VL, etc.

**Changes needed**:

| Layer | File | Changes |
|-------|------|---------|
| C bridge | `localllm_capi.cpp/h` | New subsystem: model loading with vision projector, image tokenization, embedding insertion during generation |
| CMake | `CMakeLists.txt.custom` | Link mtmd module |
| Proxy | `proxy.h/cpp` | Add ~5-8 new function pointers |
| Rcpp | `interface.cpp` | New wrappers for vision functions |
| R | New functions | `model_load_vision()`, `generate_with_image()`, etc. |

**Estimated effort**: ~500-800 lines, essentially a new subsystem

**API stability**: LOW - `mtmd` module is actively evolving with frequent changes

---

## Workaround: `apply_chat_template()` for Gemma 4 (Temporary Patch)

**Status**: Hardcoded fallback in place. Upstream fix pending in llama.cpp.

**Background**: Gemma 4 introduced a new chat format (`<|turn>role\ncontent<turn|>\n`) that is completely different from Gemma 2/3 (`<start_of_turn>`). llama.cpp's `llama_chat_apply_template()` detects templates via heuristic string matching and does not recognize the new `<|turn>` format → returns -1.

**Current fix** (`custom_files/localllm_capi.cpp`, in `localllm_apply_chat_template()`):
When `llama_chat_apply_template()` returns -1, check `general.architecture` via `llama_model_meta_val_str()`. If `"gemma4"`, apply the format manually:
```
<|turn>system\n{system_content}<turn|>\n
<|turn>user\n{user_content}<turn|>\n
<|turn>model\n<|channel>thought\n<channel|>   ← generation prompt (suppresses thinking by default)
```

**Limitations**: Covers simple conversation only. Tool calls, thinking mode, and multi-modal content are not handled by the fallback.

**Upstream fix needed**: llama.cpp should add `<|turn>` to `llm_chat_detect_template()` in `src/llama-chat.cpp` (or add a Gemma 4 template entry to `llm_chat_apply_template()`). Once merged upstream, our fallback can be removed.

---

## Summary

| Feature | Effort | API Stability | User Value | Priority |
|---------|--------|---------------|------------|----------|
| Embedding | 150-200 lines | **Stable** (llama.h) | High (RAG, search) | **1** |
| Grammar / Structured Output | 50-150 lines | Unstable (common/) | High (JSON output) | **2** |
| Reasoning / Thinking | 200-300 lines | Unstable (common/) | Medium (specific models) | **3** |
| Speculative Decoding | 300-500 lines | Unstable (common/) | High (speed) | **4** |
| Multimodal / Vision | 500-800 lines | Unstable (mtmd/) | High but niche | **5** |

> **Note**: Embedding is the only feature implementable entirely with the stable llama.h C API. All others depend on `common/` internal APIs that may break with llama.cpp upgrades.

---

## Feature: `stop` Parameter for User-Defined Antiprompts (replaces EOG bug fix)

**Background**: `<|start_header_id|>` is intentionally excluded from llama.cpp's EOG whitelist. llama.cpp itself logs "control token: 128006 <|start_header_id|> is not marked as EOG" and handles this via user-supplied `--reverse-prompt`. We decided not to add more hardcoded stop sequences (risk of silently truncating valid output). Instead, expose a `stop` parameter.

**What**: Add `stop = character(0)` to `generate()` and `generate_parallel()`. Each string in `stop` acts as an antiprompt — generation halts and the stop string is trimmed from output when it appears.

**Changes needed**:
| Layer | File | Changes |
|-------|------|---------|
| C bridge | `localllm_capi.cpp` | Add `stop_strings` array param to `localllm_generate()` / `localllm_generate_parallel()`; after appending each token piece, check if `generated_text` ends with any stop string and truncate+break |
| Proxy | `proxy.h/cpp` | Update function signatures |
| Rcpp | `interface.cpp` | Pass `stop` character vector through |
| R | `api.R` | Add `stop = character(0)` to `generate()` and `generate_parallel()` |

**Estimated effort**: ~80-120 lines

---

## EOG Detection Design — Current Implementation (2026-04-16)

### Three-layer architecture

Generation stops via three independent layers, checked in order every token:

**Layer 1 — Single-token EOG (`llama_vocab_is_eog()`)**
- Fires when sampled token is registered as an EOG token in the model's GGUF vocab
- Zero false-positive risk; covers well-behaved models (Gemma, Qwen, Mistral, etc.)

**Layer 2 — Multi-token sequence detection (hardcoded token IDs)**
- Maintains a 7-token sliding window per sequence / slot
- Detects: `<|eot_id|>` = `{27,91,68,354,851,91,29}`, `<|end_header_id|>` = `{27,91,408,8932,851,91,29}`
- Designed for models where these tokens are NOT marked as EOG and get spelled out as multiple ordinary tokens
- **Redundancy**: both strings are already in Layer 3's `text_stop_strings`, so Layer 2 fires first but Layer 3 would have caught the same case. Layer 2 is historical code added before Layer 3 existed; kept because it's harmless and removal needs regression testing on LLaMA 3.
- **Cross-model risk**: IDs are LLaMA 3–specific. For other tokenizers these IDs mean different tokens; a coincidental 7-match would cause wrong truncation (probability extremely low).

**Layer 3 — Text-level stop strings (`text_stop_strings`)**
- After each token is appended to the response, searches within a window of `stop.size() + 4` bytes from the tail (windowed `find`, not full scan)
- On match: erases the response from the match position onward, then breaks

Current list (both `generate()` and `generate_parallel()`):
```
"<turn|>", "<end_of_turn>", "<|eot_id|>", "<|im_end|>",
"<|start_header_id|>", "\n\nUser:", "\n\nHuman:"
```

`\n\nUser:` and `\n\nHuman:` were added 2026-04-16 to replace an older full-response scan in `generate_parallel()` that (a) didn't erase the matched text, (b) was O(n²), and (c) was absent from `generate()`. Moving them into `text_stop_strings` fixes all three issues and keeps both functions in sync.

### False truncation risk

Layer 3's windowed search only fires when a stop string appears at the **current tail** of the response — it cannot trigger on earlier content. Real false-positive scenarios are narrow:

- User asks model to explain LLaMA 3/ChatML chat format → model generates `<|eot_id|>` or `<|im_end|>` literally → truncated
- User asks model to produce a dialogue example → model generates `\n\nUser:` as part of the example → truncated

These are meta-discussion cases. Ordinary Q&A, coding, and writing tasks are unaffected.

### Long-term fix

Expose a user-facing `stop` parameter on `generate()` and `generate_parallel()` (see "Feature: `stop` Parameter" below). This lets callers override stop behavior per-call, reducing reliance on hardcoded lists. The hardcoded lists become a sensible default rather than the only option.

---

## Bug Fix: Robust Multi-Token EOG Detection (Priority: LOW — see feature above)

**Problem**: `generate()` and `generate_parallel()` have incomplete EOG (end-of-generation) detection for Llama 3.x models.

**Root cause**:
- In Llama 3.2 3B's GGUF, control tokens like `<|eot_id|>` and `<|start_header_id|>` are not marked as special tokens, so `llama_vocab_is_eog()` never fires for them
- The current code hardcodes two stop sequences: `<|eot_id|>` = `[27, 91, 68, 354, 851, 91, 29]` and `<|end_header_id|>` = `[27, 91, 408, 8932, 851, 91, 29]`
- In practice, Llama 3.2 3B outputs `<|start_header_id|>assistant<|end_header_id|>\n\n...` after its answer instead of `<|eot_id|>`. The token sequence for `<|start_header_id|>` = `[27, 91, 2527, 8932, 851, 91, 29]` is not in the detection list, so generation never stops

**Scope**: Both `generate()` and `generate_parallel()` are affected equally. Models like Gemma that use proper special tokens for EOS are unaffected.

**Recommended fix**: At model load time, tokenize the known control strings using the model's own tokenizer and build the stop-sequence list dynamically:

1. After loading the model, tokenize `<|eot_id|>`, `<|start_header_id|>`, `<|end_header_id|>`, etc.
2. If the result is a single special token → already handled by `llama_vocab_is_eog()`, skip
3. If the result is multiple ordinary tokens → add to the stop-sequence list; match via sliding window during generation

**Why this is better than adding another hardcoded sequence**:
- Works automatically for any model without hardcoded token IDs
- Gemma and other well-behaved models are completely unaffected
- Future models require no code changes

**Files to change**: `custom_files/localllm_capi.cpp` — `localllm_generate()` (~line 415) and `localllm_generate_parallel()` (~line 1043)

---

## Bug Fix: C-Layer Memory Guard in `c_r_model_load_safe` (Priority: LOW)

**Problem**: The memory check in `model_load()` lives entirely in the R layer (`.check_model_memory_requirements()`). Users who explicitly pass `check_memory = FALSE`, or developers who add a new R function that calls `c_r_model_load_safe` without invoking the R-layer check, bypass all guards. When llama.cpp mmap-loads a file that exceeds physical RAM, macOS OOM-kills the entire R process with no error message — RStudio silently crashes.

**When this matters**:
- User passes `check_memory = FALSE` and the model truly doesn't fit (intentional bypass, but crash is still bad UX)
- Future developer adds a code path that calls `.Call("c_r_model_load_safe", ...)` without calling `.check_model_memory_requirements()` first

**Recommended fix**: Add a lightweight memory check inside `c_r_model_load_safe` in `localllm_capi.cpp`, before the `llama_model_load_from_file()` call. If available memory is below estimated requirement, throw `std::runtime_error` (which Rcpp converts to a clean R `stop()`) instead of proceeding to mmap.

**Note**: This should be treated as a last-resort guard, not a replacement for the R-layer check. The R layer handles interactive user prompts; the C layer should only hard-stop to prevent a crash.

**Files to change**: `custom_files/localllm_capi.cpp` — `localllm_model_load()` or equivalent, before the call to `llama_model_load_from_file()`

---

## Bug Fix: `next_batch` Per-Token Allocation in `generate()` (Priority: LOW — performance)

**Found**: 2026-04-16

**Problem**: In the `generate()` generation loop, a new `llama_batch` is allocated and freed for every single generated token:

```cpp
for (int i = 0; i < max_tokens; ++i) {
    ...
    llama_batch next_batch = llama_batch_init(1, 0, 1);   // ← per-token alloc
    common_batch_add(next_batch, new_token, n_past, {0}, true);
    llama_decode(ctx, next_batch);
    llama_batch_free(next_batch);                          // ← per-token free
}
```

This is the same pattern as the gen_batch issue fixed in `generate_parallel()` (Problem 2, 2026-04-16). For size-1 batches the overhead is small (~microseconds per call), but it's unnecessary and inconsistent with the parallel implementation.

**Fix**: Allocate `llama_batch next_batch = llama_batch_init(1, 0, 1)` once before the loop, reset `next_batch.n_tokens = 0` at the start of each iteration, free once after the loop. Mirror the gen_batch pattern from `generate_parallel()`.

**Files to change**: `backend/llama.cpp/localllm_capi.cpp` — `localllm_generate()`, lines ~597–606

---

## Bug Fix: `ensure_slots_filled` vs `slots_pending_reassign` Double-Assignment (Priority: MEDIUM) ✅ FIXED 2026-04-16

**Found**: 2026-04-16

**Problem**: In `generate_parallel()`, two code paths can assign the same slot simultaneously, causing a prompt to be silently skipped.

**Trigger sequence**:
1. A slot's first sampled token is EOS (e.g. empty prompt, or unusual model behavior)
2. `assign_next_prompt` calls `finalize_slot` → `slot.active = false`, slot added to `slots_pending_reassign`
3. The while-loop's next iteration calls `ensure_slots_filled` (line 1008), which sees `!slot.active` and assigns a NEW prompt to this slot (sampler initialized, `slot.active = true`, `active_clients++`)
4. The same loop iteration later processes `slots_pending_reassign`: `assign_next_prompt` is called again for the same slot, and begins with `release_slot(slot)` — which frees the just-initialized sampler and resets `slot.active = false`
5. The prompt assigned in step 3 is now abandoned: its response stays as an empty string in `final_responses`

**Root cause**: `slots_pending_reassign` is consumed at the END of each loop iteration, but `ensure_slots_filled` at the START of the same iteration may have already handled the slot.

**Fix** — add a single guard in the `slots_pending_reassign` loop (lines ~1213–1218):

```cpp
for (int slot_idx : slots_pending_reassign) {
    if (!slots[slot_idx].active) {   // skip if ensure_slots_filled already reassigned
        assign_next_prompt(slot_idx);
    }
}
```

**Severity**: Low in practice — requires the first sampled token of a prompt to be EOS, which is rare with well-formed chat-templated prompts. But causes a silent result gap (empty string instead of `[ERROR]`) when it does occur.

**Files to change**: `backend/llama.cpp/localllm_capi.cpp` — `localllm_generate_parallel()`, lines ~1213–1218

---

## Code Quality: Dead Code in `generate_parallel()` (Priority: LOW)

**Found**: 2026-04-16

Two unreachable code paths in `generate_parallel()`:

**1. `need_prompt_logit` / `priming` mechanism** (lines ~906, 1029–1034, 1090–1094):
`need_prompt_logit` is set to `slot.suffix_tokens.empty() && slot.n_prompt > 0`. However, `assign_next_prompt` always ensures `suffix_tokens` is non-empty when `n_prompt > 0`: when the entire prompt is the shared prefix, it adjusts `prefix_len` down by 1 and adds the last token to `suffix_tokens`. So `need_prompt_logit` is permanently `false`, and the priming code path never executes. Safe to remove.

**2. Dead `pos` initialization at line ~1027**:
```cpp
int pos = slot.n_past + slot.n_decoded;  // never used
```
Both branches of the following `if/else` (lines 1034 and 1038) overwrite `pos` before it is used. The initial calculation is dead code. Safe to remove.

**No functional impact** — these are pure cleanup items.
