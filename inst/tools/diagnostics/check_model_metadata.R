#!/usr/bin/env Rscript

# Inspect metadata reported by localLLM for a given model
library(localLLM)

cat("=== Inspecting model metadata ===\n\n")

model_path <- Sys.getenv("LOCALLLM_MODEL_PATH", "<path-to-your-model>.gguf")

if (!file.exists(model_path)) {
  cat("Model file not found.\n")
  quit(status = 1)
}

info <- file.info(model_path)
cat("File information:\n")
cat(sprintf("  path: %s\n", model_path))
cat(sprintf("  size: %.1f MB\n", info$size / (1024 * 1024)))

if (!lib_is_installed()) {
  install_localLLM()
}

tryCatch({
  cat("\nLoading model to gather details...\n")
  model <- model_load(model_path, n_gpu_layers = 0L, verbosity = 2L)

  cat("\nInformation printed during load includes architecture, vocabulary size, and special token hints.\n")

  cat("\nSampling special tokens:\n")
  test_tokens <- c("<s>", "</s>", "[INST]", "[/INST]", "<<SYS>>", "<</SYS>>", 
                   "<|im_start|>", "<|im_end|>", "<start_of_turn>", "<end_of_turn>")
  
  for (token in test_tokens) {
    tryCatch({
      tokenized <- tokenize(model, token)
      cat(sprintf("  %s: tokenID=%s\n", token, paste(tokenized, collapse=",")))
    }, error = function(e) {
      cat(sprintf("  %s: could not be tokenized\n", token))
    })
  }
  
  cat("\nChat template preview:\n")
  simple_msg <- list(list(role = "user", content = "Hi"))
  
  # apply_chat_template (automatic detection)
  result_auto <- apply_chat_template(model, simple_msg)
  cat(sprintf("apply_chat_template (auto): '%s'\n", gsub("\n", "\\n", result_auto)))
  
  # smart_chat_template
  result_smart <- smart_chat_template(model, simple_msg)
  cat(sprintf("smart_chat_template: '%s'\n", gsub("\n", "\\n", result_smart)))
  
  rm(model)
  backend_free()
  
}, error = function(e) {
  cat("❌ Inspection failed:", e$message, "\n")
  tryCatch(backend_free(), error = function(e2) {})
})
cat("\nMetadata inspection complete.\n")
