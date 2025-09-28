#' Apply Gemma-Compatible Chat Template
#'
#' Creates a properly formatted chat template for Gemma models, which use
#' <start_of_turn> and <end_of_turn> markers instead of ChatML format.
#' This function addresses compatibility issues with apply_chat_template()
#' when used with Gemma models.
#'
#' @param messages A list of message objects, each with 'role' and 'content' fields
#' @param add_assistant Whether to add the assistant turn prefix (default: TRUE)
#' @return A character string with properly formatted Gemma chat template
#' @export
#'
#' @examples
#' \dontrun{
#' messages <- list(
#'   list(role = "system", content = "You are a helpful assistant."),
#'   list(role = "user", content = "Hello!")
#' )
#' formatted <- apply_gemma_chat_template(messages)
#' }
apply_gemma_chat_template <- function(messages, add_assistant = TRUE) {
  if (!is.list(messages) || length(messages) == 0) {
    stop("messages must be a non-empty list", call. = FALSE)
  }
  
  # Gemma format construction
  result <- ""
  system_prompt <- ""
  
  # Step 1: Extract system prompt (Gemma has no independent system role)
  user_messages <- list()
  for (msg in messages) {
    if (!is.list(msg) || is.null(msg$role) || is.null(msg$content)) {
      stop("Each message must have 'role' and 'content' fields", call. = FALSE)
    }
    
    if (msg$role == "system") {
      system_prompt <- trimws(msg$content)
    } else {
      user_messages <- append(user_messages, list(msg))
    }
  }
  
  # Step 2: Construct Gemma format dialogue
  for (i in seq_along(user_messages)) {
    msg <- user_messages[[i]]
    role <- msg$role
    content <- trimws(msg$content)
    
    if (role == "user") {
      # For the first user message, merge system prompt
      if (i == 1 && nzchar(system_prompt)) {
        combined_content <- paste0(system_prompt, "\n\n", content)
      } else {
        combined_content <- content
      }
      
      result <- paste0(result, "<start_of_turn>user\n", combined_content, "<end_of_turn>\n")
      
    } else if (role == "assistant") {
      result <- paste0(result, "<start_of_turn>model\n", content, "<end_of_turn>\n")
    }
  }
  
  # Step 3: Add assistant start marker
  if (add_assistant) {
    result <- paste0(result, "<start_of_turn>model\n")
  }
  
  return(result)
}

#' Smart Chat Template Application
#'
#' Automatically detects the model type and applies the appropriate chat template.
#' For Gemma models, uses the Gemma-specific format. For other models, 
#' falls back to the standard apply_chat_template function.
#'
#' @param model A model object created with model_load
#' @param messages A list of message objects
#' @param template Custom template (passed to apply_chat_template if not Gemma)
#' @param add_assistant Whether to add assistant turn prefix
#' @return Formatted chat template string
#' @export
smart_chat_template <- function(model, messages, template = NULL, add_assistant = TRUE) {
  .ensure_backend_loaded()
  if (!inherits(model, "localllm_model")) {
    stop("Expected a localllm_model object", call. = FALSE)
  }
  
  # Try to detect if it's a Gemma model (through model attributes or heuristic methods)
  # Here we use a simple heuristic: if the standard chat template contains ChatML markers,
  # we consider that Gemma format might be needed
  test_messages <- list(list(role = "user", content = "test"))
  
  tryCatch({
    standard_output <- apply_chat_template(model, test_messages, template, add_assistant)
    
    # If it contains ChatML markers, it might be a format mismatch
    if (grepl("<\\|im_start\\||<\\|im_end\\|", standard_output)) {
      # Use Gemma format
      return(apply_gemma_chat_template(messages, add_assistant))
    } else {
      # Use standard format
      return(apply_chat_template(model, messages, template, add_assistant))
    }
  }, error = function(e) {
    # If standard method fails, try Gemma format
    return(apply_gemma_chat_template(messages, add_assistant))
  })
}
