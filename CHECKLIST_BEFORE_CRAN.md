# Checklist Before CRAN Submission

Run through every item below before submitting. Each section records a past failure and how to avoid repeating it.

---

## 1. DESCRIPTION: Do not start with "This package" or the package name

**Past failure (v1.0.1 review):** CRAN reviewer Benjamin Altmann flagged:
> "Please do not start the description with 'This package', package name, title or similar."

**Check:** Open `localLLM/DESCRIPTION`. The `Description:` field must not begin with:
- "This package..."
- "localLLM..."
- The title text
- "A package..."

**Good example:**
```
Description: Provides R bindings to the 'llama.cpp' library for running
    large language models locally...
```

---

## 2. Parallel generation benchmark — record and review results

Run the benchmark and record the numbers:

```bash
Rscript benchmark_parallel.R 2>&1 | tee benchmark_parallel_output.txt
```

**Always report the summary table**, e.g.:
```
Sequential  (n_seq_max=1):   45.4 sec  acc=72.0%
Parallel    (n_seq_max=10):  27.8 sec  acc=72.0%  speedup=1.63x
```

**If parallel is slower than sequential (speedup < 1.0x), do not submit.** This indicates the `seq_cp` fix was lost, likely during a backend upgrade. Investigate `custom_files/localllm_capi.cpp`:
- `assign_next_prompt`: must call `llama_memory_seq_cp(mem, 0, slot.seq_id, -1, -1)` when `prefix_ready && slot.prefix_len > 0`
- `decode_prompt_tokens`: must decode only `slot.suffix_tokens` (not `slot.full_tokens`) when prefix is ready

---

## 4. Run test_vignettes.R and confirm all pass

Vignettes are checked during `R CMD check --as-cran`, but run this script locally first to catch issues early:

```bash
Rscript test_vignettes.R 2>&1 | tee test_vignettes_output.txt
```

Review `test_vignettes_output.txt` and confirm no errors or unexpected warnings. All vignette code chunks must complete successfully.

---

## 5. Standard R-CMD-check items

```bash
# Build the tarball
R CMD build localLLM

# Run full CRAN check
R CMD check --as-cran localLLM_*.tar.gz
```

Status must be:
```
Status: OK
```
or only NOTEs that are acceptable (e.g., "New submission", "unable to verify current time").

No WARNINGs or ERRORs allowed.

---

## 6. Version and NEWS.md

- Bump version in `localLLM/DESCRIPTION`
- Add entry to `localLLM/NEWS.md` describing changes
- Ensure version in `localLLM/R/install.R` (`.lib_version`) matches DESCRIPTION if releasing a new binary

