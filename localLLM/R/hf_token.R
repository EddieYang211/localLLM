# --- FILE: localLLM/R/hf_token.R ---

#' Configure Hugging Face access token
#'
#' Utility helper to manage the `HF_TOKEN` environment variable used for
#' authenticated downloads from Hugging Face. The token is set for the current
#' R session, and it can optionally be persisted to a `.Renviron` file for
#' future sessions. The token is not printed back to the console.
#'
#' @param token Character scalar. Your Hugging Face access token, typically
#'   starting with `hf_`.
#' @param persist Logical flag controlling whether to persist the token to a
#'   startup file. Defaults to `FALSE`.
#' @param renviron_path Optional path to the `.Renviron` file to update when
#'   `persist = TRUE`. Defaults to `"~/.Renviron"`.
#'
#' @return Invisibly returns the currently active token value.
#' @examples
#' \dontrun{
#' set_hf_token("hf_xxx")
#' }
#'
#' @export
set_hf_token <- function(token, persist = FALSE, renviron_path = "~/.Renviron") {
  if (missing(token) || is.null(token) || length(token) != 1L || !nzchar(token)) {
    stop("`token` must be a non-empty character scalar", call. = FALSE)
  }

  token <- as.character(token)

  # Update the session environment first
  Sys.setenv(HF_TOKEN = token)

  if (isTRUE(persist)) {
    renviron_path <- path.expand(renviron_path)
    lines <- character()
    if (file.exists(renviron_path)) {
      lines <- readLines(renviron_path, warn = FALSE)
      keep <- !grepl("^HF_TOKEN=", trimws(lines))
      lines <- lines[keep]
    }
    lines <- c(lines, sprintf("HF_TOKEN=%s", token))
    # Ensure directory exists
    dir.create(dirname(renviron_path), recursive = TRUE, showWarnings = FALSE)
    writeLines(lines, renviron_path)
  }

  invisible(Sys.getenv("HF_TOKEN", unset = ""))
}

#' Temporarily apply an HF token for a scoped operation
#'
#' This helper sets the `HF_TOKEN` environment variable for the duration of a
#' code block and restores the previous value afterwards.
#'
#' @param token Character scalar or NULL. When NULL, the current token (if any)
#'   is used. When non-NULL, the environment variable is temporarily set to this
#'   value.
#' @param expr Expression to evaluate within the temporary token context.
#' @keywords internal
.with_hf_token <- function(token, expr) {
  old <- Sys.getenv("HF_TOKEN", unset = NA_character_)
  on.exit({
    if (is.na(old)) {
      Sys.unsetenv("HF_TOKEN")
    } else {
      Sys.setenv(HF_TOKEN = old)
    }
  }, add = TRUE)

  if (!is.null(token)) {
    if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
      stop("`hf_token` must be a non-empty character scalar", call. = FALSE)
    }
    Sys.setenv(HF_TOKEN = token)
  }

  force(expr)
}
