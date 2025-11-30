# --- FILE: localLLM/R/hash_utils.R ---

# Internal helpers for computing deterministic SHA-256 hashes of
# generation inputs/outputs. Hashes intentionally focus on user-controlled
# payloads so they remain comparable across machines.

.hash_payload <- function(payload) {
  json <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null",
                           digits = NA, force = TRUE)
  digest::digest(json, algo = "sha256")
}

.hash_model_identifier <- function(model) {
  value <- NULL
  if (!is.null(model)) {
    value <- attr(model, "model_identifier")
    if (is.null(value)) {
      value <- attr(model, "model_path")
    }
  }
  if (is.null(value) || length(value) == 0) {
    return(NA_character_)
  }
  as.character(value[[1]])
}

.hash_normalise_model_source <- function(source, fallback = NA_character_) {
  if (is.null(source) || length(source) == 0) {
    return(fallback)
  }
  ref <- trimws(as.character(source[[1]]))
  if (!nzchar(ref)) {
    return(fallback)
  }
  if (grepl("^ollama", ref, ignore.case = TRUE)) {
    return(tolower(ref))
  }
  if (grepl("^https?://", ref, ignore.case = TRUE)) {
    return(ref)
  }
  basename(ref)
}

.hash_attach_metadata <- function(result, input_hash, output_hash, event) {
  attr(result, "hashes") <- list(input = input_hash, output = output_hash)
  message(sprintf("%s input hash: %s | output hash: %s",
                  event, input_hash, output_hash))
  .document_record_event(paste0(event, "_hash"), list(
    input_hash = input_hash,
    output_hash = output_hash
  ))
  result
}
