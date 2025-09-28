#!/usr/bin/env Rscript

# Clean up any stuck download lock files
library(localLLM)

# Get the model cache directory
cache_dir <- get_model_cache_dir()
cat("Cache directory:", cache_dir, "\n")

# Find and remove any .lock files
lock_files <- list.files(cache_dir, pattern = "\\.lock$", full.names = TRUE, recursive = TRUE)
if (length(lock_files) > 0) {
  cat("Found lock files:", lock_files, "\n")
  for (lock_file in lock_files) {
    if (file.exists(lock_file)) {
      cat("Removing lock file:", lock_file, "\n")
      file.remove(lock_file)
    }
  }
  cat("Lock files cleaned up.\n")
} else {
  cat("No lock files found.\n")
}

# Also check for any partial downloads
partial_files <- list.files(cache_dir, pattern = "gemma-3-12b-it-q4_0\\.gguf", full.names = TRUE, recursive = TRUE)
for (partial_file in partial_files) {
  file_size <- file.info(partial_file)$size
  if (!is.na(file_size) && file_size < 1024 * 1024) {  # Less than 1MB, likely partial
    cat("Removing partial download:", partial_file, "(", file_size, "bytes)\n")
    file.remove(partial_file)
  }
}