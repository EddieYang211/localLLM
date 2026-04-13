library(localLLM)

cat("=== Parallel vs Sequential Benchmark ===\n\n")

# ─── Setup ────────────────────────────────────────────────────────────────────
cached <- list_cached_models()
llama_path <- cached$path[grepl("gemma", cached$name, ignore.case = TRUE)][1]
if (is.na(llama_path)) stop("Gemma model not found in cache")
cat("Model:", basename(llama_path), "\n\n")

data("ag_news_sample", package = "localLLM")
n        <- nrow(ag_news_sample)
ctx_size <- 512L   # per-sequence context (same for both modes)
n_seq    <- 10L    # parallel sequences
max_tok  <- 50L

# ─── Load model & build prompts ───────────────────────────────────────────────
model <- model_load(llama_path, n_gpu_layers = 999)
cat(sprintf("GPU layers requested: %d (check Metal buffer in log above)\n\n", 999L))

cat("Building", n, "prompts...\n")
all_prompts <- sapply(seq_len(n), function(i) {
  apply_chat_template(model, list(
    list(role = "system",
         content = "You are a text classifier. Respond with exactly one word."),
    list(role = "user", content = paste0(
      "Classify the following news article into exactly one category: ",
      "World, Sports, Business, or Sci/Tech.\n\n",
      "Title: ", ag_news_sample$title[i], "\n",
      "Description: ", ag_news_sample$description[i], "\n\n",
      "Category (one word only):"
    ))
  ))
})
cat(sprintf("Prompts ready. ctx_size=%d  max_tokens=%d\n\n", ctx_size, max_tok))

clean_pred <- function(x) trimws(gsub("\n.*", "", trimws(x)))

# ─── Sequential: n_seq_max=1 ──────────────────────────────────────────────────
cat("--- SEQUENTIAL (n_seq_max=1) ---\n")
ctx_seq <- context_create(model, n_ctx = ctx_size, n_seq_max = 1L)

t_seq <- system.time({
  results_seq <- character(n)
  for (i in seq_len(n)) {
    results_seq[i] <- generate(ctx_seq, all_prompts[i],
                               max_tokens = max_tok, seed = 92092,
                               clean = FALSE)
    if (i %% 25 == 0) cat("  ", i, "/", n, "\n")
  }
})
acc_seq <- mean(clean_pred(results_seq) == ag_news_sample$class, na.rm = TRUE)
cat(sprintf("Time: %.1f sec  |  Accuracy: %.1f%%\n\n",
            t_seq["elapsed"], acc_seq * 100))

# ─── Parallel: n_seq_max=10 ───────────────────────────────────────────────────
cat(sprintf("--- PARALLEL (n_seq_max=%d) ---\n", n_seq))
ctx_par <- context_create(model, n_ctx = ctx_size * n_seq, n_seq_max = n_seq)

t_par <- system.time({
  results_par <- generate_parallel(
    ctx_par, all_prompts,
    max_tokens = max_tok, seed = 92092,
    progress = TRUE, clean = FALSE
  )
})
acc_par <- mean(clean_pred(results_par) == ag_news_sample$class, na.rm = TRUE)
cat(sprintf("Time: %.1f sec  |  Accuracy: %.1f%%\n\n",
            t_par["elapsed"], acc_par * 100))

# ─── Summary ──────────────────────────────────────────────────────────────────
speedup <- t_seq["elapsed"] / t_par["elapsed"]
pct     <- 100 / speedup

cat("=== SUMMARY ===\n")
cat(sprintf("Sequential  (n_seq_max=1):   %.1f sec  acc=%.1f%%\n",
            t_seq["elapsed"], acc_seq * 100))
cat(sprintf("Parallel    (n_seq_max=%d):  %.1f sec  acc=%.1f%%  speedup=%.2fx\n",
            n_seq, t_par["elapsed"], acc_par * 100, speedup))
cat(sprintf("Parallel = %.0f%% of sequential time\n", pct))
