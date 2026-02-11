# =============================================================================
# API Consistency Check for localLLM Vignettes
# =============================================================================
# This script checks for API inconsistencies between vignette examples and
# the actual function implementations.
# =============================================================================

cat("\n=== API Consistency Check ===\n\n")

# Helper function to extract formal arguments
check_function_params <- function(func_name, expected_params) {
  # Get the function from the package namespace
  func <- tryCatch(
    getFromNamespace(func_name, "localLLM"),
    error = function(e) NULL
  )

  if (is.null(func)) {
    cat(sprintf("✗ Function '%s' not found\n", func_name))
    return(FALSE)
  }

  actual_params <- names(formals(func))
  missing_params <- setdiff(expected_params, actual_params)

  if (length(missing_params) > 0) {
    cat(sprintf("✗ %s: Missing parameters: %s\n",
                func_name, paste(missing_params, collapse = ", ")))
    cat(sprintf("  Actual parameters: %s\n", paste(actual_params, collapse = ", ")))
    return(FALSE)
  }

  cat(sprintf("✓ %s: All parameters valid\n", func_name))
  return(TRUE)
}

# Check quick_llama parameters
cat("Checking quick_llama...\n")
check_function_params("quick_llama", c(
  "prompt", "model", "n_threads", "n_gpu_layers", "n_ctx",
  "max_tokens", "temperature", "top_p", "top_k", "verbosity",
  "repeat_last_n", "penalty_repeat", "min_p", "system_prompt",
  "auto_format", "chat_template", "stream", "seed", "progress",
  "clean", "hash"
))

# Check model_load parameters
cat("\nChecking model_load...\n")
check_function_params("model_load", c(
  "model_path", "cache_dir", "n_gpu_layers", "use_mmap", "use_mlock",
  "show_progress", "force_redownload", "verify_integrity",
  "check_memory", "hf_token", "verbosity"
))

# Check context_create parameters
cat("\nChecking context_create...\n")
check_function_params("context_create", c(
  "model", "n_ctx", "n_threads", "n_seq_max", "verbosity"
))

# Check apply_chat_template parameters
cat("\nChecking apply_chat_template...\n")
check_function_params("apply_chat_template", c(
  "model", "messages", "template", "add_assistant"
))

# Check generate parameters
cat("\nChecking generate...\n")
check_function_params("generate", c(
  "context", "prompt", "max_tokens", "top_k", "top_p",
  "temperature", "repeat_last_n", "penalty_repeat", "seed",
  "clean", "hash"
))

# Check generate_parallel parameters
cat("\nChecking generate_parallel...\n")
check_function_params("generate_parallel", c(
  "context", "prompts", "max_tokens", "top_k", "top_p",
  "temperature", "repeat_last_n", "penalty_repeat", "seed",
  "progress", "clean", "hash"
))

# Check tokenize parameters
cat("\nChecking tokenize...\n")
check_function_params("tokenize", c("model", "text", "add_special"))

# Check detokenize parameters
cat("\nChecking detokenize...\n")
check_function_params("detokenize", c("model", "tokens"))

# Check explore parameters
cat("\nChecking explore...\n")
check_function_params("explore", c(
  "models", "instruction", "prompts", "engine", "batch_size",
  "reuse_models", "sink", "progress", "clean", "keep_prompts",
  "hash", "chat_template", "system_prompt"
))

# Check validate parameters
cat("\nChecking validate...\n")
check_function_params("validate", c(
  "annotations", "gold", "pairwise", "label_levels",
  "sample_col", "model_col", "label_col", "truth_col",
  "method", "include_confusion", "include_reliability"
))

# Check compute_confusion_matrices parameters
cat("\nChecking compute_confusion_matrices...\n")
check_function_params("compute_confusion_matrices", c(
  "annotations", "gold", "pairwise", "label_levels",
  "sample_col", "model_col", "label_col", "truth_col"
))

# Check intercoder_reliability parameters
cat("\nChecking intercoder_reliability...\n")
check_function_params("intercoder_reliability", c(
  "annotations", "method", "label_levels",
  "sample_col", "model_col", "label_col"
))

# Check annotation_sink_csv parameters
cat("\nChecking annotation_sink_csv...\n")
check_function_params("annotation_sink_csv", c("path", "append"))

# Check list_cached_models parameters
cat("\nChecking list_cached_models...\n")
check_function_params("list_cached_models", c("cache_dir"))

# Check list_ollama_models parameters
cat("\nChecking list_ollama_models...\n")
# This function has no parameters
func <- tryCatch(
  getFromNamespace("list_ollama_models", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'list_ollama_models' not found\n")
} else {
  cat("✓ list_ollama_models: Function exists\n")
}

# Check hardware_profile parameters
cat("\nChecking hardware_profile...\n")
func <- tryCatch(
  getFromNamespace("hardware_profile", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'hardware_profile' not found\n")
} else {
  cat("✓ hardware_profile: Function exists\n")
}

# Check set_hf_token parameters
cat("\nChecking set_hf_token...\n")
func <- tryCatch(
  getFromNamespace("set_hf_token", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'set_hf_token' not found\n")
} else {
  cat("✓ set_hf_token: Function exists\n")
}

# Check lib_is_installed parameters
cat("\nChecking lib_is_installed...\n")
func <- tryCatch(
  getFromNamespace("lib_is_installed", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'lib_is_installed' not found\n")
} else {
  cat("✓ lib_is_installed: Function exists\n")
}

# Check install_localLLM parameters
cat("\nChecking install_localLLM...\n")
func <- tryCatch(
  getFromNamespace("install_localLLM", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'install_localLLM' not found\n")
} else {
  actual_params <- names(formals(func))
  cat(sprintf("✓ install_localLLM: Function exists with params: %s\n",
              paste(actual_params, collapse = ", ")))
}

# Check document_start parameters
cat("\nChecking document_start...\n")
func <- tryCatch(
  getFromNamespace("document_start", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'document_start' not found\n")
} else {
  cat("✓ document_start: Function exists\n")
}

# Check document_end parameters
cat("\nChecking document_end...\n")
func <- tryCatch(
  getFromNamespace("document_end", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'document_end' not found\n")
} else {
  cat("✓ document_end: Function exists\n")
}

# Check download_model parameters
cat("\nChecking download_model...\n")
check_function_params("download_model", c(
  "model_url", "output_path", "show_progress",
  "verify_integrity", "max_retries", "hf_token"
))

# Check get_model_cache_dir
cat("\nChecking get_model_cache_dir...\n")
func <- tryCatch(
  getFromNamespace("get_model_cache_dir", "localLLM"),
  error = function(e) NULL
)
if (is.null(func)) {
  cat("✗ Function 'get_model_cache_dir' not found\n")
} else {
  cat("✓ get_model_cache_dir: Function exists\n")
}

cat("\n=== API Consistency Check Complete ===\n")
cat("\nNote: This check verifies that parameters used in vignette examples\n")
cat("match the actual function signatures in the package.\n")
