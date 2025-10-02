# localLLM

[![R-CMD-check](https://github.com/EddieYang211/localLLM/workflows/R-CMD-check/badge.svg)](https://github.com/EddieYang211/localLLM/actions)
[![codecov](https://codecov.io/gh/EddieYang211/localLLM/branch/master/graph/badge.svg)](https://codecov.io/gh/EddieYang211/localLLM)
[![CRAN status](https://www.r-pkg.org/badges/version/localLLM)](https://CRAN.R-project.org/package/localLLM)

## Tutorial

### Brief Introduction

The `localLLM` package provides a powerful and easy-to-use interface to run high-performance large language models (LLMs) directly in R. Backed by a complete `llama.cpp` integration, it allows you to generate text, analyze data, and build LLM-powered applications without relying on external APIs. Everything runs locally on your own machine, ensuring privacy and control.

This tutorial will guide you from installation to advanced customization, showing you how to unlock the full potential of local LLMs in your R workflow.

---

### Installation

Getting started requires two simple steps: installing the R package from CRAN and then downloading the backend C++ library that handles the heavy computations.

```r
# 1. Install the R package from CRAN
install.packages("localLLM")

# 2. Load the package and install the backend library
library(localLLM)
install_localLLM()
```

That's it! The `install_localLLM()` function automatically detects your operating system (Windows, macOS, Linux) and processor architecture to download the appropriate pre-compiled library.

---

### About GGUF Models

The `localLLM` backend is powered by `llama.cpp` (commit `b5421`), which only supports models
stored in the GGUF format. In practice this means every model you load through
`model_load()` or `quick_llama()` must be a `.gguf` file.

GGUF (GGML Unified Format) is a compact binary container designed for local
inference. It packages model weights together with tokenizer metadata and other
runtime information, enabling fast loading on CPUs or GPUs without additional
conversion steps.

**Finding GGUF models on Hugging Face**

1. Open [huggingface.co](https://huggingface.co).
2. In the search bar type `gguf` and press Enter.
3. Click **“See all model results for "gguf"”** to view the full catalogue. As
   of 2025-09-25 there are 127,756 GGUF models available.
4. To narrow down to specific families—such as Gemma or Llama—include the model
   name together with `gguf` in the search query (e.g. `gemma gguf`).

For a quick start, `quick_llama()` defaults to
`Llama-3.2-3B-Instruct-Q5_K_M.gguf`, an instruction-tuned Llama 3.2 model that downloads
automatically on first use. You can swap in any other GGUF model by passing a
different URL or local path; refer to the function reference for the `model`
argument to see all available options.

---

### Quick Start

You can start generating text with a single function call.

```r
# Load the package
library(localLLM)

# Ask a question and get a response
response <- quick_llama("What is machine learning in one sentence?")
cat(response)
```

The `quick_llama()` function is a high-level wrapper designed for convenience. It uses sensible defaults for all parameters, including automatically downloading and caching `Llama-3.2-3B-Instruct-Q5_K_M.gguf` on its first run. You can easily customize the generation by passing arguments directly. For example, you can change the `temperature` for more creative responses or increase `max_tokens` for longer answers.

Importantly, `quick_llama()` is a smart function. It automatically detects the format of your input.
*   If you provide a **single character string**, it performs a single generation.
*   If you provide a **vector of character strings**, it automatically switches to a highly efficient parallel generation mode, processing all of them at once.

This makes it incredibly versatile for both interactive use and batch processing.

---

### Advanced Usage: Direct Control with Lower-Level Functions

For maximum control and efficiency, especially in complex applications, you can bypass the `quick_llama` wrapper and use the core lower-level functions directly. This approach avoids reloading the model for each task and gives you fine-grained control over the generation process.

The core workflow is:
1.  **`model_load()`**: Load the model into memory once.
2.  **`context_create()`**: Create a reusable context for inference.
3.  **`apply_chat_template()`**: Format your prompts correctly for the model.
4.  **`generate()`** or **`generate_parallel()`**: Use the context to generate text.

#### Single Prompt Generation with Chat Templates

Modern instruction-tuned models are trained to respond to specific formats that include roles (like "system" and "user") and special control tokens. Simply sending a raw string is often not enough. The `apply_chat_template()` function is essential for formatting your prompts correctly.

```r
# 1. Load the model once (e.g., enabling GPU acceleration)
# Using a large number for n_gpu_layers offloads as many layers as possible.
model <- model_load(
  model = "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
  n_gpu_layers = 999
)

# 2. Create a reusable context with a specific size
ctx <- context_create(model, n_ctx = 4096)

# 3. Define the conversation using a list of messages
# This is where you set the system prompt (the model's instructions) and the user prompt (your query).
messages <- list(
  list(role = "system", content = "You are a helpful R programming assistant who provides concise code examples."),
  list(role = "user", content = "How do I create a bar plot in ggplot2?")
)

# 4. Apply the model's built-in chat template
# This converts the list of messages into a single, correctly formatted string that the model understands.
formatted_prompt <- apply_chat_template(model, messages)

# 5. Tokenize, generate, and detokenize to get the final text response
tokens <- tokenize(model, formatted_prompt)
output_tokens <- generate(ctx, tokens, max_tokens = 200, temperature = 0.3)
output_tokens
```

#### Parallel (Batch) Generation with Chat Templates

For the highest throughput, you can format multiple conversations and process them in a single batch with `generate_parallel()`. This is the most performant method for large-scale tasks.

```r
# Assumes 'model' and 'ctx' are already loaded from the previous step

# Define system and user prompts
system_prompt <- "You are a helpful assistant."
user_prompts <- c(
  "Explain machine learning in one sentence.",
  "What is deep learning?",
  "Summarize the concept of AI ethics."
)

# Use sapply() to apply the chat template to each user prompt
formatted_prompts <- sapply(user_prompts, function(user_content) {
  messages <- list(
    list(role = "system", content = system_prompt),
    list(role = "user", content = user_content)
  )
  apply_chat_template(model, messages)
})

# Process all formatted prompts in a single, highly optimized parallel call
results_parallel <- generate_parallel(ctx, formatted_prompts, max_tokens = 100)
results_parallel
```

---

### Running Example

In academic research, text classification is a highly demanded task—for example, classifying news articles by topic. To help users better understand how to leverage this package, we provide an example of performing text classification using open-source large language models. Specifically, we use a sample dataset containing 100 news headlines and their corresponding paragraphs, and demonstrate how to perform classification with three approaches: quick_llama, single-call functions, and parallel sequence functions.
```r
library(localLLM)

news_prompt <- paste(
  "Classify this news article into exactly one category: World, Sports, Business, or Sci/Tech. Respond with only the category name.",
  "",
  "Title: UPDATE: Australia's Fairfax Eyes Role In Media Shake-Up",
  "Description: SYDNEY (Dow Jones)--As investors speculate about the future landscape of the Australian media industry, newspaper publisher John Fairfax Holdings Ltd.",
  "",
  "Category:",
  sep = "\n"
)

result <- quick_llama(news_prompt)
result
```

#### For Loop for Running Example

To process the entire dataframe, a `for` loop is a straightforward approach. This method processes each row sequentially.

```r
library(dplyr)
library(localLLM)

# Load bundled sample dataset
data("ag_news_sample", package = "localLLM")

data_sample <- ag_news_sample %>%
  mutate(LLM_result = NA_character_)

# 1. Load the model once
model <- model_load(
  model = "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
  n_gpu_layers = 99,
  verbosity = 1
)

# 2. Create a reusable context
ctx <- context_create(model, n_ctx = 512, verbosity = 1)

# Process each observation
for (i in seq_len(nrow(data_sample))) {
  cat("Processing", i, "of", nrow(data_sample), "\n")
  
  tryCatch({
    # 3. Define the conversation
    messages <- list(
      list(role = "system", content = "You are a helpful assistant."),
      list(role = "user", content = paste0(
        "Classify this news article into exactly one category: World, Sports, Business, or Sci/Tech. Respond with only the category name.\n\n",
        "Title: ", data_sample$title[i], "\n",
        "Description: ", substr(data_sample$description[i], 1, 100), "\n\n",
        "Category:"
      ))
    )
    
    # 4. Apply chat template
    formatted_prompt <- apply_chat_template(model, messages)
    
    # 5. Tokenize and generate
    tokens <- tokenize(model, formatted_prompt)
    output_tokens <- generate(
      ctx, tokens,
      max_tokens = 5L,
      top_k = 20L,
      top_p = 0.95,
      temperature = 0.7,
      repeat_last_n = 32L,
      penalty_repeat = 1.05,
      seed = 1234L,
      clean = TRUE
    )
    
    # Store the result (output_tokens is already text)
    data_sample$LLM_result[i] <- trimws(gsub("\\n.*$", "", output_tokens))
    
  }, error = function(e) {
    cat("Error on item", i, ":", e$message, "\n")
    data_sample$LLM_result[i] <- "ERROR"
  })
}

# Compare with true labels
data_sample <- data_sample %>%
  mutate(correct = ifelse(LLM_result == class, TRUE, FALSE))

# Calculate accuracy
accuracy <- mean(data_sample$correct, na.rm = TRUE)
accuracy

write.csv(data_sample, "classification_results.csv", row.names = FALSE)
cat("Results saved to classification_results.csv\n")
```

#### Parallel Processing Example

In addition to looping through each row with the single-sequence generator, you can process the same dataset with the parallel generator; in our benchmarking on this sample, the batched run finishes in roughly 65% of the for-loop execution time.

```r
# 2. Create a reusable context
ctx <- context_create(model, n_ctx = 1048, n_seq_max = 10, verbosity = 1)

# 3. Prepare all prompts at once
all_prompts <- character(nrow(data_sample))
prompt_tokens <- vector("list", nrow(data_sample))  # optional: inspect tokenized prompts

for (i in seq_len(nrow(data_sample))) {
  messages <- list(
    list(role = "system", content = "You are a helpful assistant."),
    list(role = "user", content = paste0(
      "Classify this news article into exactly one category: World, Sports, Business, or Sci/Tech. Respond with only the category name.\n\n",
      "Title: ", data_sample$title[i], "\n",
      "Description: ", substr(data_sample$description[i], 1, 100), "\n\n",
      "Category:"
    ))
  )
  formatted_prompt <- apply_chat_template(model, messages)
  all_prompts[i] <- formatted_prompt
  prompt_tokens[[i]] <- tokenize(model, formatted_prompt)
}

# Record start time for parallel processing
parallel_start_time <- Sys.time()
cat("Parallel processing started at:", format(parallel_start_time, "%Y-%m-%d %H:%M:%S"), "\n")

# Process samples in parallel
tryCatch({
  results <- generate_parallel(
    context = ctx,
    prompts = all_prompts,
    max_tokens = 5L,
    top_k = 20L,
    top_p = 0.95,
    temperature = 0.7,
    repeat_last_n = 32L,
    penalty_repeat = 1.05,
    seed = 1234L,
    progress = TRUE,
    clean = TRUE
  )

  parallel_end_time <- Sys.time()
  cat("Parallel processing completed at:", format(parallel_end_time, "%Y-%m-%d %H:%M:%S"), "\n")

  parallel_duration <- parallel_end_time - parallel_start_time
  cat("Parallel processing duration:", round(as.numeric(parallel_duration, units = "secs"), 2), "seconds\n")

  data_sample$LLM_result <- sapply(results, function(x) trimws(gsub("\\n.*$", "", x)))
  cat("Parallel processing completed successfully!\n")

}, error = function(e) {
  cat("Error during parallel processing:", e$message, "\n")
  data_sample$LLM_result <- rep("ERROR", nrow(data_sample))
})

# Display final dataset
print(data_sample)

# Compare with true labels
data_sample <- data_sample %>%
  mutate(correct = ifelse(LLM_result == class, TRUE, FALSE))

# Calculate accuracy
accuracy <- mean(data_sample$correct, na.rm = TRUE)
cat("Classification accuracy:", accuracy, "\n")

write.csv(data_sample, "classification_results_parallel.csv", row.names = FALSE)
cat("Results saved to classification_results_parallel.csv\n")
```

---


### Customization

All generation functions (`quick_llama`, `generate`, `generate_parallel`) accept a wide range of parameters to control model behavior, performance, and output. The examples below reference `quick_llama()`.

#### Temperature / Determinism

These parameters control the creativity and randomness of the output.

-   **`temperature`**: A value from 0.0 to >1.0. Lower values (e.g., `0.2`) make the output more deterministic and focused, which is good for factual or classification tasks. Higher values (e.g., `0.9`) encourage more creative and diverse responses.
-   **`top_k`**: An integer (e.g., `40`). The model considers only the top `k` most likely tokens at each step.
-   **`top_p`**: A numeric value (e.g., `0.9`). The model selects from the smallest set of tokens whose cumulative probability exceeds `p`.
-   **`min_p`**: A numeric value (e.g., `0.05`). Sets a minimum probability threshold for token selection.

```r
# A factual, deterministic response
factual <- quick_llama("What is the capital of France?", temperature = 0.1, top_k = 1)

# A more creative response
creative <- quick_llama("Write a short story about a robot who discovers music.", temperature = 0.8)
```

#### Model Download

You can point the package at any GGUF model by URL, local path, or cached
filename.

```r
# Download a different model from Hugging Face (cached automatically)
response <- quick_llama(
  "Explain quantum physics in simple terms",
  model = "Llama-3.2-3B-Instruct-Q5_K_M.gguf"
)

# Load a local model file you have already downloaded
response <- quick_llama("Explain quantum physics in simple terms", model = "/path/to/your/local_model.gguf")

# Reuse a cached model by name fragment (auto-detected from cache)
response <- quick_llama("Explain quantum physics in simple terms", model = "Llama-3.2")
```

If you provide a name fragment instead of a full path/URL, the loader searches
the cache first. A single match loads immediately; multiple matches are printed
so you can choose interactively.

```r
# List cached models
cached <- list_cached_models()

# Remove cached models if needed
if (nrow(cached) > 0) {
  files_to_remove <- cached$path
  unlink(files_to_remove, force = TRUE)
  message("Removed ", length(files_to_remove), " cached models.")
} else {
  message("No cached models found.")
}
```

**Troubleshooting: Download Lock Issues**

If you encounter an error message like "Another download in progress" or "Download timeout: another process seems to be stuck", it means a previous download was interrupted and left a lock file. To resolve this, clear the cache directory manually:

```r
# macOS default path
unlink("~/Library/Caches/org.R-project.R/R/localLLM/models", recursive = TRUE, force = TRUE)

# Linux default path
unlink("~/.cache/R/localLLM/models", recursive = TRUE, force = TRUE)

# Windows default path
unlink(file.path(Sys.getenv("LOCALAPPDATA"), "R", "cache", "R", "localLLM", "models"), recursive = TRUE, force = TRUE)
```

This will remove all cached models and lock files, allowing fresh downloads.

#### Private Hugging Face Models

Some Hugging Face repositories (for example, Google-released or enterprise models) require an access token. Set the token once per session using `set_hf_token()` before calling `quick_llama()`, `model_load()`, or `download_model()`. The helper wires the token into the backend without printing it to the console.

```r
# Store the token for this session
set_hf_token('hf_your_token_here')

# Optionally persist it to ~/.Renviron (use with care)
# set_hf_token('hf_your_token_here', persist = TRUE)

# Now you can load gated models by URL
model <- model_load('hf://google/gated-model/model.gguf')
```

You can also set `HF_TOKEN` manually via `Sys.setenv()` if you prefer to manage environment variables yourself.

**Where to find your Hugging Face access token**
1. Visit https://huggingface.co/settings/tokens while logged in.
2. Click *Create new token*, give it a descriptive name, and assign at least *read* scope.
3. Copy the token (starts with `hf_`) and pass it to `set_hf_token()` as shown above.

#### Max Tokens

The `max_tokens` parameter controls the maximum length of the generated response.

```r
# Generate a short response (approx. 50 tokens)
short <- quick_llama("Summarize the plot of 'Hamlet'", max_tokens = 50)

# Generate a longer, more detailed response
long <- quick_llama("Summarize the plot of 'Hamlet'", max_tokens = 300)
```

#### Context Window (`n_ctx`)

The context window (`n_ctx`) defines how much text (input prompt + generated response) the model can "remember" at once, measured in tokens. A larger context window is necessary for longer conversations or documents but consumes more memory.

```r
# Set a context window of 4096 tokens for longer interactions
response <- quick_llama("Let's have a long conversation about AI.", n_ctx = 4096)
```

#### GPU Acceleration

If you have a compatible GPU (NVIDIA or Apple Metal), you can offload model layers to it for a significant speed increase (5-10x or more).

-   `n_gpu_layers = 0`: Use CPU only (the default).
-   `n_gpu_layers > 0`: Offloads a specific number of layers to the GPU. To offload all possible layers, set this to a very high number (e.g., `999`).

```r
# Offload as many layers as possible to the GPU for the fastest generation
quick_llama("Tell me a joke", n_gpu_layers = 999)
```

#### All Other Parameters

The `quick_llama()` function provides full control over the `llama.cpp` backend. Some other useful parameters include:

-   **`system_prompt` (character)**: Sets the initial instruction for the model to define its role or persona (e.g., `"You are a helpful R programming assistant."`).
-   **`n_threads` (integer)**: The number of CPU threads to use for processing. Defaults to auto-detection for optimal performance.
-   **`penalty_repeat` (numeric)**: A penalty applied to repeated tokens to discourage the model from getting stuck in loops. A common value is `1.1`.
-   **`seed` (integer)**: A random seed for sampling. Setting a seed (e.g., `seed = 1234`) ensures you get the exact same output for the same prompt every time, making your results reproducible.
-   **`verbosity` (integer)**: Controls the amount of backend logging information printed to the console (3=max, 0=errors only).

```r
# An example combining multiple custom settings for a reproducible poem
response <- quick_llama(
  prompt = "Write a short poem about data science",
  system_prompt = "You are a world-class poet.",
  temperature = 0.8,
  max_tokens = 150,
  n_gpu_layers = 999,
  seed = 42
)
cat(response)
```

For a complete list of all available parameters and their descriptions, run `?quick_llama` in your R console.
