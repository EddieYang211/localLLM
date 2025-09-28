#!/usr/bin/env Rscript

# Setup script to help user set HuggingFace token
cat("To fix the authentication issue, you need to set your HuggingFace token.\n\n")

cat("Step 1: Get your token from https://huggingface.co/settings/tokens\n")
cat("Step 2: Set it as environment variable:\n")
cat("   export HF_TOKEN=your_token_here\n\n")

cat("Or you can set it in R for this session:\n")
cat("   Sys.setenv(HF_TOKEN = 'your_token_here')\n\n")

# Check if token is already set
hf_token <- Sys.getenv("HF_TOKEN", unset = NA)
if (is.na(hf_token) || nchar(hf_token) == 0) {
  cat("HF_TOKEN is not currently set.\n")
  cat("Please set your HuggingFace token first, then rebuild the backend library.\n\n")
  
  # Ask user if they want to set it interactively
  if (interactive()) {
    token <- readline("Enter your HF token (or press Enter to skip): ")
    if (nchar(token) > 0) {
      Sys.setenv(HF_TOKEN = token)
      cat("HF_TOKEN set for this R session.\n")
      cat("Note: You'll need to rebuild the backend library for the changes to take effect.\n")
    }
  }
} else {
  cat("HF_TOKEN is set.\n")
  cat("Token starts with:", substr(hf_token, 1, 10), "...\n")
}
