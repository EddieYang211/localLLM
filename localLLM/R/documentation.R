# --- FILE: localLLM/R/documentation.R ---

.localllm_doc_env <- new.env(parent = emptyenv())
.localllm_doc_env$active <- FALSE
.localllm_doc_env$entries <- list()
.localllm_doc_env$path <- NULL
.localllm_doc_env$append <- FALSE
.localllm_doc_env$start_time <- NULL

#' Start automatic run documentation
#'
#' Calling `document_start()` enables automatic logging for subsequent
#' `localLLM` calls. Information such as timestamps, models, and generation
#' settings are buffered in-memory until [document_end()] is invoked, at which
#' point a human-readable text report is written to disk.
#'
#' @param path Optional destination path for the log file. Defaults to
#'   `localLLM_run_<timestamp>.txt` in the current working directory.
#' @param metadata Optional named list of user-defined metadata to include in the
#'   log header (e.g. project name, dataset id).
#' @param append When `TRUE`, entries are appended to an existing file instead of
#'   overwriting it.
#' @return The path that will be written when [document_end()] is called.
#' @importFrom utils capture.output str
#' @export
document_start <- function(path = NULL, metadata = list(), append = FALSE) {
  if (isTRUE(.localllm_doc_env$active)) {
    stop("document_start() has already been called. Invoke document_end() before starting a new session.", call. = FALSE)
  }

  start_time <- Sys.time()
  if (is.null(path)) {
    path <- file.path(getwd(), sprintf("localLLM_run_%s.txt", format(start_time, "%Y%m%d_%H%M%S")))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  metadata <- .document_normalise_metadata(metadata)

  .localllm_doc_env$active <- TRUE
  .localllm_doc_env$path <- path
  .localllm_doc_env$append <- isTRUE(append)
  .localllm_doc_env$start_time <- start_time
  .localllm_doc_env$entries <- list()

  base_details <- c(.document_session_facts(), metadata)
  .document_record_event("document_start", base_details, timestamp = start_time)

  invisible(path)
}

#' Finish automatic run documentation
#'
#' Flushes the buffered log entries assembled since the matching
#' [document_start()] call and writes them to the configured text file.
#'
#' @return Invisibly returns the path that was written.
#' @export
document_end <- function() {
  if (!isTRUE(.localllm_doc_env$active)) {
    stop("document_start() has not been called.", call. = FALSE)
  }

  end_time <- Sys.time()
  entries <- .localllm_doc_env$entries
  duration <- as.numeric(difftime(end_time, .localllm_doc_env$start_time, units = "secs"))
  entries[[length(entries) + 1L]] <- list(
    type = "document_end",
    timestamp = end_time,
    details = list(duration_seconds = duration, total_events = length(entries))
  )

  lines <- .document_format_entries(entries, .localllm_doc_env$start_time, end_time, .localllm_doc_env$path)

  path <- .localllm_doc_env$path
  mode <- if (isTRUE(.localllm_doc_env$append) && file.exists(path)) "a" else "w"
  con <- file(path, open = mode, encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  if (mode == "a") {
    writeLines("", con)
    writeLines(strrep("=", 60), con)
  }
  writeLines(lines, con)

  message("localLLM run log written to: ", path)

  .localllm_doc_env$active <- FALSE
  .localllm_doc_env$entries <- list()
  .localllm_doc_env$path <- NULL
  .localllm_doc_env$start_time <- NULL

  invisible(path)
}

.document_record_event <- function(event, details = list(), timestamp = Sys.time()) {
  if (!isTRUE(.localllm_doc_env$active)) {
    return(invisible(FALSE))
  }

  entry <- list(
    type = event,
    timestamp = timestamp,
    details = details
  )

  .localllm_doc_env$entries[[length(.localllm_doc_env$entries) + 1L]] <- entry
  invisible(TRUE)
}

.document_format_entries <- function(entries, start_time, end_time, path) {
  tz <- Sys.timezone()
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

  header <- c(
    "localLLM Run Log",
    sprintf("File: %s", normalizePath(path, winslash = "/", mustWork = FALSE)),
    sprintf("Started: %s", format(start_time, tz = tz, usetz = TRUE)),
    sprintf("Ended: %s", format(end_time, tz = tz, usetz = TRUE)),
    sprintf("Duration: %.2f seconds", duration),
    "",
    "Events:"
  )

  event_lines <- unlist(lapply(entries, function(entry) {
    block <- c(sprintf("- [%s] %s", format(entry$timestamp, tz = tz, usetz = TRUE), entry$type))
    if (length(entry$details)) {
      detail_lines <- .document_format_details(entry$details)
      block <- c(block, paste0("    ", detail_lines))
    }
    c(block, "")
  }), use.names = FALSE)

  c(header, event_lines)
}

.document_format_details <- function(details) {
  tryCatch({
    json <- jsonlite::toJSON(details, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
    strsplit(json, "\n", fixed = TRUE)[[1]]
  }, error = function(e) {
    capture.output(str(details, give.attr = FALSE))
  })
}

.document_normalise_metadata <- function(metadata) {
  if (is.null(metadata)) {
    return(list())
  }
  if (!is.list(metadata)) {
    metadata <- as.list(metadata)
  }
  metadata
}

.document_session_facts <- function() {
  sys <- Sys.info()
  list(
    package_version = as.character(utils::packageVersion("localLLM")),
    r_version = as.character(getRversion()),
    platform = R.version$platform,
    os = sys[["sysname"]],
    release = sys[["release"]],
    user = sys[["user"]] %||% Sys.getenv("USER", unset = NA_character_),
    working_directory = getwd()
  )
}
