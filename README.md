# localLLM

[![R-CMD-check](https://github.com/EddieYang211/localLLM/workflows/R-CMD-check/badge.svg)](https://github.com/EddieYang211/localLLM/actions)
[![CRAN status](https://www.r-pkg.org/badges/version/localLLM)](https://cran.r-project.org/package=localLLM)

**localLLM** provides an easy-to-use interface to run large language models (LLMs) directly in R. It uses the performant `llama.cpp` library as the backend and allows you to generate text and analyze data with LLM. Everything runs locally on your own machine, completely free. Furthermore, it ensures reproducibility by default, making it a reliable tool for scientific research.

---

### Installation

Getting started requires two simple steps: installing the R package from CRAN and then downloading the backend C++ library that handles the heavy computations. The `install_localLLM()` function automatically detects your operating system (Windows, macOS, Linux) and processor architecture to download the appropriate pre-compiled library.

```r
# 1. Install the R package from CRAN
install.packages("localLLM")

# 2. Load the package and install the backend library
library(localLLM)
install_localLLM()
```
---

### Quick Start

You can start running an LLM using quick_llama().

```r
library(localLLM)

# Ask a question and get a response
response <- quick_llama('Classify the sentiment of the following tweet into one of two 
  categories: Positive or Negative.\n\nTweet: "This paper is amazing! I really like it."')

cat(response) # Output: The sentiment of this tweet is Positive.
```

`quick_llama()` is a high-level wrapper designed for convenience. It automatically downloads and caches the default LLM `Llama-3.2-3B-Instruct-Q5_K_M.gguf` on its first run. You can easily customize the generation by passing arguments directly. For example, you can change the `temperature` for more creative responses or increase `max_tokens` for longer answers.

`quick_llama()` can process different types of input:
*   If you provide a **single character string**, it performs a single generation.
*   If you provide a **vector of character strings**, it automatically switches to parallel generation mode, processing all of them at once.

---

### Reproducibility

You can check the reproducibility of the result by running the same query multiple times. By default , all generation functions in **localLLM** (`quick_llama()`, `generate()`, and `generate_parallel()`) use deterministic greedy decoding with temperature = 0. Even when temperature > 0, results are reproducibile.

```r
response1 <- quick_llama('Classify the sentiment of the following tweet into one of two 
  categories: Positive or Negative.\n\nTweet: "This paper is amazing! I really like it."', 
  temperature=0.9, seed=92092)

response2 <- quick_llama('Classify the sentiment of the following tweet into one of two 
  categories: Positive or Negative.\n\nTweet: "This paper is amazing! I really like it."', 
  temperature=0.9, seed=92092)

print(response1==response2)
```

---

### About GGUF Models

The `localLLM` backend is powered by `llama.cpp` (commit `b5421`), which only supports models stored in the GGUF format. In practice this means every model you load through
`model_load()` or `quick_llama()` must be a `.gguf` file.

**Finding GGUF models on Hugging Face**

1. Open [huggingface.co](https://huggingface.co).
2. In the search bar type `gguf` and press Enter.
3. Click **“See all model results for "gguf"”** to view the full catalogue. As nof 2025-10-02 there are 128,493 GGUF models available.
4. To narrow down to specific families - such as Gemma or Llama - include the model name together with `gguf` in the search query (e.g. `gemma gguf`).

`quick_llama()` defaults to `Llama-3.2-3B-Instruct-Q5_K_M.gguf`, a GGUF version of the Llama-3.2-3B model. You can swap in any other GGUF model by passing adifferent URL or local path; for example, to download and local another model from Hugging Face, simply locate the model url and do:

```r
model_load(
  model_path="https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf")
```

---

### Direct Control with Lower-Level Functions

For more control, you can bypass the `quick_llama` wrapper and use the core lower-level functions directly.

The core workflow is:
1.  **`model_load()`**: Load the model into memory once.
2.  **`context_create()`**: Create a reusable context for inference.
3.  **`apply_chat_template()`**: Format your prompts correctly for the model.
4.  **`generate()`** or **`generate_parallel()`**: Use the context to generate text.

#### Single Prompt Generation with Chat Templates

LLMs are trained to respond to specific formats that include roles (like "system" and "user") and special control tokens. Simply sending a raw string is often not enough. The `apply_chat_template()` function is essential for formatting your prompts correctly.

```r
# 1. Load the model once
# Using a large number for n_gpu_layers offloads as many layers as possible 
# to GPU for faster computing.
model <- model_load(
  model = "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
  n_gpu_layers = 999
)

# 2. Create a reusable context with a specific size
ctx <- context_create(model, n_ctx = 4096)

# 3. Define the conversation using a list of messages
# This is where you set the system prompt and the user prompt (your query).
messages <- list(
  list(role = "system", content = "You are a helpful R programming assistant who provides concise code examples."),
  list(role = "user", content = "How do I create a bar plot in ggplot2?")
)

# 4. Apply the model's built-in chat template
# This converts the list of messages into a single, 
# correctly formatted string that the model understands.
formatted_prompt <- apply_chat_template(model, messages)

# 5. Generate response directly from the formatted prompt
output <- generate(ctx, formatted_prompt, max_tokens = 200)
cat(output)
```

#### Parallel (Batch) Generation

If you want to process multiple prompts at the same time or for large-scale tasks, you can use the `generate_parallel()` function.

```r
# Assumes 'model' and 'ctx' are already loaded from the previous step

# Define system and user prompts
system_prompt <- "You are a helpful assistant."

prompt_prefix <- "Classify the sentiment of the following tweet into one of two categories: 
  Positive or Negative.\n\nTweet: "

user_prompts <- c(
  paste0(prompt_prefix, '"This paper is amazing! I really like it."'),
  paste0(prompt_prefix, '"This paper is terrible! I hate it."'),
  paste0(prompt_prefix, '"This paper is pretty good. I like it."')
)

# Use sapply() to apply the chat template to each user prompt
formatted_prompts <- sapply(user_prompts, function(user_content) {
  messages <- list(
    list(role = "system", content = system_prompt),
    list(role = "user", content = user_content)
  )
  apply_chat_template(model, messages)
})

# Process all formatted prompts in a single, parallel call
results_parallel <- generate_parallel(ctx, formatted_prompts, max_tokens = 32)
cat(results_parallel)
```

---

### Running Example: Text Classification

Researchers often wish to use LLM for data classification/annotation - for example, classifying news articles by topic and tweets by sentiment. Here we provide an example of how users can use **localLLM** to perform text classification using open-source LLMs. Specifically, we use a sample dataset containing 100 news headlines and their corresponding descriptions, and demonstrate how to perform classification with two approaches: `generate()`, and `generate_parallel()`.

#### For Loop using `generate()`

To process the entire dataframe, a `for` loop is a straightforward approach. This method processes each row sequentially.

```r
library(localLLM)

# Load sample dataset
data("ag_news_sample", package = "localLLM")

ag_news_sample$LLM_result <- NA

# 1. Load the model once
model <- model_load(
  model = "Llama-3.2-3B-Instruct-Q5_K_M.gguf",
  n_gpu_layers = 99
)

# 2. Create a reusable context
ctx <- context_create(model, n_ctx = 512)

# Process each observation
for (i in 1:nrow(ag_news_sample)) {
  cat("Processing", i, "of", nrow(ag_news_sample), "\n")
  
  # 3. Define the prompt
  messages <- list(
    list(role = "system", content = "You are a helpful assistant."),
    list(role = "user", content = paste0(
      "Classify this news article into exactly one category: World, Sports, Business, 
      or Sci/Tech. Respond with only the category name.\n\n",
      "Title: ", ag_news_sample$title[i], "\n",
      "Description: ", substr(ag_news_sample$description[i], 1, 100), "\n\n",
      "Category:"
    ))
  )
    
  # 4. Apply chat template
  formatted_prompt <- apply_chat_template(model, messages)
    
  # 5. Generate response
  output_tokens <- generate(
    ctx, formatted_prompt,
    max_tokens = 5,
    seed = 92092,
    clean = TRUE # strip common chat-template control tokens from the generated text
  )
    
  # Store the result
  ag_news_sample$LLM_result[i] <- trimws(sub("\\.$", "", gsub("[\n<].*$", "", output_tokens)))

}

# Compare with true labels and calculate accuracy
accuracy <- mean(ag_news_sample$LLM_result==ag_news_sample$class)
print(accuracy)
```

#### Parallel Processing with `generate_parallel()`

In addition to looping through each row with the single-sequence generator, you can process the same dataset with the parallel generator; in our benchmarking on this sample, the batched run finishes in roughly 65% of the for-loop execution time.

```r
# Create a reusable context
ctx <- context_create(model, n_ctx = 1048, n_seq_max = 10)

# Prepare all prompts at once
all_prompts <- character(nrow(ag_news_sample))
prompt_tokens <- vector("list", nrow(ag_news_sample))  # optional: inspect tokenized prompts

for (i in 1:nrow(ag_news_sample)) {
  messages <- list(
    list(role = "system", content = "You are a helpful assistant."),
    list(role = "user", content = paste0(
      "Classify this news article into exactly one category: World, Sports, Business, 
      or Sci/Tech. Respond with only the category name.\n\n",
      "Title: ", ag_news_sample$title[i], "\n",
      "Description: ", substr(ag_news_sample$description[i], 1, 100), "\n\n",
      "Category:"
    ))
  )
  formatted_prompt <- apply_chat_template(model, messages)
  all_prompts[i] <- formatted_prompt
  prompt_tokens[[i]] <- tokenize(model, formatted_prompt)
}

# Process samples in parallel
results <- generate_parallel(
  context = ctx,
  prompts = all_prompts,
  max_tokens = 5,
  seed = 92092,
  progress = TRUE,
  clean = TRUE
)

ag_news_sample$LLM_result <- sapply(results, function(x) trimws(gsub("\\n.*$", "", x)))

# Compare with true labels and calculate accuracy
accuracy <- mean(ag_news_sample$LLM_result==ag_news_sample$class)
print(accuracy)
```

---

### Customization

All generation functions (`quick_llama()`, `generate()`, and `generate_parallel()`) accept a wide range of parameters to control model behavior, performance, and output. 

#### Temperature

These parameters control the creativity of the output.

-   **`temperature`**: Controls creativity. Default is `0.0`. Set to 0 for factual tasks. Higher values (e.g., `0.7`-`1.0`) make output more creative and diverse.
-   **`top_k`**: Default is `40`. The model considers only the top `k` most likely tokens at each step. Higher values increase diversity.
-   **`top_p`**: Default is `1.0` (disabled). Nucleus sampling threshold. Set to `0.9` to select from tokens whose cumulative probability exceeds 90%.
-   **`repeat_last_n`**: Default is `0` (disabled). Number of recent tokens to consider for repetition penalty.
-   **`penalty_repeat`**: Default is `1.0` (disabled). Set to values >1.0 (e.g., `1.1`) to discourage repetition.

```r
# Default behavior
factual <- quick_llama("What is the capital of France?")

# Creative response with higher temperature
creative <- quick_llama("Write a short story about a robot who discovers music.",
                       temperature = 0.8)

# Prevent repetition
no_repeat <- quick_llama("Tell me about AI",
                         repeat_last_n = 64,
                         penalty_repeat = 1.1)
```

#### Model Download

You can point the package at any GGUF model by URL, local path, or cached filename.

```r
# Download a different model from Hugging Face (cached automatically)
response <- quick_llama(
  "Explain quantum physics in simple terms",
  model = "https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q2_K.gguf"
)

# Load a local model file you have already downloaded
response <- quick_llama("Explain quantum physics in simple terms", 
  model = "/path/to/your/local_model.gguf")

# Reuse a cached model by name fragment (auto-detected from cache)
response <- quick_llama("Explain quantum physics in simple terms", 
  model = "Llama-3.2")
```

If you provide a name fragment instead of a full path/URL, the loader searches the cache first. A single match loads immediately; multiple matches are printed so you can choose interactively.

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
cache_root <- tools::R_user_dir("localLLM", which = "cache")
models_dir <- file.path(cache_root, "models")
unlink(models_dir, recursive = TRUE, force = TRUE)
```

This will remove all cached models and lock files, allowing fresh downloads.

#### Private Hugging Face Models

Some Hugging Face repositories require an access token. Set the token once per session using `set_hf_token()` before calling `quick_llama()`, `model_load()`, or `download_model()`. The helper wires the token into the backend without printing it to the console. If you want the token to persist across sessions you must supply an explicit file path with `renviron_path`; by default nothing is written to the home directory.

```r
# Store the token for this session
set_hf_token('hf_your_token_here')

# Optionally persist it to a specific file that you control
# tmp_env <- file.path(tempdir(), ".Renviron_localLLM")
# set_hf_token(
#   'hf_your_token_here',
#   persist = TRUE,
#   renviron_path = tmp_env
# )
#
# For a persistent location, point `renviron_path` to a file you manage, e.g.:
# secure_env <- file.path('/path/to/secure/location', '.Renviron_localLLM')
# set_hf_token(
#   'hf_your_token_here',
#   persist = TRUE,
#   renviron_path = secure_env
# )

# Now you can load gated models by URL
model <- model_load('https://huggingface.co/google/gated-model/resolve/main/model.gguf')
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

-   `n_gpu_layers = 0`: Use CPU only.
-   `n_gpu_layers > 0`: Offloads a specific number of layers to the GPU. To offload all possible layers, set this to a very high number (e.g., `999`).

```r
# Offload as many layers as possible to the GPU for the fastest generation
quick_llama("Tell me a joke", n_gpu_layers = 999)
```

#### All Other Parameters

The generation functions provide full control over the `llama.cpp` backend. Some other useful parameters include:

-   **`system_prompt` (character)**: Sets the initial instruction for the model to define its role or persona (default: `"You are a helpful assistant."`).
-   **`n_threads` (integer)**: The number of CPU threads to use for processing. Defaults to auto-detection for optimal performance.
-   **`seed` (integer)**: Random seed for reproducible generation (default: `1234`). Setting a seed ensures you get the exact same output for the same prompt every time.
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

### Report bugs
Please report bugs to **xu2009@purdue.edu** with your sample
code and data file. Much appreciated!
