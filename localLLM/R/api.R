# --- FILE: localLLM/R/api.R ---

#' Initialize localLLM backend
#'
#' Initialize the backend library. This should be called once before using other functions.
#'
#' @return No return value, called for side effects (initializes backend).
#' @export
backend_init <- function() {
  .ensure_backend_loaded()
  invisible(.Call("c_r_backend_init"))
}

#' Free localLLM backend
#'
#' Clean up backend resources. Usually called automatically.
#'
#' @return No return value, called for side effects (frees backend resources).
#' @export
backend_free <- function() {
  if (.is_backend_loaded()) {
    invisible(.Call("c_r_backend_free"))
  }
}

#' Load Language Model with Automatic Download Support
#'
#' Loads a GGUF format language model from local path or URL with intelligent caching
#' and download management. Supports various model sources including Hugging Face, 
#' Ollama repositories, and direct HTTPS URLs. Models are automatically cached to 
#' avoid repeated downloads.
#'
#' @param model_path Path to local GGUF model file, URL, or cached model name. Supported URL formats:
#'   \itemize{
#'     \item \code{https://} - Direct download from web servers
#'   }
#'   If you previously downloaded a model through this package you can supply the
#'   cached file name (or a distinctive fragment of it) instead of the full path
#'   or URL. The loader will search the local cache and offer any matches.
#' @param cache_dir Custom directory for downloaded models (default: NULL uses system cache directory)
#' @param n_gpu_layers Number of transformer layers to offload to GPU (default: 0 for CPU-only). 
#'   Set to -1 to offload all layers, or a positive integer for partial offloading
#' @param use_mmap Enable memory mapping for efficient model loading (default: TRUE). 
#'   Disable only if experiencing memory issues
#' @param use_mlock Lock model in physical memory to prevent swapping (default: FALSE). 
#'   Enable for better performance but requires sufficient RAM
#' @param show_progress Display download progress bar for remote models (default: TRUE)
#' @param force_redownload Force re-download even if cached version exists (default: FALSE). 
#'   Useful for updating to newer model versions
#' @param verify_integrity Verify file integrity using checksums when available (default: TRUE)
#' @param check_memory Check if sufficient system memory is available before loading (default: TRUE)
#' @param hf_token Optional Hugging Face access token to set during model resolution. Defaults to the existing `HF_TOKEN` environment variable.
#' @param verbosity Control backend logging during model loading (default: 1L).
#'   Larger numbers print more detail: \code{0} shows only errors, \code{1}
#'   adds warnings, \code{2} prints informational messages, and \code{3}
#'   enables the most verbose debug output.
#' @return A model object (external pointer) that can be used with \code{\link{context_create}}, 
#'   \code{\link{tokenize}}, and other model functions
#' @export
#' @examples
#' \dontrun{
#' # Load local GGUF model
#' model <- model_load("/path/to/my_model.gguf")
#' 
#' # Download from Hugging Face and cache locally
#' hf_path = "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"
#' model <- model_load(hf_path)
#' 
#' # Load with GPU acceleration (offload 10 layers)
#' model <- model_load("/path/to/model.gguf", n_gpu_layers = 10)
#' 
#' # Download to custom cache directory
#' model <- model_load(hf_path, 
#'                     cache_dir = file.path(tempdir(), "my_models"))
#' 
#' # Force fresh download (ignore cache)
#' model <- model_load(hf_path, 
#'                     force_redownload = TRUE)
#' 
#' # High-performance settings for large models
#' model <- model_load("/path/to/large_model.gguf", 
#'                     n_gpu_layers = -1,     # All layers on GPU
#'                     use_mlock = TRUE)      # Lock in memory
#' 
#' # Load with minimal verbosity (quiet mode)
#' model <- model_load("/path/to/model.gguf", verbosity = 2L)
#' }
#' @seealso \code{\link{context_create}}, \code{\link{download_model}}, \code{\link{get_model_cache_dir}}, \code{\link{list_cached_models}}
model_load <- function(model_path, cache_dir = NULL, n_gpu_layers = 0L, use_mmap = TRUE, 
                       use_mlock = FALSE, show_progress = TRUE, force_redownload = FALSE, 
                       verify_integrity = TRUE, check_memory = TRUE, hf_token = NULL, verbosity = 1L) {
  .ensure_backend_loaded()
  
  # Resolve model path (download if needed)
  resolved_path <- .resolve_model_path(model_path, cache_dir, show_progress, 
                                       force_redownload, verify_integrity, hf_token)
  if (is.null(resolved_path)) {
    stop("Model selection was cancelled. Provide a specific path or URL to continue.", call. = FALSE)
  }
  
  # Check memory availability before loading
  if (check_memory) {
    .check_model_memory_requirements(resolved_path)
  }
  
  .Call("c_r_model_load_safe", 
        as.character(resolved_path),
        as.integer(n_gpu_layers), 
        as.logical(use_mmap),
        as.logical(use_mlock),
        as.logical(check_memory),
        as.integer(verbosity))
}

#' Create Inference Context for Text Generation
#'
#' Creates a context object that manages the computational state for text generation.
#' The context maintains the conversation history and manages memory efficiently for
#' processing input tokens and generating responses. Each model can have multiple
#' contexts with different settings.
#'
#' @param model A model object returned by \code{\link{model_load}}
#' @param n_ctx Maximum context length in tokens (default: 2048). This determines how many
#'   tokens of conversation history can be maintained. Larger values require more memory
#'   but allow for longer conversations. Must not exceed the model's maximum context length
#' @param n_threads Number of CPU threads for inference (default: 4). Set to the number
#'   of available CPU cores for optimal performance. Only affects CPU computation
#' @param n_seq_max Maximum number of parallel sequences (default: 1). Used for batch
#'   processing multiple conversations simultaneously. Higher values require more memory
#' @param verbosity Control backend logging during context creation (default: 1L).
#'   Larger values print more information: \code{0} emits only errors, \code{1}
#'   includes warnings, \code{2} adds informational logs, and \code{3}
#'   enables the most verbose debug output.
#' @return A context object (external pointer) used for text generation with \code{\link{generate}}
#' @export
#' @examples
#' \dontrun{
#' # Load model and create basic context
#' model <- model_load("path/to/model.gguf")
#' ctx <- context_create(model)
#' 
#' # Create context with larger buffer for long conversations
#' long_ctx <- context_create(model, n_ctx = 4096)
#' 
#' # High-performance context with more threads
#' fast_ctx <- context_create(model, n_ctx = 2048, n_threads = 8)
#' 
#' # Context for batch processing multiple conversations
#' batch_ctx <- context_create(model, n_ctx = 2048, n_seq_max = 4)
#' 
#' # Create context with minimal verbosity (quiet mode)
#' quiet_ctx <- context_create(model, verbosity = 2L)
#' }
#' @seealso \code{\link{model_load}}, \code{\link{generate}}, \code{\link{tokenize}}
context_create <- function(model, n_ctx = 2048L, n_threads = 4L, n_seq_max = 1L, verbosity = 1L) {
  .ensure_backend_loaded()
  if (!inherits(model, "localllm_model")) {
    stop("Expected a localllm_model object", call. = FALSE)
  }

  ctx <- .Call("c_r_context_create",
               model,
               as.integer(n_ctx),
               as.integer(n_threads),
               as.integer(n_seq_max),
               as.integer(verbosity))

  # Store model reference in context for auto-tokenization support in generate()
  attr(ctx, "model") <- model

  ctx
}

#' Convert Text to Token IDs
#'
#' Converts text into a sequence of integer token IDs that the language model can process.
#' This is the first step in text generation, as models work with tokens rather than raw text.
#' Different models may use different tokenization schemes (BPE, SentencePiece, etc.).
#'
#' @param model A model object created with \code{\link{model_load}}
#' @param text Character string or vector to tokenize. Can be a single text or multiple texts
#' @param add_special Whether to add special tokens like BOS (Beginning of Sequence) and EOS
#'   (End of Sequence) tokens (default: TRUE). These tokens help models understand text boundaries
#' @return Integer vector of token IDs corresponding to the input text. These can be used with
#'   \code{\link{generate}} for text generation or \code{\link{detokenize}} to convert back to text
#' @export
#' @examples
#' \dontrun{
#' # Load model
#' model <- model_load("path/to/model.gguf")
#' 
#' # Basic tokenization
#' tokens <- tokenize(model, "Hello, world!")
#' print(tokens)  # e.g., c(15339, 11, 1917, 0)
#' 
#' # Tokenize without special tokens (for model inputs)
#' raw_tokens <- tokenize(model, "Continue this text", add_special = FALSE)
#' 
#' # Tokenize multiple texts
#' batch_tokens <- tokenize(model, c("First text", "Second text"))
#' 
#' # Check tokenization of specific phrases
#' question_tokens <- tokenize(model, "What is AI?")
#' print(length(question_tokens))  # Number of tokens
#' }
#' @seealso \code{\link{detokenize}}, \code{\link{generate}}, \code{\link{model_load}}
tokenize <- function(model, text, add_special = TRUE) {
  .ensure_backend_loaded()
  if (!inherits(model, "localllm_model")) {
    stop("Expected a localllm_model object", call. = FALSE)
  }
  
  .Call("c_r_tokenize",
        model,
        as.character(text),
        as.logical(add_special))
}

#' Convert Token IDs Back to Text
#'
#' Converts a sequence of integer token IDs back into human-readable text. This is the 
#' inverse operation of tokenization and is typically used to convert model output tokens
#' into text that can be displayed to users.
#'
#' @param model A model object created with \code{\link{model_load}}. Must be the same model
#'   that was used for tokenization to ensure proper decoding
#' @param tokens Integer vector of token IDs to convert back to text. These are typically
#'   generated by \code{\link{tokenize}} or \code{\link{generate}}
#' @return Character string containing the decoded text corresponding to the input tokens
#' @export
#' @examples
#' \dontrun{
#' # Load model
#' model <- model_load("path/to/model.gguf")
#' 
#' # Tokenize then detokenize (round-trip)
#' original_text <- "Hello, how are you today?"
#' tokens <- tokenize(model, original_text)
#' recovered_text <- detokenize(model, tokens)
#' print(recovered_text)  # Should match original_text
#' 
#' # Generate and display text
#' ctx <- context_create(model)
#' generated_text <- generate(ctx, "The weather is", max_tokens = 10)
#' 
#' # Inspect individual tokens
#' single_token <- c(123)  # Some token ID
#' token_text <- detokenize(model, single_token)
#' print(paste("Token", single_token, "represents:", token_text))
#' }
#' @seealso \code{\link{tokenize}}, \code{\link{generate}}, \code{\link{model_load}}
detokenize <- function(model, tokens) {
  .ensure_backend_loaded()
  if (!inherits(model, "localllm_model")) {
    stop("Expected a localllm_model object", call. = FALSE)
  }
  
  .Call("c_r_detokenize",
        model,
        as.integer(tokens))
}

#' Apply Chat Template to Format Conversations
#'
#' Formats conversation messages using the model's built-in chat template or a custom template.
#' This is essential for chat models that expect specific formatting for multi-turn conversations.
#'
#' @param model A model object created with \code{\link{model_load}}
#' @param messages List of chat messages, each with 'role' and 'content' fields. 
#'   Role should be 'user', 'assistant', or 'system'
#' @param template Optional custom template string (default: NULL, uses model's built-in template)
#' @param add_assistant Whether to add assistant prompt suffix for response generation (default: TRUE)
#' @return Formatted prompt string ready for text generation
#' @export
#' @examples
#' \dontrun{
#' # Load a chat model
#' model <- model_load("path/to/chat_model.gguf")
#' 
#' # Format a conversation
#' messages <- list(
#'   list(role = "system", content = "You are a helpful assistant."),
#'   list(role = "user", content = "What is machine learning?"),
#'   list(role = "assistant", content = "Machine learning is..."),
#'   list(role = "user", content = "Give me an example.")
#' )
#' 
#' # Apply chat template
#' formatted_prompt <- apply_chat_template(model, messages)
#' 
#' # Generate response
#' response <- quick_llama(formatted_prompt)
#' }
#' @seealso \code{\link{model_load}}, \code{\link{quick_llama}}, \code{\link{generate}}
apply_chat_template <- function(model, messages, template = NULL, add_assistant = TRUE) {
  .ensure_backend_loaded()
  if (!inherits(model, "localllm_model")) {
    stop("Expected a localllm_model object", call. = FALSE)
  }
  
  .Call("c_r_apply_chat_template",
        model,
        template,
        messages,
        as.logical(add_assistant))
}

#' Generate Text Using Language Model Context
#'
#' Generates text using a loaded language model context with automatic tokenization.
#' Simply provide a text prompt and the model will handle tokenization internally.
#' This function now has a unified API with \code{\link{generate_parallel}}.
#'
#' @param context A context object created with \code{\link{context_create}}
#' @param prompt Character string containing the input text prompt
#' @param max_tokens Maximum number of tokens to generate (default: 100). Higher values produce longer responses
#' @param top_k Top-k sampling parameter (default: 40). Limits vocabulary to k most likely tokens. Use 0 to disable
#' @param top_p Top-p (nucleus) sampling parameter (default: 1.0). Cumulative probability threshold for token selection
#' @param temperature Sampling temperature (default: 0.0). Set to 0 for greedy decoding. Higher values increase creativity
#' @param repeat_last_n Number of recent tokens to consider for repetition penalty (default: 0). Set to 0 to disable
#' @param penalty_repeat Repetition penalty strength (default: 1.0). Values >1 discourage repetition. Set to 1.0 to disable
#' @param seed Random seed for reproducible generation (default: 1234). Use positive integers for deterministic output
#' @param clean If TRUE, strip common chat-template control tokens from the generated text (default: FALSE).
#' @return Character string containing the generated text
#' @export
#' @examples
#' \dontrun{
#' # Load model and create context
#' model <- model_load("path/to/model.gguf")
#' ctx <- context_create(model, n_ctx = 2048)
#'
#' response <- generate(ctx, "Hello, how are you?", max_tokens = 50)
#'
#' # Creative writing with higher temperature
#' story <- generate(ctx, "Once upon a time", max_tokens = 200, temperature = 0.8)
#'
#' # Prevent repetition
#' no_repeat <- generate(ctx, "Tell me about AI",
#'                      repeat_last_n = 64,
#'                      penalty_repeat = 1.1)
#'
#' # Clean output (remove special tokens)
#' clean_output <- generate(ctx, "Explain quantum physics", clean = TRUE)
#' }
#' @seealso \code{\link{quick_llama}}, \code{\link{generate_parallel}}, \code{\link{context_create}}
generate <- function(context, prompt, max_tokens = 100L, top_k = 40L, top_p = 1.0,
                     temperature = 0.0, repeat_last_n = 0L, penalty_repeat = 1.0,
                     seed = 1234L, clean = FALSE) {
  .ensure_backend_loaded()
  if (!inherits(context, "localllm_context")) {
    stop("Expected a localllm_context object", call. = FALSE)
  }

  # Validate prompt input
  if (!is.character(prompt) || length(prompt) != 1) {
    stop("prompt must be a single character string", call. = FALSE)
  }

  # Extract model from context for tokenization
  model <- attr(context, "model")
  if (is.null(model)) {
    stop("Context must have an associated model. Please recreate the context using context_create().",
         call. = FALSE)
  }

  # Auto-tokenize the prompt
  tokens <- tokenize(model, prompt, add_special = TRUE)

  result <- .Call("c_r_generate",
                  context,
                  tokens,
                  as.integer(max_tokens),
                  as.integer(top_k),
                  as.numeric(top_p),
                  as.numeric(temperature),
                  as.integer(repeat_last_n),
                  as.numeric(penalty_repeat),
                  as.integer(seed))

  if (isTRUE(clean)) {
    result <- .clean_output(result)
  }

  result
}

#' Generate Text in Parallel for Multiple Prompts
#'
#' @param context A context object created with \code{\link{context_create}}
#' @param prompts Character vector of input text prompts
#' @param max_tokens Maximum number of tokens to generate (default: 100)
#' @param top_k Top-k sampling parameter (default: 40). Limits vocabulary to k most likely tokens
#' @param top_p Top-p (nucleus) sampling parameter (default: 1.0). Cumulative probability threshold for token selection
#' @param temperature Sampling temperature (default: 0.0). Set to 0 for greedy decoding. Higher values increase creativity
#' @param repeat_last_n Number of recent tokens to consider for repetition penalty (default: 0). Set to 0 to disable
#' @param penalty_repeat Repetition penalty strength (default: 1.0). Values >1 discourage repetition. Set to 1.0 to disable
#' @param seed Random seed for reproducible generation (default: 1234). Use positive integers for deterministic output
#' @param progress If \code{TRUE}, displays a console progress bar indicating batch
#'   completion status while generations are running (default: FALSE).
#' @param clean If TRUE, remove common chat-template control tokens from each generated text (default: FALSE).
#' @return Character vector of generated texts
#' @export
generate_parallel <- function(context, prompts, max_tokens = 100L, top_k = 40L, top_p = 1.0,
                              temperature = 0.0, repeat_last_n = 0L, penalty_repeat = 1.0,
                              seed = 1234L, progress = FALSE, clean = FALSE) {
  .ensure_backend_loaded()
  if (!inherits(context, "localllm_context")) {
    stop("Expected a localllm_context object", call. = FALSE)
  }
  
  result <- .Call("c_r_generate_parallel",
        context,
        as.character(prompts),
        as.integer(max_tokens),
        as.integer(top_k),
        as.numeric(top_p),
        as.numeric(temperature),
        as.integer(repeat_last_n),
        as.numeric(penalty_repeat),
        as.integer(seed),
        as.logical(progress))

  if (isTRUE(clean)) {
    if (is.list(result)) {
      result <- lapply(result, .clean_output)
    } else if (is.character(result)) {
      result <- vapply(result, .clean_output, character(1), USE.NAMES = TRUE)
    }
  }

  result
}

#' Test tokenize function (debugging)
#'
#' @param model A model object
#' @return Integer vector of tokens for "H"
#' @export
tokenize_test <- function(model) {
  .ensure_backend_loaded()
  if (!inherits(model, "localllm_model")) {
    stop("Expected a localllm_model object", call. = FALSE)
  }
  
  .Call("c_r_tokenize_test", model)
}

#' Download a model manually
#'
#' @param model_url URL of the model to download (currently only supports https://)
#' @param output_path Local path where to save the model (optional, will use cache if not provided)
#' @param show_progress Whether to show download progress (default: TRUE)
#' @param verify_integrity Verify file integrity after download (default: TRUE)
#' @param max_retries Maximum number of download retries (default: 3)
#' @param hf_token Optional Hugging Face access token to use for this download. Defaults to the existing `HF_TOKEN` environment variable.
#' @return The path where the model was saved
#' @export
#' @examples
#' \dontrun{
#' # Download to specific location
#' download_model(
#'   "https://example.com/model.gguf",
#'   file.path(tempdir(), "my_model.gguf")
#' )
#' 
#' # Download to cache (path will be returned)
#' cached_path <- download_model("https://example.com/model.gguf")
#' }
download_model <- function(model_url, output_path = NULL, show_progress = TRUE, 
                           verify_integrity = TRUE, max_retries = 3, hf_token = NULL) {
  .ensure_backend_loaded()
  
  if (is.null(output_path)) {
    output_path <- .get_cache_path(model_url)
  }
  
  # Create output directory if it doesn't exist
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  message("Downloading model from: ", model_url)
  message("Saving to: ", output_path)
  
  # Download with retry mechanism
  .download_with_retry(model_url, output_path, show_progress, max_retries, hf_token)
  
  # Verify integrity if requested
  if (verify_integrity) {
    if (!.verify_file_integrity(output_path)) {
      file.remove(output_path)
      stop("Downloaded file failed integrity check", call. = FALSE)
    }
  }
  
  message("Model downloaded successfully!")
  return(output_path)
}

#' Get the model cache directory
#'
#' @return Path to the directory where models are cached
#' @export
get_model_cache_dir <- function() {
  return(.get_model_cache_dir())
}

# --- Helper Functions for Model Download ---

#' Check if a string represents a URL
#' @param path The path/URL to check
#' @return TRUE if it's a URL, FALSE otherwise
#' @noRd
.is_url <- function(path) {
  if (is.null(path) || length(path) == 0 || nchar(path) == 0) {
    return(FALSE)
  }
  
  # Check for common URL protocols
  url_patterns <- c("^https?://", "^hf://", "^huggingface://", "^ollama://", 
                    "^ms://", "^modelscope://", "^github://", "^s3://", "^file://")
  
  for (pattern in url_patterns) {
    if (grepl(pattern, path, ignore.case = TRUE)) {
      return(TRUE)
    }
  }
  
  return(FALSE)
}

#' Get cache directory for models
#' @param cache_dir Custom cache directory (if NULL, uses default)
#' @return Path to the model cache directory
#' @noRd
.get_model_cache_dir <- function(cache_dir = NULL) {
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE)
    }
    return(cache_dir)
  }
  
  # Check environment variable
  env_cache <- Sys.getenv("LOCALLLM_CACHE_DIR", unset = NA)
  if (!is.na(env_cache) && nchar(env_cache) > 0) {
    if (!dir.exists(env_cache)) {
      dir.create(env_cache, recursive = TRUE)
    }
    return(env_cache)
  }
  
  # Default cache directory
  cache_dir <- tools::R_user_dir("localLLM", which = "cache")
  models_dir <- file.path(cache_dir, "models")
  
  if (!dir.exists(models_dir)) {
    dir.create(models_dir, recursive = TRUE)
  }
  
  return(models_dir)
}

#' List cached models on disk
#'
#' Enumerates the models that have been downloaded to the local cache. This is
#' useful when you want to reuse a previously downloaded model but no longer
#' remember the original URL. The cache directory can be overridden with the
#' `LOCALLLM_CACHE_DIR` environment variable or via the `cache_dir` argument.
#'
#' @param cache_dir Optional cache directory to inspect. Defaults to the package
#'   cache used by `model_load()`.
#'
#' @return A data frame with one row per cached model and the columns
#'   `name` (file name), `path` (absolute path), `size_bytes`, and `modified`.
#'   Returns an empty data frame when no models are cached.
#' @export
list_cached_models <- function(cache_dir = NULL) {
  cached <- .list_cached_models(cache_dir)
  if (nrow(cached) == 0) {
    message("No cached models were found. Use download_model() or model_load() with a URL to populate the cache.")
  }
  cached
}

#' @noRd
.list_cached_models <- function(cache_dir = NULL) {
  cache_dir <- .get_model_cache_dir(cache_dir)

  if (!dir.exists(cache_dir)) {
    return(data.frame(
      name = character(),
      path = character(),
      size_bytes = numeric(),
      modified = as.POSIXct(character()),
      stringsAsFactors = FALSE
    ))
  }

  files <- list.files(cache_dir, pattern = "\\.(gguf|bin)$", full.names = TRUE, recursive = TRUE)
  if (length(files) == 0) {
    return(data.frame(
      name = character(),
      path = character(),
      size_bytes = numeric(),
      modified = as.POSIXct(character()),
      stringsAsFactors = FALSE
    ))
  }

  info <- file.info(files)
  data.frame(
    name = basename(files),
    path = normalizePath(files, winslash = "/", mustWork = FALSE),
    size_bytes = as.numeric(info$size),
    modified = info$mtime,
    stringsAsFactors = FALSE
  )
}

#' @noRd
.resolve_model_name <- function(model_name, cache_dir = NULL) {
  if (is.null(model_name) || length(model_name) == 0 || nchar(model_name) == 0) {
    return(NULL)
  }

  cached <- .list_cached_models(cache_dir)
  if (nrow(cached) == 0) {
    return(NULL)
  }

  matches <- cached[grepl(model_name, cached$name, ignore.case = TRUE), , drop = FALSE]
  if (nrow(matches) == 0) {
    matches <- cached[grepl(model_name, cached$path, ignore.case = TRUE), , drop = FALSE]
  }

  if (nrow(matches) == 0) {
    return(NULL)
  }

  matches <- matches[order(matches$modified, decreasing = TRUE), , drop = FALSE]

  if (nrow(matches) == 1) {
    message("Using cached model: ", matches$path)
    return(matches$path)
  }

  message(sprintf("Multiple cached models matched '%s':", model_name))
  for (i in seq_len(nrow(matches))) {
    size_mb <- round(matches$size_bytes[i] / 1024 / 1024, 1)
    message(sprintf("[%d] %s (%.1f MB) - %s", i, matches$name[i], size_mb, matches$path[i]))
  }

  selection_option <- getOption("localllm.cache_selection", default = NULL)
  if (!is.null(selection_option)) {
    idx <- suppressWarnings(as.integer(selection_option))
    if (!is.na(idx) && idx >= 1 && idx <= nrow(matches)) {
      message("Selected cached model via option localllm.cache_selection = ", idx)
      return(matches$path[idx])
    }
    warning("Ignoring invalid localllm.cache_selection option; falling back to interactive prompt.")
  }

  if (!interactive()) {
    stop(
      sprintf(
        "Multiple cached models matched '%s'. Use list_cached_models() to inspect the cache and provide a more specific name or path.",
        model_name
      ),
      call. = FALSE
    )
  }

  repeat {
    answer <- readline("Enter the number of the model to use (press Enter to cancel): ")
    if (identical(answer, "")) {
      message("Selection cancelled. Please provide a more specific path or URL.")
      return(NULL)
    }
    idx <- suppressWarnings(as.integer(answer))
    if (!is.na(idx) && idx >= 1 && idx <= nrow(matches)) {
      return(matches$path[idx])
    }
    message(sprintf("Invalid selection. Please enter a number between 1 and %d.", nrow(matches)))
  }
}

#' Generate cache path for a model URL
#' @param model_url The model URL
#' @param cache_dir Custom cache directory (optional)
#' @return Local cache path for the model
#' @noRd
.get_cache_path <- function(model_url, cache_dir = NULL) {
  cache_dir <- .get_model_cache_dir(cache_dir)
  
  # Extract filename from URL
  # For most URLs, this will be the last part after the final /
  filename <- basename(model_url)
  
  # If no extension or generic name, add .gguf
  if (!grepl("\\.(gguf|bin)$", filename, ignore.case = TRUE)) {
    if (filename == "" || filename == model_url) {
      # Generate a reasonable filename from the URL
      clean_url <- gsub("[^a-zA-Z0-9._-]", "_", model_url)
      filename <- paste0(substr(clean_url, 1, 50), ".gguf")
    } else {
      filename <- paste0(filename, ".gguf")
    }
  }
  
  return(file.path(cache_dir, filename))
}

#' Download a model to cache
#' @param model_url The model URL
#' @param cache_path The local cache path
#' @param show_progress Whether to show download progress
#' @noRd
.download_model_to_cache <- function(model_url, cache_path, show_progress = TRUE, hf_token = NULL) {
  # Create output directory if it doesn't exist
  output_dir <- dirname(cache_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  message("Downloading model from: ", model_url)
  message("Saving to: ", cache_path)
  
  # Download with retry mechanism
  .download_with_retry(model_url, cache_path, show_progress, hf_token = hf_token)
  
  message("Model downloaded successfully!")
}

#' Resolve model path (download if needed)
#' @param model_path The model path or URL
#' @param cache_dir Custom cache directory (optional)
#' @param show_progress Whether to show download progress
#' @param force_redownload Force re-download even if cached version exists
#' @param verify_integrity Verify file integrity
#' @return The resolved local file path
#' @noRd
.resolve_model_path <- function(model_path, cache_dir = NULL, show_progress = TRUE, 
                                force_redownload = FALSE, verify_integrity = TRUE, hf_token = NULL) {
  # If it's a local file that exists, verify and return
  if (!.is_url(model_path) && file.exists(model_path)) {
    if (verify_integrity && !.verify_file_integrity(model_path)) {
      stop("Local model file failed integrity check: ", model_path, call. = FALSE)
    }
    return(model_path)
  }
  
  # If it's a URL, handle download
  if (.is_url(model_path)) {
    cache_path <- .get_cache_path(model_path, cache_dir)
    
    # Check if cached version exists and is valid
    if (file.exists(cache_path) && !force_redownload) {
      if (verify_integrity) {
        if (.verify_file_integrity(cache_path)) {
          message("Using cached model: ", cache_path)
          return(cache_path)
        } else {
          message("Cached model failed integrity check, re-downloading...")
          file.remove(cache_path)
        }
      } else {
        message("Using cached model: ", cache_path)
        return(cache_path)
      }
    }
    
    # Download to cache
    .download_model_to_cache(model_path, cache_path, show_progress, hf_token = hf_token)
    
    # Verify downloaded file
    if (verify_integrity && !.verify_file_integrity(cache_path)) {
      file.remove(cache_path)
      stop("Downloaded model failed integrity check", call. = FALSE)
    }
    
    return(cache_path)
  }
  
  # Attempt to resolve by cached model name
  cached_path <- .resolve_model_name(model_path, cache_dir)
  if (!is.null(cached_path)) {
    if (verify_integrity && !.verify_file_integrity(cached_path)) {
      stop(
        sprintf("Cached model at '%s' failed the integrity check. Consider redownloading the model.", cached_path),
        call. = FALSE
      )
    }
    return(cached_path)
  }

  # If it's neither a URL nor an existing file, it's an error
  stop("Model file does not exist and is not a valid URL: ", model_path, call. = FALSE)
}

#' Verify file integrity
#' @param file_path Path to the file to verify
#' @param expected_size Expected file size in bytes (optional)
#' @return TRUE if file is valid, FALSE otherwise
#' @noRd
.verify_file_integrity <- function(file_path, expected_size = NULL) {
  if (!file.exists(file_path)) {
    return(FALSE)
  }
  
  file_info <- file.info(file_path)
  
  # Check if file is empty or suspiciously small
  if (file_info$size < 1024) {  # Less than 1KB
    return(FALSE)
  }
  
  # Check expected size if provided
  if (!is.null(expected_size) && file_info$size != expected_size) {
    return(FALSE)
  }
  
  # Basic GGUF format check
  if (!.is_valid_gguf_file(file_path)) {
    return(FALSE)
  }
  
  return(TRUE)
}

#' Check if file is a valid GGUF file
#' @param file_path Path to the file to check
#' @return TRUE if valid GGUF file, FALSE otherwise
#' @noRd
.is_valid_gguf_file <- function(file_path) {
  tryCatch({
    con <- file(file_path, "rb")
    on.exit(close(con), add = TRUE)
    
    # Read first 4 bytes for GGUF magic number
    magic <- readBin(con, "raw", n = 4)
    
    # GGUF magic number: "GGUF" (0x47474755)
    expected_magic <- as.raw(c(0x47, 0x47, 0x55, 0x46))
    
    return(identical(magic, expected_magic))
  }, error = function(e) {
    return(FALSE)
  })
}

#' Check memory requirements for model loading
#' @param model_path Path to the model file
#' @noRd
.check_model_memory_requirements <- function(model_path) {
  .ensure_backend_loaded()
  
  tryCatch({
    # Get estimated memory requirement
    estimated_memory <- .Call("c_r_estimate_model_memory", as.character(model_path))
    
    # Check if sufficient memory is available
    memory_available <- .Call("c_r_check_memory_available", as.numeric(estimated_memory))
    
    if (!memory_available) {
      file_size_mb <- round(file.info(model_path)$size / 1024 / 1024, 1)
      estimated_mb <- round(estimated_memory / 1024 / 1024, 1)
      
      warning("Insufficient memory detected. Model file size: ", file_size_mb, 
              "MB, estimated memory requirement: ", estimated_mb, "MB. ",
              "Loading may cause system instability or crashes.", call. = FALSE)
              
      response <- readline("Do you want to continue anyway? (y/N): ")
      if (tolower(trimws(response)) != "y") {
        stop("Model loading cancelled by user due to insufficient memory", call. = FALSE)
      }
    }
  }, error = function(e) {
    # If memory check fails, issue warning but continue
    warning("Could not check memory requirements: ", e$message, call. = FALSE)
  })
}

#' Download with retry mechanism
#' @param model_url URL to download from
#' @param output_path Local path to save to
#' @param show_progress Whether to show progress
#' @param max_retries Maximum number of retries
#' @noRd
.download_with_retry <- function(model_url, output_path, show_progress = TRUE, max_retries = 3, hf_token = NULL) {
  .with_hf_token(hf_token, {
    .ensure_backend_loaded()
    
    # Create lock file to prevent concurrent downloads
    lock_file <- paste0(output_path, ".lock")
    
    # Check if another process is downloading
    if (file.exists(lock_file)) {
      message("Another download in progress, waiting...")
      for (i in 1:30) {  # Wait up to 30 seconds
        Sys.sleep(1)
        if (!file.exists(lock_file)) break
      }
      
      if (file.exists(lock_file)) {
        stop("Download timeout: another process seems to be stuck", call. = FALSE)
      }
    }
    
    # Create lock file
    file.create(lock_file)
    on.exit({
      if (file.exists(lock_file)) {
        file.remove(lock_file)
      }
    }, add = TRUE)
    
    last_error <- NULL
    
    for (attempt in 1:max_retries) {
      if (attempt > 1) {
        message("Download attempt ", attempt, " of ", max_retries, "...")
        Sys.sleep(2)  # Brief delay between retries
      }
      
      tryCatch({
        # Try C++ download first
        .Call("c_r_download_model", 
              as.character(model_url),
              as.character(output_path),
              as.logical(show_progress))
        
        # Check if download was successful
        if (file.exists(output_path) && file.info(output_path)$size > 0) {
          return()
        }
        
        stop("Download produced empty file")
        
      }, error = function(e) {
        last_error <<- e
        
        # Clean up partial download
        if (file.exists(output_path)) {
          file.remove(output_path)
        }
        
        # Try R fallback on last attempt
        if (attempt == max_retries) {
          message("C++ download failed, trying R fallback...")
          
          tryCatch({
            utils::download.file(model_url, output_path, mode = "wb", 
                                method = "auto", quiet = !show_progress)
            
            if (file.exists(output_path) && file.info(output_path)$size > 0) {
              return()
            }
            
          }, error = function(e2) {
            last_error <<- e2
          })
        }
      })
    }
    
    # If we get here, all attempts failed
    stop("Download failed after ", max_retries, " attempts. Last error: ", 
         last_error$message, call. = FALSE)
  })
} 
