# --- FILE: localLLM/R/quick_llama.R ---

# Package-level globals for caching
.quick_llama_env <- new.env(parent = emptyenv())
.quick_llama_env$suppress_messages <- FALSE

# Keep console quiet when verbosity < 0
.localllm_message <- function(...) {
  if (!isTRUE(.quick_llama_env$suppress_messages)) {
    message(...)
  }
}

# Track and restore quiet-mode state
.localllm_set_quiet <- function(quiet) {
  previous <- .quick_llama_env$suppress_messages
  if (isTRUE(quiet)) {
    .quick_llama_env$suppress_messages <- TRUE
  }
  previous
}

.localllm_restore_quiet <- function(previous) {
  .quick_llama_env$suppress_messages <- isTRUE(previous)
}

#' Quick LLaMA Inference
#'
#' A high-level convenience function that provides one-line LLM inference.
#' Automatically handles model downloading, loading, and text generation with optional
#' chat template formatting and system prompts for instruction-tuned models.
#'
#' @param prompt Character string or vector of prompts to process
#' @param model Model URL or path (default: Llama 3.2 3B Instruct Q5_K_M)
#' @param n_threads Number of threads (default: auto-detect)
#' @param n_gpu_layers Number of GPU layers (default: auto-detect)
#' @param n_ctx Context size (default: 2048)
#' @param max_tokens Maximum tokens to generate (default: 100)
#' @param temperature Sampling temperature (default: 0.0). Higher values increase creativity
#' @param top_p Top-p sampling (default: 1.0). Set to 0.9 for nucleus sampling
#' @param top_k Top-k sampling (default: 40). Limits vocabulary to k most likely tokens
#' @param verbosity Backend logging verbosity (default: 1L). Higher values show more
#'   detail: \code{0} prints only errors, \code{1} adds warnings, \code{2}
#'   includes informational messages, and \code{3} enables the most verbose debug
#'   output.
#' @param repeat_last_n Number of recent tokens to consider for repetition penalty (default: 0). Set to 0 to disable
#' @param penalty_repeat Repetition penalty strength (default: 1.0). Set to 1.0 to disable
#' @param min_p Minimum probability threshold (default: 0.05)
#' @param system_prompt System prompt to add to conversation (default: "You are a helpful assistant.")
#' @param auto_format Whether to automatically apply chat template formatting (default: TRUE)
#' @param chat_template Custom chat template to use (default: NULL uses model's built-in template)
#' @param stream Whether to stream output (default: auto-detect based on interactive())
#' @param seed Random seed for reproducibility (default: 1234)
#' @param progress Show a console progress bar when running parallel generation.
#'   Default: \code{interactive()}. Has no effect for single-prompt runs.
#' @param clean Whether to strip chat-template control tokens from the generated output.
#'   Defaults to \code{TRUE}.
#' @param hash When `TRUE` (default), compute SHA-256 hashes for the prompts fed into the
#'   backend and the corresponding outputs. Hashes are attached via the
#'   `"hashes"` attribute for later inspection.
#' @param ... Additional parameters passed to generate() or generate_parallel()
#'
#' @return Character string (single prompt) or named list (multiple prompts)
#' @export
#' @seealso \code{\link{model_load}}, \code{\link{generate}}, \code{\link{generate_parallel}}, \code{\link{install_localLLM}}
#'
#' @examples
#' \dontrun{
#' # Simple usage with default settings (deterministic)
#' response <- quick_llama("Hello, how are you?")
#'
#' # Raw text generation without chat template
#' raw_response <- quick_llama("Complete this: The capital of France is",
#'                            auto_format = FALSE)
#'
#' # Custom system prompt
#' code_response <- quick_llama("Write a Python hello world program",
#'                             system_prompt = "You are a Python programming expert.")
#'
#' # Creative writing with higher temperature
#' creative_response <- quick_llama("Tell me a story",
#'                                  temperature = 0.8,
#'                                  max_tokens = 200)
#'
#' # Prevent repetition
#' no_repeat <- quick_llama("Explain AI",
#'                         repeat_last_n = 64,
#'                         penalty_repeat = 1.1)
#'
#' # Multiple prompts (parallel processing)
#' responses <- quick_llama(c("Summarize AI", "Explain quantum computing"),
#'                         max_tokens = 150)
#' }
#'
quick_llama <- function(prompt,
                        model = .get_default_model(),
                        n_threads = NULL,
                        n_gpu_layers = "auto",
                        n_ctx = 2048L,
                        verbosity = 1L,
                        max_tokens = 100L,
                        top_k = 40L,
                        top_p = 1.0,
                        temperature = 0.0,
                        repeat_last_n = 0L,
                        penalty_repeat = 1.0,
                        min_p = 0.05,
                        system_prompt = "You are a helpful assistant.",
                        auto_format = TRUE,
                        chat_template = NULL,
                        stream = FALSE,
                        seed = 1234L,
                        progress = interactive(),
                        clean = TRUE,
                        hash = TRUE,
                        ...) {
  verbosity <- as.integer(verbosity)
  previous_quiet <- .localllm_set_quiet(verbosity < 0L)
  on.exit(.localllm_restore_quiet(previous_quiet), add = TRUE)
  
  # Validate inputs
  if (missing(prompt) || is.null(prompt) || length(prompt) == 0) {
    stop("Prompt cannot be empty", call. = FALSE)
  }
  
  # Check for empty strings
  if (any(nchar(prompt) == 0)) {
    stop("Prompt cannot be empty", call. = FALSE)
  }
  
  # Ensure stream is logical
  stream <- as.logical(stream)
  
  # Auto-detect n_threads if not specified
  if (is.null(n_threads)) {
    n_threads <- max(1L, parallel::detectCores() - 1L)
  }
  
  # Auto-detect n_gpu_layers if specified as "auto"
  if (identical(n_gpu_layers, "auto")) {
    n_gpu_layers <- .detect_gpu_layers()
  }
  
  # Ensure backend is ready
  .ensure_quick_llama_ready()
  
  # Load model and context if not cached or if different model
  tryCatch({
    .ensure_model_loaded(model, n_gpu_layers, n_ctx, n_threads, verbosity)
  }, error = function(e) {
    stop("Failed to load model: ", e$message, call. = FALSE)
  })
  
  # Format prompt with chat template if requested
  if (auto_format) {
    # Create messages structure
    if (!is.null(system_prompt) && nchar(system_prompt) > 0) {
      messages <- list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = prompt)
      )
    } else {
      messages <- list(
        list(role = "user", content = prompt)
      )
    }
    
    # Apply chat template
    formatted_prompt <- apply_chat_template(.quick_llama_env$model, messages, 
                                           template = chat_template, add_assistant = TRUE)
  } else {
    formatted_prompt <- prompt
  }
  
  # Debug: check EOS token (optional)
  if (verbosity <= 1L && !isTRUE(.quick_llama_env$suppress_messages)) {
    eos_token <- tokenize(.quick_llama_env$model, "", add_special = FALSE)
    .localllm_message("Model EOS token info available for debugging")
  }
  
  # Generate text
  # Determine formatted payload for hashing downstream
  formatted_payload <- NULL

  result <- if (length(prompt) == 1) {
    # Single prompt
    formatted_payload <- formatted_prompt
    .generate_single(formatted_prompt, max_tokens, top_k, top_p, temperature, 
                     repeat_last_n, penalty_repeat, seed, stream)
  } else {
    # Multiple prompts - apply formatting to each prompt
    if (auto_format) {
      formatted_prompts <- sapply(prompt, function(p) {
        if (!is.null(system_prompt) && nchar(system_prompt) > 0) {
          msgs <- list(
            list(role = "system", content = system_prompt),
            list(role = "user", content = p)
          )
        } else {
          msgs <- list(list(role = "user", content = p))
        }
        apply_chat_template(.quick_llama_env$model, msgs, 
                           template = chat_template, add_assistant = TRUE)
      })
    } else {
      formatted_prompts <- prompt
    }
    formatted_payload <- formatted_prompts
    .generate_multiple(formatted_prompts, max_tokens, top_k, top_p, temperature, 
                       repeat_last_n, penalty_repeat, seed, stream, progress)
  }
  
  # Clean up special tokens from output when requested
  if (isTRUE(clean)) {
    if (is.character(result)) {
      if (length(result) == 1) {
        result <- .clean_output(result)
      } else {
        result <- lapply(as.list(result), .clean_output)
      }
    } else if (is.list(result)) {
      result <- lapply(result, .clean_output)
    }
  }

  model_ref <- if (is.character(model) && length(model) == 1) model else "<object>"
  .document_record_event("quick_llama", list(
    model = model_ref,
    prompt_count = length(prompt),
    n_threads = n_threads,
    n_gpu_layers = n_gpu_layers,
    n_ctx = n_ctx,
    max_tokens = max_tokens,
    temperature = temperature,
    top_k = top_k,
    top_p = top_p,
    repeat_last_n = repeat_last_n,
    penalty_repeat = penalty_repeat,
    min_p = min_p,
    seed = seed,
    auto_format = isTRUE(auto_format),
    clean = isTRUE(clean),
    stream = isTRUE(stream)
  ))
  
  if (isTRUE(hash)) {
    attr_model <- .hash_model_identifier(.quick_llama_env$model)
    input_payload <- list(
      type = "quick_llama",
      model_identifier = attr_model,
      model_argument = if (is.character(model) && length(model) == 1) {
        .hash_normalise_model_source(model)
      } else {
        NA_character_
      },
      n_threads = n_threads,
      n_ctx = n_ctx,
      n_gpu_layers = n_gpu_layers,
      params = list(
        max_tokens = max_tokens,
        top_k = top_k,
        top_p = top_p,
        temperature = temperature,
        repeat_last_n = repeat_last_n,
        penalty_repeat = penalty_repeat,
        min_p = min_p,
        seed = seed,
        auto_format = isTRUE(auto_format),
        system_prompt = system_prompt,
        chat_template = chat_template %||% NA_character_,
        clean = isTRUE(clean),
        stream = isTRUE(stream)
      ),
      raw_prompt = prompt,
      formatted_prompt = formatted_payload
    )
    output_payload <- list(type = "quick_llama", output = result)
    input_hash <- .hash_payload(input_payload)
    output_hash <- .hash_payload(output_payload)
    result <- .hash_attach_metadata(result, input_hash, output_hash, "quick_llama")
  }

  result
}

#' Reset quick_llama state
#'
#' Clears cached model and context objects, forcing fresh initialization
#' on the next call to quick_llama().
#'
#' @return No return value, called for side effects (resets cached state).
#' @export
quick_llama_reset <- function() {
  if (exists("model", envir = .quick_llama_env)) {
    rm(list = ls(envir = .quick_llama_env), envir = .quick_llama_env)
  }
  .quick_llama_env$suppress_messages <- FALSE
  message("quick_llama state reset")
  invisible(NULL)
}

# --- Helper Functions ---

#' Clean output by removing special tokens
#' @param text The generated text to clean
#' @return Cleaned text
#' @noRd
.clean_output <- function(text) {
  if (!is.character(text) || length(text) == 0) {
    return(text)
  }

  # Normalise line endings to simplify regex handling
  text <- gsub('\r\n', '\n', text, perl = TRUE)

  # Remove chat template markers such as <|start_header|>, <|im_start|>, etc.
  text <- gsub("<[\u007c\uff5c][^\u007c\uff5c>]+[\u007c\uff5c]>(?:assistant|user|system)?\\s*", "", text, perl = TRUE, ignore.case = TRUE)

  # Remove partially emitted control tokens at the end of the string (e.g. '<|start_header')
  text <- gsub("<[\u007c\uff5c][^\u007c\uff5c>]*$", "", text, perl = TRUE)

  # Strip bracket-based instruction markers used by several instruct models
  text <- gsub("\\[/?INST\\]", "", text, perl = TRUE)
  text <- gsub("<<SYS>>|<</SYS>>", "", text, perl = TRUE)
  text <- gsub("</?s>", "", text, ignore.case = TRUE, perl = TRUE)
  text <- gsub("</?(bos|eos)>", "", text, ignore.case = TRUE, perl = TRUE)

  # Remove Gemma-specific turn markers
  text <- gsub("\\s*</?end_of_turn>\\s*", "", text, perl = TRUE, ignore.case = TRUE)
  text <- gsub("\\s*</?start_of_turn>(?:user|model|assistant|system)?\\s*", "", text, perl = TRUE, ignore.case = TRUE)

  text <- gsub("\\s*<\\|im_end\\|>.*$", "", text, perl = TRUE)  # Remove im_end and everything after
  text <- gsub("<\\|im_start\\|>(?:system|user|assistant)?\\s*", "", text, perl = TRUE)
  text <- gsub("<\\|endoftext\\|>\\s*", "", text, perl = TRUE)

  text <- gsub("\\s*<\\|[^|>]*$", "", text, perl = TRUE)

  # Trim whitespace after removals
  text <- trimws(text)

  text
}

#' Get default model URL
#' @return Default model URL
#' @noRd
.get_default_model <- function() {
  "https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q5_K_M.gguf"
}

#' Detect optimal GPU layers
#' @return Integer number of GPU layers
#' @noRd
.detect_gpu_layers <- function() {
  # Try to detect GPU support
  # This is a simplified version - in real implementation, you might
  # want to check for specific GPU libraries or capabilities
  
  sysname <- Sys.info()["sysname"]
  
  # Basic heuristic: if on macOS (likely has Metal), use GPU
  # if on Linux/Windows, be more conservative
  if (sysname == "Darwin") {
    # On macOS, assume Metal is available
    return(999L)  # Use all layers on GPU
  } else if (sysname == "Linux") {
    # On Linux, check if NVIDIA GPU tools are available
    # This is a basic check - more sophisticated detection could be added
    nvidia_smi <- Sys.which("nvidia-smi")
    if (nvidia_smi != "") {
      return(999L)
    }
  }
  
  # Default to CPU-only
  return(0L)
}

#' Ensure backend is ready
#' @noRd
.ensure_quick_llama_ready <- function() {
  # Check if backend library is installed
  if (!lib_is_installed()) {
    .localllm_message("Backend library not found. Installing...")
    install_localLLM()
  }
  
  # Initialize backend if not already done
  if (!.is_backend_loaded()) {
    .localllm_message("Initializing backend...")
    backend_init()
  }
}

#' Ensure model and context are loaded
#' @param model_path Model path or URL
#' @param n_gpu_layers Number of GPU layers
#' @param n_ctx Context size
#' @param n_threads Number of threads
#' @param verbosity Verbosity level
#' @noRd
.ensure_model_loaded <- function(model_path, n_gpu_layers, n_ctx, n_threads, verbosity = 1L) {
  # Check if we have a cached model and context for this configuration
  cache_key <- paste0(model_path, "_", n_gpu_layers, "_", n_ctx, "_", n_threads, "_", verbosity)
  quiet_state <- .localllm_set_quiet(verbosity < 0L)
  on.exit(.localllm_restore_quiet(quiet_state), add = TRUE)
  
  if (exists("cache_key", envir = .quick_llama_env) && 
      identical(.quick_llama_env$cache_key, cache_key) &&
      exists("model", envir = .quick_llama_env) &&
      exists("context", envir = .quick_llama_env)) {
    # Model and context already loaded with same configuration
    return()
  }
  
  # Load model
  .localllm_message("Loading model...")
  model_obj <- model_load(model_path, n_gpu_layers = n_gpu_layers, show_progress = TRUE, verbosity = verbosity)
  
  # Create context
  .localllm_message("Creating context...")
  context_obj <- context_create(model_obj, n_ctx = n_ctx, n_threads = n_threads, verbosity = verbosity)
  
  # Cache the objects
  .quick_llama_env$model <- model_obj
  .quick_llama_env$context <- context_obj
  .quick_llama_env$cache_key <- cache_key
  
  .localllm_message("Model and context ready!")
}

#' Generate text for single prompt
#' @param prompt Single prompt string
#' @param max_tokens Maximum tokens
#' @param top_k Top-k sampling
#' @param top_p Top-p sampling
#' @param temperature Temperature
#' @param repeat_penalty Repetition penalty
#' @param seed Random seed
#' @param stream Whether to stream
#' @param ... Additional parameters
#' @return Generated text string
#' @noRd
.generate_single <- function(prompt, max_tokens, top_k, top_p, temperature, 
                             repeat_last_n, penalty_repeat, seed, stream, hash = FALSE, ...) {
  
  context <- .quick_llama_env$context
  # Generate text (auto-tokenization is now handled by generate())
  .localllm_message("Generating...")
  result <- generate(context, prompt,
                     max_tokens = max_tokens,
                     top_k = top_k,
                     top_p = top_p,
                     temperature = temperature,
                     repeat_last_n = repeat_last_n,
                     penalty_repeat = penalty_repeat,
                     seed = seed,
                     hash = hash)
  result
}

#' Generate text for multiple prompts
#' @param prompts Vector of prompt strings
#' @param max_tokens Maximum tokens
#' @param top_k Top-k sampling
#' @param top_p Top-p sampling
#' @param temperature Temperature
#' @param repeat_last_n Number of recent tokens for repetition penalty
#' @param penalty_repeat Repetition penalty strength
#' @param seed Random seed
#' @param stream Whether to stream
#' @param ... Additional parameters
#' @return Named list of generated texts
#' @noRd
.generate_multiple <- function(prompts, max_tokens, top_k, top_p, temperature, 
                               repeat_last_n, penalty_repeat, seed, stream, progress,
                               hash = FALSE, ...) {
  
  context <- .quick_llama_env$context
  
  .localllm_message("Generating ", length(prompts), " responses...")
  
  # Use parallel generation for better performance (streaming flag available for future use)
  results <- generate_parallel(context, prompts,
                               max_tokens = max_tokens,
                               top_k = top_k,
                               top_p = top_p,
                               temperature = temperature,
                               repeat_last_n = repeat_last_n,
                               penalty_repeat = penalty_repeat,
                               seed = seed,
                               progress = progress,
                               hash = hash)
  
  # Return as named list
  names(results) <- paste0("prompt_", seq_along(prompts))
  results
}

#' Check if backend is loaded
#' @return TRUE if backend is loaded, FALSE otherwise
#' @noRd
.is_backend_loaded <- function() {
  # Simply check if the backend library is installed
  # The actual loading will be handled by ensure_backend_loaded
  tryCatch({
    lib_is_installed()
  }, error = function(e) {
    FALSE
  })
}
