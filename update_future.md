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

**Update (2026-09-13)**: Upstream llama.cpp (b10948) has landed a different, likely lower-effort path to this feature: native **MTP (Multi-Token Prediction)** speculative decoding, built as a first-class framework (`llm_graph_input_mtp`, dedicated per-model support) rather than the generic `common/speculative.h` draft-model API described above. MTP is a small auxiliary prediction head trained directly into the model checkpoint — no separate draft model needed. Currently supported for DeepSeek V3.2/V4, GLM-4.5-Air/4.7-Flash/5.2, Qwen3-Next/3.5, Kimi-K3, MiMo V2, Hy3, Nemotron, and Gemma4. Re-evaluate effort estimate against this path when the backend is upgraded — but note MTP only benefits large MoE models that ship MTP weights; it does **not** apply to the small dense models we currently document (Gemma-3-4B, Llama-3.2-3B), so the generic `common/speculative.h` approach may still be needed for those. See the version-gap investigation notes at the end of this file for full detail.

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

## Bug: `generate_parallel()` Prefix Sharing on Recurrent/Hybrid Models (Priority: HIGH) — CONFIRMED 2026-10-24

**Found**: 2026-10-24, by code reading during the b11869 upgrade analysis. **Reproduced the same day** with LFM2-350M (`lfm2`, hybrid), Q4_K_M, on macOS Metal. It happens **identically on b8766 (1.3.0 + PR #7) and on b11869**, so current users are affected.

**Reproduction results** (4 prompts, `temperature = 0`, each result compared with `generate()` on the same prompt):

| Prompt set | `n_seq_max = 4` (3 slots) | `n_seq_max = 5` (4 slots) |
|---|---|---|
| 4 identical prompts | 4/4 `[ERROR] Failed to decode prompt tokens` | 4/4 `[ERROR]` |
| 4 prompts with a 34-token shared system prompt | 1/4 `[ERROR]` (the prompt on the reused slot) | 0/4, all match `generate()` |
| 4 unrelated prompts (4-token shared template header) | 1/4 `[ERROR]` (the prompt on the reused slot) | 0/4, all match `generate()` |
| 12 unrelated short prompts | 0/12 (with `max_tokens` 20, 30 and 60) | — |

The backend log for each failure is `init: the tokens of sequence 1 in the input batch have inconsistent sequence positions … X = n_prompt-1 … Y = n_prompt-1`.

There are two distinct failure modes:
1. **prompt == shared prefix** (identical prompts): explained below, and always fails.
2. **Reused slot**: this fails only sometimes (1/4 in two sets, 0/12 in another), and the **root cause is not yet identified**. At the moment of the prompt decode, the reused sequence already holds positions up to `n_prompt-1`, which suggests that recurrent state from the shared seq 0 or from the slot's previous occupant was not reset or copied correctly. Debug it by logging slot index, `prefix_len`, `shared_prefix_len` and `llama_memory_seq_pos_max()` before and after `seq_rm`/`seq_cp`. Dense models (SmolLM2, Qwen2.5, Qwen3, Gemma 4) never fail in either mode.

**Original analysis** (failure mode 1):

**Problem**: If a prompt's tokens consist entirely of the shared prefix, `generate_parallel()` copies seq 0's full prefix KV into the slot (`llama_memory_seq_cp(mem, 0, slot.seq_id, -1, -1)`). It then calls a **partial** `llama_memory_seq_rm(mem, slot.seq_id, slot.prefix_len, -1)` to drop the last position, so that the final token can be re-decoded to produce logits. Recurrent/hybrid memory cannot erase part of a sequence's state. The call returns `false` without changing the cache, and **we ignore the return value**.

**Trigger**: prefix sharing is active and some prompt == the shared prefix. Most commonly this means **all prompts are identical**, e.g. `generate_parallel(ctx, rep(prompt, 5))` for repeated sampling or intercoder-reliability runs. It also happens when one prompt is a token-prefix of every other prompt.

**Why it fails** (verified in b11869 `src/llama-memory-recurrent.cpp`, `seq_rm`): partial rollback is only possible through per-token snapshots, bounded by the new context param `n_rs_seq`. Its default is 0 and we don't set it. Even with snapshots, rollback is refused when the state cell is shared by several sequences, which it always is right after `seq_cp(0 → slot)`. `llama_memory_hybrid::seq_rm` tries the recurrent part first and returns `false` if that fails.

**Symptom** (confirmed 2026-10-24): the suffix decode re-submits position `n_prompt - 1`, which still exists in that sequence, so `llama_decode` rejects the batch. That prompt returns `"[ERROR] ..."` instead of text, without crashing R. With identical prompts, every result would be an error.

**Scope — not new with the upgrade**: b8766 (1.3.0) already supports 18 recurrent/hybrid archs. Recurrent: `mamba`, `mamba2`, `rwkv6`, `rwkv6qwen2`, `rwkv7`, `arwkv7`. Hybrid: `jamba`, `falcon-h1`, `plamo2`, `granitehybrid`, `lfm2`, `lfm2moe`, `nemotron_h`, `nemotron_h_moe`, `qwen3next`, `kimi-linear`, `qwen35`, `qwen35moe`. This includes the popular Qwen3.5 family. b11869 adds 6 more hybrid archs: `bailingmoe3`, `kimi-k3`, `glm5-next`, `qwen4exp`, `deepseek4`, `minimax-01`. Current 1.3.0 users may therefore already be affected.

**Test plan** (after the upgrade, before advertising new-model support; can also be run on 1.3.0 now):
1. Load a small hybrid model (e.g. LFM2-350M, or a small Qwen3.5 / Granite-4.0-H GGUF), plus a dense model as a control.
2. Run `generate_parallel()` with (a) 4 identical prompts, (b) 4 prompts with a long shared prefix but different endings, (c) 4 unrelated prompts.
3. At `temperature = 0`, compare each result with `generate()` on the same prompt. Expect seq == par, and watch for `"[ERROR]"` or empty strings.

**Candidate fix**: check the return value of the partial `llama_memory_seq_rm()`. On `false`, fall back to `llama_memory_seq_rm(mem, slot.seq_id, 0, -1)` (full removal always works) and decode that slot's full prompt without prefix sharing. Simpler alternative: skip prefix sharing when `llama_model_is_recurrent(model) || llama_model_is_hybrid(model)`; both functions exist in b8766 and b11869.

**Files to change**: `backend/llama.cpp/localllm_capi.cpp` — `localllm_generate_parallel()`: slot assignment (~lines 892–900) and the `seq_cp`/`seq_rm` block (~lines 940–948).

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

---

## Investigation: llama.cpp Backend Version Gap & Reproducibility (2026-09-13)

**Method**: Compared our backend commit (b8766, 2026-04-12) against the latest upstream tag (b10948, 2026-09-13) using the `backend/llama.cpp` submodule's local git history directly (`git log b8766..b10948`), instead of the GitHub API, to avoid the 60 req/hour anonymous rate limit.

### Version gap

- **2182 commits, ~5 months, 2794 files changed, +580,011 / -187,333 lines.** Not a routine bump — should be scoped as its own project, not folded into an unrelated change.
- The core stable API our C bridge depends on is **unchanged**: `llama_batch_init` and `llama_decode` have byte-identical signatures in `include/llama.h` between b8766 and b10948, and `llama_memory_seq_cp`/`seq_rm`/`seq_add` (used for prefix sharing in `generate_parallel()`) are also unchanged. Upgrading carries low risk of breaking our `localllm_capi.cpp` slot logic specifically.
- The one commit that looked relevant, `server: abstract llama_memory calls to common_memory (#26221)`, only touches `common/common.cpp`, `common/common.h`, and `tools/server/server-context.cpp` — internal refactor of the `llama-server` binary we don't link against. Not relevant to us.
- `llama_set_warmup()` was deprecated (#24009) — not used anywhere in our codebase, no impact.
- `--mmap`/`--mlock`/`--dio` CLI flags were deprecated in favor of a unified `--load-mode`, but this is at the `common/arg.cpp` CLI-parsing layer. Our `localllm_capi.cpp` sets `llama_model_params.use_mmap`/`use_mlock` struct fields directly (not via CLI args), which should be unaffected — but re-verify at upgrade time. **Correction (2026-10-24)**: wrong — by b11869 the `use_mmap`/`use_mlock` struct fields themselves are removed (see the b11869 analysis below).

### Model / quantization coverage gap (the real reason to upgrade)

New model architectures merged since b8766 that our current backend **cannot load**: DeepSeek V3.2/V4 (new sparse attention, "DSA"), GLM-4.5-Air/4.7-Flash/5.2, Kimi-K3, MiniMax-M3, Qwen3-Next/Qwen3.8-Flash-Next, BailingMoE3, EXAONE 4.5, Tencent Hy3/Hy_v4, NVIDIA Nemotron-3-Puzzle-75B, MiMo V2, and others. Also new **NVFP4** quantization support (NVIDIA's 4-bit float format with block-wise FP8 microscaling) — GGUF files exported in NVFP4 will fail to load on b8766 regardless of architecture. Model-architecture coverage has historically been the primary driver for backend bumps in this project (the b7825→b8664 bump was specifically for "18 new architectures" per NEWS.md) — this is the strongest concrete justification for the next upgrade.

**Correction (2026-10-24)**: overstated. b8766 already has arch entries for `qwen3next`, `mimo2`, `glm4moe` (GLM-4.5-Air / 4.7), `exaone4`, `nemotron_h` and `bailingmoe2`, and `GGML_TYPE_NVFP4` (type 40) already exists in b8766's `ggml.h`; only the `GGML_FTYPE_MOSTLY_NVFP4` file type is new. The verified list of new arch names is in the b11869 analysis below.

### Multi-GPU gap (candidate new roadmap item, not yet numbered above)

Per current upstream `docs/multi-gpu.md`, llama.cpp exposes three `--split-mode` options: `layer` (pipeline parallel across GPUs, default, tolerant of slow interconnect), `row` (deprecated), and `tensor` (true tensor parallelism with cross-GPU AllReduce, EXPERIMENTAL, best on multi-NVIDIA-GPU + CUDA + fast interconnect). **Our `model_load()` exposes none of `tensor_split` / `split_mode` / `main_gpu` — only `n_gpu_layers`.** A user with multiple GPUs cannot split a model across them through our package today; behavior is whatever the backend's internal default does. If we ever get reports of multi-GPU workstation users, exposing `split_mode`/`tensor_split` (starting with the more mature `layer` mode, treating `tensor` as experimental/opt-in) would be a natural, low-risk addition — it only requires passing two more params down through the existing `model_load()` C bridge, no generation-loop changes.

### Reproducibility findings

Investigated whether "same seed + same backend binary + same hardware + same `n_threads`/GPU choice" guarantees bit-identical output (prompted by comparing to vLLM's `VLLM_ENABLE_V1_MULTIPROCESSING=0` reproducibility knob — not a direct analogue, since llama.cpp's core library has no async multi-process scheduler; its non-determinism sources are purely numerical/kernel-level).

- **CPU**: `ggml-cpu` core ops use static, thread-id-indexed strided loops (`for (i = ith; i < n; i += nth)`), i.e. deterministic work partitioning given a fixed `n_threads` — not a race-based reduction. No `atomic*`-based float accumulation found in core CPU ops. CPU-only inference should be reproducible in practice given fixed seed + fixed `n_threads`.
- **CUDA**: Confirmed current `ggml/src/ggml-cuda/ggml-cuda.cu` still calls `cublasGemmEx(..., CUBLAS_GEMM_DEFAULT_TENSOR_OP)` for GEMM. NVIDIA's own cuBLAS documentation states results are **not guaranteed to be bit-reproducible run-to-run** — this has been a known, documented llama.cpp caveat since 2023 (original fix was `GGML_CUDA_MAX_STREAMS=1`; the macro still exists in `ggml/src/ggml-cuda/common.cuh` but the warning is no longer surfaced in current README/docs). No widespread `atomicAdd` usage found in core CUDA matmul/flash-attention kernels (only in `count-equal.cu`), so this risk is specific to cuBLAS's own internal algorithm selection, not our/ggml's hand-written kernels.
- **MoE routing**: `opencl: make the MoE expert scatter deterministic (#26464)` (2026-08-19) confirms MoE expert routing/scatter had at least one non-determinism bug on the OpenCL backend; unclear whether analogous issues exist or have been fixed on CUDA/Vulkan. Only relevant to MoE models — none of our currently-documented example models (Gemma-3-4B, Llama-3.2-3B) are MoE.
- **`generate_parallel()` caveat**: batch composition (how many/which sequences are decoded together) can route to different GEMM kernel/tiling code paths purely based on batch shape — a source of variance orthogonal to seed/hardware/thread-count, not evaluated here.
- **Empirical spot-check** (2026-09-13, localLLM 1.3.0, Apple M3 Pro / Metal, `n_gpu_layers = -1`, Qwen3-4B-Thinking Q8_0, `~/.llamabarn/qwen3-4b-thinking-2507-q8_0.gguf`): 3/3 identical runs at `temperature=0, seed=42`, and 3/3 identical runs at `temperature=0.8, seed=42`. Small sample size; Metal only (does not confirm/refute the CUDA cuBLAS concern above, since Metal doesn't go through cuBLAS); dense model only (does not exercise the MoE routing risk above).

**Action item**: Consider adding a disclaimer to `vignettes/reproducible-output.Rmd` — the `identical()` guarantee is well-grounded on CPU (static thread partitioning), but on GPU (especially CUDA) it is better described as "holds in practice, not a guaranteed property," and MoE models carry an additional routing-determinism risk not present in the dense models currently used in the vignette's examples.

---

## Backend Upgrade Analysis: b8766 → b11869 (2026-10-24)

**Method**: Checked out upstream tag **b11869** (2026-10-24) in the `backend/llama.cpp` submodule, 3103 commits after b8766. Built an inventory of every llama.cpp symbol `localllm_capi.cpp` uses (44 `llama_*` functions, 12 `common_*` symbols, 4 `ggml_*` symbols), then diffed each declaration, every struct field we set, the default param values, and our `CMakeLists.txt.custom` / CI against the new tree. **No code has been changed yet.** The submodule is checked out at b11869 locally, but the pointer is not committed.

**Bottom line**: the core `llama.h` API we use is unchanged. The breakage is in `common/` and in the build system. All required C-bridge changes are mechanical adaptations that preserve behaviour. The R ⇄ C-bridge ABI is unaffected, so the R package needs only a version bump. Estimated effort is a few dozen lines, and the main risk is CMake/Metal across the 7 release platforms.

### Compile/build breaks

**C bridge (`localllm_capi.cpp`)**

| # | Upstream change | Our usage | Fix |
|---|---|---|---|
| 1 | `common_batch_add()` removed (`60e9cf7a7`, 2026-09-30; upstream moved its own code to the new `llama_batch_ext` API) | 5 call sites: `generate()` prompt + per-token batch, `generate_parallel()` shared prefix, suffix, and per-step gen batch | Add a local copy of the old ~10-line helper (it only fills the `llama_batch` arrays). The legacy `llama_batch_init`/`llama_decode(llama_batch)` path is still native and not marked deprecated, and the `llama_batch` struct layout is byte-identical, so our aggregate-initialised batch views stay valid |
| 2 | `llama_model_params.use_mmap`/`use_mlock`/`use_direct_io` removed in favour of `enum llama_load_mode load_mode` (`e6dd0e29a`); the new default is `LLAMA_LOAD_MODE_AUTO` | `localllm_model_load()` and `localllm_model_load_safe()` (6 lines) | Map the two R booleans onto the enum (TRUE/FALSE→`AUTO` or `MMAP`, TRUE/TRUE→`MMAP_MLOCK`, FALSE/TRUE→`MLOCK`, FALSE/FALSE→`NONE`). `AUTO` = mmap, except it falls back to no-mmap on devices without mmap support (e.g. some iGPUs) |
| 3 | `common_chat_params.prompt` changed from `std::string` to `common_chat_prompt` (`ff026f8c0`, 2026-10-14) | Jinja fallback in `localllm_apply_chat_template()` | `params.prompt.str()` |
| 4 | `common_chat_params.thinking_end_tag` (string) → `thinking_end_tags` (vector) | Gemma 4 pre-closed-thinking strip | Loop over the vector. Gemma 4's parser still reports `{"<channel|>"}`, so behaviour is unchanged |

**Build (`CMakeLists.txt.custom`)**

| # | Upstream change | Impact |
|---|---|---|
| 5 | Library target `common` renamed `llama-common` (`build_info` → `llama-common-base`) | Our link line, the macOS/Linux/Windows whole-archive flags, and `check_static_library_completeness` all reference `common`, so CMake configure fails |
| 6 | `vendor/` now has its own CMakeLists; `llama-common` links `vendor::nlohmann` and `vendor::sheredom` | Replace `add_subdirectory(vendor/cpp-httplib)` with `add_subdirectory(vendor)`. Optionally set `LLAMA_SUBPROCESS=OFF`, since it is only needed by server tools |
| 7 | `ggml-metal.metal` split into 41 `kernels/*.metal` files; new `ggml-metal-fusion.cpp` and `ggml-metal-tuning.cpp` | Our hand-written Metal source list and custom embed block break. Recommended: drop them and rely on upstream's `ggml-metal` target, which already embeds the library when `GGML_METAL_EMBED_LIBRARY=ON`. **Highest-risk item**: verify on both arm64 and x86_64 macOS |

**CI**

| # | Change |
|---|---|
| 8 | Linux Vulkan: `find_package(SPIRV-Headers CONFIG REQUIRED)` was added (`a6d6183db`), so add `spirv-headers` to the apt install. Windows `choco install vulkan-sdk` presumably ships it (unverified) |
| 9 | `scripts/check_symbols.sh:72` hardcodes `common/libcommon.a` (now `libllama-common.a`) |

### Verified unchanged

- All 44 `llama.h` functions we call: identical declarations (tokenize/detokenize, decode, batch init/free, `llama_memory_*` incl. `seq_cp`/`seq_rm`, chat template, metadata, vocab queries).
- `llama_batch` struct layout, and the `llama_context_params` fields we set (`n_ctx`, `n_threads`, `n_threads_batch`, `n_seq_max`) and their defaults.
- `common_sampler_init/sample/accept/free`, `common_params_sampling` fields we set, the default sampler chain order, and `common_token_to_piece`.
- `common_chat_templates_init` signature, `common_chat_msg.role/content`, `enable_thinking = true` default, and leading-BOS stripping in the Jinja path.
- C++17, and all CMake options our CI passes (`GGML_NATIVE`, `GGML_AVX512`, `GGML_METAL_EMBED_LIBRARY`, `GGML_VULKAN`, …).
- Batch validation: the only new `llama_batch_allocr::init` errors concern embedding/state inputs. Our batches are token-only with strictly increasing positions per sequence, so none apply.
- New context param `n_outputs_max_per_seq` (default 1) is only enforced for backend sampling. We sample on CPU via `common_sampler` (`backend_sampling = false`), so it does not apply.
- Roadmap APIs: `llama_set_embeddings`, `llama_get_embeddings_seq/ith`, `llama_pooling_type`, `llama_sampler_init_grammar`, `common_grammar`, so items 1–2 are unaffected.

### Functional impact on `generate()` / `generate_parallel()`

None of fixes 1–4 changes what our code does: they rename or re-wrap the same operations. Slot management, prefix sharing (`seq_cp` + partial `seq_rm`), stop-string handling, and batch splitting are untouched. User-visible differences come only from **upstream internals**:

1. **Outputs differ from 1.3.0 for the same seed.** This is combined with PR #7 (special-token parsing), so NEWS and `reproducible-output.Rmd` must say so.
2. **`temperature = 0` now uses the greedy sampler directly** (`d0b490f25`) instead of temp(≤0 keeps the max logit) + dist. Equivalent in practice and faster; tie-breaking may differ in rare cases.
3. **`repeat_last_n = -1` now silently means "disabled"**, where it used to mean "whole context" (`a6aa6f545`; values are clamped to ≥0). We never documented -1. Consider rejecting negatives in R.
4. **Metal flash-attention parameters are now tuned per chip** (`f280b2698` + M3 Max/M4 Pro/M5 tunings). Same-machine reproducibility is unaffected, but cross-chip identical output becomes less likely.
5. **Bug fixes we inherit**: Metal MoE-reduce fusion race (`098ce526b`), ggml-cpu heap corruption (`2f539596c`), and several KV-cache restore/rollback fixes for MoE/hybrid models.
6. **Caveat (pre-existing, not caused by the upgrade)**: prefix sharing calls a partial `llama_memory_seq_rm()` that recurrent/hybrid memory refuses, and we ignore the return value. b8766 already loads 18 such archs (incl. Qwen3.5), and b11869 adds 6 more. See **"Bug: `generate_parallel()` Prefix Sharing on Recurrent/Hybrid Models"** above (confirmed 2026-10-24) for the trigger, the test plan, and a candidate fix. Run that test after the upgrade, before advertising new-model support.

### New capabilities

- **38 new architecture names** (126 → 164), e.g. `deepseek32`, `deepseek4`, `glm5-next`, `kimi-k3`, `minimax-m3`, `minimax-01`, `qwen4exp`, `cohere2moe`, `bailingmoe3`, `granite_swa`, `graniteswitch`, `hy_v3`, `hy_v4`, `gemma-embedding2`, `hunyuan_vl`, plus TTS models (`qwen3tts`, `pockettts`) that are irrelevant to us. New quant type `Q2_0`.
- **Prompt parts with an `is_input` flag** (`ff026f8c0`): the Jinja engine now marks which spans of the rendered prompt came from user input. This is the upstream mechanism to resolve PR #7's trade-off (literal `<|im_end|>` inside user documents). Upstream itself still flattens it with `.str()`. The C-API path (`llama_chat_apply_template`) returns a plain string and carries no part info.
- **MTP speculative decoding** (`load_mtp`, `LLAMA_CONTEXT_TYPE_MTP`), relevant to roadmap item 4.
- **Reasoning budget sampler** improvements (multiple end tags, injected message, runtime control), relevant to roadmap item 3.
- **GPU cache for MoE experts kept in host memory** (`moe_cache_size`, experimental).
- The new `llama_batch_ext` API. Migrating is optional for now and should be its own task once the legacy API is formally deprecated.

### Recommended upgrade order

1. C bridge fixes 1–4 → 2. CMake fixes 5–7 → 3. local macOS build + A/B regression (SmolLM2-135M, Qwen2.5-0.5B, Qwen3-4B; `generate()` and `generate_parallel()`; seq == par) → 4. CI fixes 8–9 → 5. full release build on all 7 platforms + `smoke-test.yml` → 6. bump `.lib_version` in `install.R`, update NEWS (PR #7 + backend), and submit to CRAN.
