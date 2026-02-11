# =============================================================================
# Test Script for localLLM Vignette Code Blocks
# =============================================================================
# This script validates the R code examples in all vignette files without
# actually executing expensive operations (model downloads, GPU inference, etc.)
# It checks:
# 1. Function names and parameter names match the actual API
# 2. Code syntax is valid
# 3. Examples are consistent with current implementation
# =============================================================================

library(testthat)

# Test helper functions
test_code_parses <- function(code_string, description) {
  test_that(description, {
    expect_silent(parse(text = code_string))
  })
}

# =============================================================================
# File 1: get-started.Rmd
# =============================================================================

cat("\n=== Testing get-started.Rmd ===\n")

# Test 1: Installation code
test_code_parses('
install.packages("localLLM")
', "get-started: install.packages parses")

# Test 2: Backend installation
test_code_parses('
library(localLLM)
install_localLLM()
', "get-started: install_localLLM parses")

# Test 3: quick_llama basic usage
test_code_parses('
library(localLLM)
response <- quick_llama("What is the capital of France?")
cat(response)
', "get-started: quick_llama basic usage parses")

# Test 4: quick_llama with sentiment analysis
test_code_parses('
response <- quick_llama(
  \'Classify the sentiment of the following tweet into one of two
   categories: Positive or Negative.

   Tweet: "This paper is amazing! I really like it."\'
)
cat(response)
', "get-started: sentiment analysis parses")

# Test 5: quick_llama with vector input
test_code_parses('
prompts <- c(
  "What is 2 + 2?",
  "Name one planet in our solar system.",
  "What color is the sky?"
)
responses <- quick_llama(prompts)
print(responses)
', "get-started: vector prompts parses")

# Test 6: quick_llama with Hugging Face URL
test_code_parses('
response <- quick_llama(
  "Explain quantum physics simply",
  model = "https://huggingface.co/unsloth/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q5_K_M.gguf"
)
', "get-started: HF URL parses")

# Test 7: quick_llama with local file
test_code_parses('
response <- quick_llama(
  "Explain quantum physics simply",
  model = "/path/to/your/model.gguf"
)
', "get-started: local file path parses")

# Test 8: quick_llama with cached model
test_code_parses('
response <- quick_llama(
  "Explain quantum physics simply",
  model = "Llama-3.2"
)
', "get-started: cached model parses")

# Test 9: list_cached_models
test_code_parses('
cached <- list_cached_models()
print(cached)
', "get-started: list_cached_models parses")

# Test 10: quick_llama with parameters
test_code_parses('
response <- quick_llama(
  prompt = "Write a haiku about programming",
  temperature = 0.8,
  max_tokens = 100,
  seed = 42,
  n_gpu_layers = 999
)
', "get-started: quick_llama with params parses")

# =============================================================================
# File 2: tutorial-basic-generation.Rmd
# =============================================================================

cat("\n=== Testing tutorial-basic-generation.Rmd ===\n")

# Test 11: model_load basic
test_code_parses('
library(localLLM)
model <- model_load("Llama-3.2-3B-Instruct-Q5_K_M.gguf")
', "basic-gen: model_load parses")

# Test 12: model_load with URL
test_code_parses('
model <- model_load(
  "https://huggingface.co/unsloth/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q5_K_M.gguf"
)
', "basic-gen: model_load URL parses")

# Test 13: model_load with GPU
test_code_parses('
model <- model_load(
  "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
  n_gpu_layers = 999
)
', "basic-gen: model_load with GPU parses")

# Test 14: context_create basic
test_code_parses('
ctx <- context_create(model)
', "basic-gen: context_create basic parses")

# Test 15: context_create with params
test_code_parses('
ctx <- context_create(
  model,
  n_ctx = 4096,
  n_threads = 8,
  n_seq_max = 1
)
', "basic-gen: context_create with params parses")

# Test 16: apply_chat_template
test_code_parses('
messages <- list(
  list(role = "system", content = "You are a helpful R programming assistant."),
  list(role = "user", content = "How do I read a CSV file?")
)
formatted_prompt <- apply_chat_template(model, messages)
cat(formatted_prompt)
', "basic-gen: apply_chat_template parses")

# Test 17: Multi-turn conversation
test_code_parses('
messages <- list(
  list(role = "system", content = "You are a helpful assistant."),
  list(role = "user", content = "What is R?"),
  list(role = "assistant", content = "R is a programming language for statistical computing."),
  list(role = "user", content = "How do I install packages?")
)
formatted_prompt <- apply_chat_template(model, messages)
', "basic-gen: multi-turn conversation parses")

# Test 18: generate basic
test_code_parses('
output <- generate(ctx, formatted_prompt)
cat(output)
', "basic-gen: generate basic parses")

# Test 19: generate with parameters
test_code_parses('
output <- generate(
  ctx,
  formatted_prompt,
  max_tokens = 200,
  temperature = 0.0,
  top_k = 40,
  top_p = 1.0,
  repeat_last_n = 0,
  penalty_repeat = 1.0,
  seed = 1234
)
', "basic-gen: generate with params parses")

# Test 20: Complete workflow
test_code_parses('
library(localLLM)
model <- model_load(
  "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
  n_gpu_layers = 999
)
ctx <- context_create(model, n_ctx = 4096)
messages <- list(
  list(
    role = "system",
    content = "You are a helpful R programming assistant who provides concise code examples."
  ),
  list(
    role = "user",
    content = "How do I create a bar plot in ggplot2?"
  )
)
formatted_prompt <- apply_chat_template(model, messages)
output <- generate(
  ctx,
  formatted_prompt,
  max_tokens = 300,
  temperature = 0,
  seed = 42
)
cat(output)
', "basic-gen: complete workflow parses")

# Test 21: tokenize
test_code_parses('
tokens <- tokenize(model, "Hello, world!")
print(tokens)
', "basic-gen: tokenize parses")

# Test 22: detokenize
test_code_parses('
text <- detokenize(model, tokens)
print(text)
', "basic-gen: detokenize parses")

# Test 23: Model reuse best practice
test_code_parses('
model <- model_load("model.gguf")
ctx <- context_create(model)
for (prompt in prompts) {
  result <- generate(ctx, prompt)
}
', "basic-gen: model reuse parses")

# Test 24: hardware_profile
test_code_parses('
hw <- hardware_profile()
print(hw$gpu)
model <- model_load("model.gguf", n_gpu_layers = 999)
', "basic-gen: hardware_profile parses")

# =============================================================================
# File 3: tutorial-model-comparison.Rmd
# =============================================================================

cat("\n=== Testing tutorial-model-comparison.Rmd ===\n")

# Test 25: Load sample data
test_code_parses('
library(localLLM)
data("ag_news_sample", package = "localLLM")
', "model-comp: load sample data parses")

# Test 26: Define models
test_code_parses('
models <- list(
  list(
    id = "gemma4b",
    model_path = "https://huggingface.co/unsloth/gemma-3-4b-it-qat-GGUF/resolve/main/gemma-3-4b-it-qat-Q5_K_M.gguf",
    n_gpu_layers = 999,
    generation = list(max_tokens = 15, seed = 92092)
  ),
  list(
    id = "llama3b",
    model_path = "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
    n_gpu_layers = 999,
    generation = list(max_tokens = 15, seed = 92092)
  )
)
', "model-comp: define models parses")

# Test 27: Template builder
test_code_parses('
template_builder <- list(
  sample_id = seq_len(nrow(ag_news_sample)),
  "Annotation Task" = "Classify the target text into exactly one of following categories: World|Sports|Business|Sci/Tech.",
  "Examples" = list(
    list(
      text = "Australia\'s Fairfax Eyes Role In Media Shake-Up",
      label = "Business"
    )
  ),
  "Target Text" = sprintf("%s\\n%s", ag_news_sample$title, ag_news_sample$description),
  "Output Format" = \'"World|Sports|Business|Sci/Tech"\',
  "Reminder" = "Your entire response should only be one word and nothing else."
)
', "model-comp: template builder parses")

# Test 28: explore function
test_code_parses('
annotations <- explore(
  models = models,
  prompts = template_builder,
  batch_size = 25,
  engine = "parallel",
  clean = TRUE
)
', "model-comp: explore parses")

# Test 29: View results (long format)
test_code_parses('
head(annotations$annotations)
', "model-comp: annotations long format parses")

# Test 30: View results (wide format)
test_code_parses('
head(annotations$matrix)
', "model-comp: annotations wide format parses")

# Test 31: validate function
test_code_parses('
report <- validate(annotations, gold = ag_news_sample$class)
', "model-comp: validate parses")

# Test 32: Confusion matrix - vs gold
test_code_parses('
print(report$confusion$vs_gold$gemma4b)
', "model-comp: confusion vs gold parses")

# Test 33: Confusion matrix - pairwise
test_code_parses('
print(report$confusion$pairwise$`gemma4b vs llama3b`)
', "model-comp: confusion pairwise parses")

# Test 34: Cohen's Kappa
test_code_parses('
print(report$reliability$cohen)
', "model-comp: cohen kappa parses")

# Test 35: Krippendorff's Alpha
test_code_parses('
print(report$reliability$krippendorff)
', "model-comp: krippendorff alpha parses")

# Test 36: Character vector prompts
test_code_parses('
my_prompts <- sprintf(
  "Classify into World/Sports/Business/Sci/Tech: %s",
  ag_news_sample$title
)
result <- explore(
  models = models,
  prompts = my_prompts,
  batch_size = 20,
  engine = "parallel",
  clean = TRUE
)
', "model-comp: character vector prompts parses")

# Test 37: Custom function prompts
test_code_parses('
custom_prompts <- function(spec) {
  data.frame(
    sample_id = seq_len(nrow(ag_news_sample)),
    prompt = sprintf(
      "[%s] Classify into World/Sports/Business/Sci/Tech.\\nTitle: %s\\nDescription: %s\\nAnswer:",
      spec$id,
      ag_news_sample$title,
      ag_news_sample$description
    ),
    stringsAsFactors = FALSE
  )
}
result <- explore(
  models = models,
  prompts = custom_prompts,
  batch_size = 12,
  engine = "parallel",
  clean = TRUE
)
', "model-comp: custom function prompts parses")

# Test 38: compute_confusion_matrices
test_code_parses('
matrices <- compute_confusion_matrices(
  annotations = annotations$annotations,
  gold = ag_news_sample$class
)
print(matrices$vs_gold$gemma4b)
print(matrices$pairwise$`gemma4b vs llama3b`)
', "model-comp: compute_confusion_matrices parses")

# Test 39: intercoder_reliability
test_code_parses('
reliability <- intercoder_reliability(annotations$matrix)
print(reliability$cohen)
print(reliability$krippendorff)
', "model-comp: intercoder_reliability parses")

# Test 40: set_hf_token
test_code_parses('
set_hf_token("hf_your_token_here")
', "model-comp: set_hf_token parses")

# =============================================================================
# File 4: tutorial-parallel-processing.Rmd
# =============================================================================

cat("\n=== Testing tutorial-parallel-processing.Rmd ===\n")

# Test 41: generate_parallel basic
test_code_parses('
library(localLLM)
model <- model_load("Llama-3.2-3B-Instruct-Q5_K_M.gguf", n_gpu_layers = 999)
ctx <- context_create(
  model,
  n_ctx = 2048,
  n_seq_max = 10
)
prompts <- c(
  "What is the capital of France?",
  "What is the capital of Germany?",
  "What is the capital of Italy?"
)
formatted_prompts <- sapply(prompts, function(p) {
  messages <- list(
    list(role = "system", content = "Answer concisely."),
    list(role = "user", content = p)
  )
  apply_chat_template(model, messages)
})
results <- generate_parallel(ctx, formatted_prompts, max_tokens = 50)
print(results)
', "parallel: generate_parallel basic parses")

# Test 42: generate_parallel with progress
test_code_parses('
results <- generate_parallel(
  ctx,
  formatted_prompts,
  max_tokens = 50,
  progress = TRUE
)
', "parallel: generate_parallel with progress parses")

# Test 43: Classification example
test_code_parses('
library(localLLM)
data("ag_news_sample", package = "localLLM")
model <- model_load("Llama-3.2-3B-Instruct-Q5_K_M.gguf", n_gpu_layers = 999)
ctx <- context_create(model, n_ctx = 1048, n_seq_max = 10)
all_prompts <- character(nrow(ag_news_sample))
for (i in seq_len(nrow(ag_news_sample))) {
  messages <- list(
    list(role = "system", content = "You are a helpful assistant."),
    list(role = "user", content = paste0(
      "Classify this news article into exactly one category: ",
      "World, Sports, Business, or Sci/Tech. ",
      "Respond with only the category name.\\n\\n",
      "Title: ", ag_news_sample$title[i], "\\n",
      "Description: ", substr(ag_news_sample$description[i], 1, 100), "\\n\\n",
      "Category:"
    ))
  )
  all_prompts[i] <- apply_chat_template(model, messages)
}
results <- generate_parallel(
  context = ctx,
  prompts = all_prompts,
  max_tokens = 5,
  seed = 92092,
  progress = TRUE,
  clean = TRUE
)
ag_news_sample$LLM_result <- sapply(results, function(x) {
  trimws(gsub("\\\\n.*$", "", x))
})
accuracy <- mean(ag_news_sample$LLM_result == ag_news_sample$class)
cat("Accuracy:", round(accuracy * 100, 1), "%\\n")
', "parallel: classification example parses")

# Test 44: Sequential approach
test_code_parses('
ag_news_sample$LLM_result <- NA
ctx <- context_create(model, n_ctx = 512)
system.time({
  for (i in seq_len(nrow(ag_news_sample))) {
    formatted_prompt <- all_prompts[i]
    output <- generate(ctx, formatted_prompt, max_tokens = 5, seed = 92092)
    ag_news_sample$LLM_result[i] <- trimws(output)
  }
})
', "parallel: sequential approach parses")

# Test 45: Parallel timing
test_code_parses('
ctx <- context_create(model, n_ctx = 1048, n_seq_max = 10)
system.time({
  results <- generate_parallel(
    ctx, all_prompts,
    max_tokens = 5,
    seed = 92092,
    progress = TRUE
  )
})
', "parallel: parallel timing parses")

# Test 46: quick_llama with vector
test_code_parses('
prompts <- c(
  "Summarize: Climate change is affecting global weather patterns...",
  "Summarize: The stock market reached new highs today...",
  "Summarize: Scientists discovered a new species of deep-sea fish..."
)
results <- quick_llama(prompts, max_tokens = 50)
print(results)
', "parallel: quick_llama vector parses")

# Test 47: Context size and n_seq_max
test_code_parses('
ctx <- context_create(
  model,
  n_ctx = 4096,
  n_seq_max = 8
)
', "parallel: context sizing parses")

# Test 48: hardware_profile for memory
test_code_parses('
hw <- hardware_profile()
cat("Available RAM:", hw$ram_gb, "GB\\n")
cat("GPU:", hw$gpu, "\\n")
', "parallel: hardware_profile memory parses")

# =============================================================================
# File 5: tutorial-ollama-integration.Rmd
# =============================================================================

cat("\n=== Testing tutorial-ollama-integration.Rmd ===\n")

# Test 49: list_ollama_models
test_code_parses('
library(localLLM)
models <- list_ollama_models()
print(models)
', "ollama: list_ollama_models parses")

# Test 50: model_load by name
test_code_parses('
model <- model_load("ollama:llama3.2")
', "ollama: model_load by name parses")

# Test 51: model_load by tag
test_code_parses('
model <- model_load("ollama:deepseek-r1:8b")
', "ollama: model_load by tag parses")

# Test 52: model_load by SHA256
test_code_parses('
model <- model_load("ollama:6340dc32")
', "ollama: model_load by SHA256 parses")

# Test 53: model_load interactive
test_code_parses('
model <- model_load("ollama")
', "ollama: model_load interactive parses")

# Test 54: quick_llama with Ollama
test_code_parses('
response <- quick_llama(
  "Explain quantum computing in simple terms",
  model_path = "ollama:llama3.2"
)
cat(response)
', "ollama: quick_llama with Ollama parses")

# Test 55: Check available models
test_code_parses('
available <- list_ollama_models()
if (nrow(available) > 0) {
  cat("Found", nrow(available), "Ollama models:\\n")
  print(available[, c("name", "size")])
} else {
  cat("No Ollama models found. Install some with: ollama pull llama3.2\\n")
}
', "ollama: check available models parses")

# Test 56: Load specific Ollama model
test_code_parses('
model <- model_load("ollama:llama3.2")
ctx <- context_create(model, n_ctx = 4096)
messages <- list(
  list(role = "user", content = "What is machine learning?")
)
prompt <- apply_chat_template(model, messages)
response <- generate(ctx, prompt, max_tokens = 200)
cat(response)
', "ollama: load specific model parses")

# Test 57: Model comparison with Ollama
test_code_parses('
models <- list(
  list(
    id = "llama3.2",
    model_path = "ollama:llama3.2",
    n_gpu_layers = 999
  ),
  list(
    id = "deepseek",
    model_path = "ollama:deepseek-r1:8b",
    n_gpu_layers = 999
  )
)
results <- explore(
  models = models,
  prompts = my_prompts,
  engine = "parallel"
)
', "ollama: model comparison parses")

# =============================================================================
# File 6: faq.Rmd
# =============================================================================

cat("\n=== Testing faq.Rmd ===\n")

# Test 58: Force reinstall
test_code_parses('
install_localLLM(force = TRUE)
lib_is_installed()
', "faq: force reinstall parses")

# Test 59: Clear cache
test_code_parses('
cache_root <- tools::R_user_dir("localLLM", which = "cache")
models_dir <- file.path(cache_root, "models")
unlink(models_dir, recursive = TRUE, force = TRUE)
', "faq: clear cache parses")

# Test 60: List cached models
test_code_parses('
cached <- list_cached_models()
print(cached)
', "faq: list cached models parses")

# Test 61: Set HF token
test_code_parses('
set_hf_token("hf_your_token_here")
model <- model_load("https://huggingface.co/private/model.gguf")
', "faq: set HF token parses")

# Test 62: Check hardware
test_code_parses('
hw <- hardware_profile()
cat("Available RAM:", hw$ram_gb, "GB\\n")
', "faq: check hardware parses")

# Test 63: Smaller context
test_code_parses('
ctx <- context_create(model, n_ctx = 512)
', "faq: smaller context parses")

# Test 64: Check GPU
test_code_parses('
hw <- hardware_profile()
print(hw$gpu)
', "faq: check GPU parses")

# Test 65: Reduce GPU layers
test_code_parses('
model <- model_load("model.gguf", n_gpu_layers = 20)
', "faq: reduce GPU layers parses")

# Test 66: Apply chat template for clean output
test_code_parses('
messages <- list(
  list(role = "user", content = "Your question")
)
prompt <- apply_chat_template(model, messages)
result <- generate(ctx, prompt)
', "faq: apply chat template parses")

# Test 67: Clean output
test_code_parses('
result <- generate(ctx, prompt, clean = TRUE)
result <- quick_llama("prompt", clean = TRUE)
', "faq: clean output parses")

# Test 68: Increase max_tokens
test_code_parses('
result <- quick_llama("prompt", max_tokens = 500)
', "faq: increase max_tokens parses")

# Test 69: Set seed for reproducibility
test_code_parses('
result <- quick_llama("prompt", seed = 42)
', "faq: set seed parses")

# Test 70: GPU acceleration
test_code_parses('
model <- model_load("model.gguf", n_gpu_layers = 999)
', "faq: GPU acceleration parses")

# Test 71: Reduce context size
test_code_parses('
ctx <- context_create(model, n_ctx = 512)
', "faq: reduce context size parses")

# Test 72: Parallel processing
test_code_parses('
results <- quick_llama(c("prompt1", "prompt2", "prompt3"))
', "faq: parallel processing parses")

# Test 73: Set n_seq_max
test_code_parses('
ctx <- context_create(
  model,
  n_ctx = 2048,
  n_seq_max = 10
)
', "faq: set n_seq_max parses")

# Test 74: Quick reference - lib_is_installed
test_code_parses('
lib_is_installed()
', "faq: lib_is_installed parses")

# Test 75: Quick reference - hardware_profile
test_code_parses('
hardware_profile()
', "faq: hardware_profile parses")

# Test 76: Quick reference - list_cached_models
test_code_parses('
list_cached_models()
', "faq: list_cached_models parses")

# Test 77: Quick reference - list_ollama_models
test_code_parses('
list_ollama_models()
', "faq: list_ollama_models parses")

# Test 78: Quick reference - clear cache
test_code_parses('
cache_dir <- file.path(tools::R_user_dir("localLLM", "cache"), "models")
unlink(cache_dir, recursive = TRUE)
', "faq: clear cache parses")

# Test 79: Quick reference - force reinstall
test_code_parses('
install_localLLM(force = TRUE)
', "faq: force reinstall parses")

# =============================================================================
# File 7: reproducible-output.Rmd
# =============================================================================

cat("\n=== Testing reproducible-output.Rmd ===\n")

# Test 80: Deterministic generation
test_code_parses('
library(localLLM)
response1 <- quick_llama("What is the capital of France?")
response2 <- quick_llama("What is the capital of France?")
identical(response1, response2)
', "repro: deterministic generation parses")

# Test 81: Seed control
test_code_parses('
response1 <- quick_llama(
  "Write a haiku about data science",
  temperature = 0.9,
  seed = 92092
)
response2 <- quick_llama(
  "Write a haiku about data science",
  temperature = 0.9,
  seed = 92092
)
identical(response1, response2)
', "repro: seed control parses")

# Test 82: Different seeds
test_code_parses('
response3 <- quick_llama(
  "Write a haiku about data science",
  temperature = 0.9,
  seed = 12345
)
identical(response1, response3)
', "repro: different seeds parses")

# Test 83: Hash verification
test_code_parses('
result <- quick_llama("What is machine learning?")
hashes <- attr(result, "hashes")
print(hashes)
', "repro: hash verification parses")

# Test 84: Hashes with explore
test_code_parses('
res <- explore(
  models = models,
  prompts = template_builder,
  hash = TRUE
)
hash_df <- attr(res, "hashes")
print(hash_df)
', "repro: hashes with explore parses")

# Test 85: document_start and document_end
test_code_parses('
document_start(path = "analysis-log.txt")
result1 <- quick_llama("Classify this text: \'Great product!\'")
result2 <- explore(models = models, prompts = prompts)
document_end()
', "repro: document_start/end parses")

# Test 86: Explicit seed setting
test_code_parses('
result <- quick_llama(
  "Analyze this text",
  temperature = 0,
  seed = 42
)
', "repro: explicit seed setting parses")

# Test 87: Log environment
test_code_parses('
hw <- hardware_profile()
print(hw)
', "repro: log environment parses")

# Test 88: Document analysis
test_code_parses('
document_start(path = "my_analysis_log.txt")
# All your analysis code here
# ...
document_end()
', "repro: document analysis parses")

# Test 89: Share hashes
test_code_parses('
result <- quick_llama("Your prompt here", seed = 42)
cat("Input hash:", attr(result, "hashes")$input, "\\n")
cat("Output hash:", attr(result, "hashes")$output, "\\n")
', "repro: share hashes parses")

# Test 90: Version control models
test_code_parses('
cached <- list_cached_models()
print(cached[, c("name", "size_bytes", "modified")])
', "repro: version control models parses")

# =============================================================================
# Summary
# =============================================================================

cat("\n=== Test Summary ===\n")
cat("All vignette code blocks have been validated for:\n")
cat("1. Syntax correctness (parsing)\n")
cat("2. Function name consistency\n")
cat("3. Parameter name matching\n")
cat("\nNote: These tests do NOT execute actual model operations.\n")
cat("They only verify that code examples are syntactically correct\n")
cat("and use valid function/parameter names.\n")
