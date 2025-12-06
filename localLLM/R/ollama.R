#' List GGUF models managed by Ollama
#'
#' This helper scans common Ollama installation directories for downloaded
#' GGUF weights that can be loaded directly by the `llama.cpp` backend.
#' It inspects both manifest metadata (when available) and the blobs directory
#' to return human-readable model descriptions.
#'
#' @param min_size_mb Minimum size (in megabytes) for a candidate GGUF file.
#'   Defaults to 50 MB to avoid tiny placeholder layers.
#' @param verify Whether to confirm the GGUF magic header before listing the
#'   model (default `TRUE`).
#' @return A data.frame with columns: `name`, `path`, `size_mb`, `size_gb`,
#'   `size_bytes`, `sha256`, `modified`, `source`, `tag`, `model`. Returns an
#'   empty data.frame if no models are found.
#' @export
list_ollama_models <- function(min_size_mb = 50, verify = TRUE) {
  stopifnot(is.numeric(min_size_mb), length(min_size_mb) == 1L, min_size_mb >= 0)
  stopifnot(is.logical(verify), length(verify) == 1L)

  min_size_override <- getOption('localllm.ollama_min_size_mb', default = min_size_mb)
  if (!is.null(min_size_override)) {
    candidate <- suppressWarnings(as.numeric(min_size_override)[1])
    if (!is.na(candidate)) {
      min_size_mb <- max(0, candidate)
    }
  }

  verify_override <- getOption('localllm.ollama_verify', default = verify)
  if (!is.null(verify_override) && !is.na(verify_override[1])) {
    verify <- isTRUE(verify_override[1])
  }

  roots <- .ollama_candidate_roots()
  roots <- roots[dir.exists(roots)]

  if (length(roots) == 0L) {
    .localllm_message("No Ollama installation directories found.")
    return(.empty_ollama_df())
  }

  discovered <- lapply(roots, function(root) {
    .scan_ollama_root(root, min_size_mb = min_size_mb, verify = verify)
  })

  models <- do.call(c, lapply(discovered, "[[", "models"))

  # Deduplicate models by path (same blob may be found in multiple roots)
  if (length(models) > 0L) {
    paths <- vapply(models, function(m) m$path, character(1))
    unique_indices <- !duplicated(paths)
    models <- models[unique_indices]
  }

  if (length(models) == 0L) {
    .localllm_message("No Ollama GGUF models found in: ", paste(roots, collapse = ", "))
    return(.empty_ollama_df())
  }

  # Convert list of models to data.frame
  .models_list_to_df(models)
}

.empty_ollama_df <- function() {
  data.frame(
    name = character(),
    path = character(),
    size_mb = numeric(),
    size_gb = numeric(),
    size_bytes = numeric(),
    sha256 = character(),
    modified = as.POSIXct(character()),
    source = character(),
    tag = character(),
    model = character(),
    stringsAsFactors = FALSE
  )
}

.models_list_to_df <- function(models) {
  data.frame(
    name = vapply(models, function(m) m$name, character(1)),
    path = vapply(models, function(m) m$path, character(1)),
    size_mb = vapply(models, function(m) m$size_mb, numeric(1)),
    size_gb = vapply(models, function(m) m$size_gb, numeric(1)),
    size_bytes = vapply(models, function(m) m$size_bytes, numeric(1)),
    sha256 = vapply(models, function(m) m$sha256, character(1)),
    modified = do.call(c, lapply(models, function(m) m$modified)),
    source = vapply(models, function(m) m$source, character(1)),
    tag = vapply(models, function(m) {
      if (is.null(m$tag) || is.na(m$tag)) "" else as.character(m$tag)
    }, character(1)),
    model = vapply(models, function(m) {
      if (is.null(m$model) || is.na(m$model)) "" else as.character(m$model)
    }, character(1)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

.ollama_candidate_roots <- function() {
  roots <- character()

  env_root <- Sys.getenv("OLLAMA_MODELS", unset = NA_character_)
  if (!is.na(env_root) && nzchar(env_root)) {
    roots <- c(roots, path.expand(env_root))
  }

  home <- path.expand("~")
  roots <- c(
    roots,
    file.path(home, ".ollama", "models"),
    file.path(home, ".ollama", "models", "blobs"),
    file.path(home, "Library", "Application Support", "Ollama", "models"),
    file.path(home, "Library", "Application Support", "Ollama", "models", "blobs")
  )

  if (.Platform$OS.type == "windows") {
    userprofile <- Sys.getenv("USERPROFILE", unset = NA_character_)
    if (!is.na(userprofile) && nzchar(userprofile)) {
      roots <- c(roots, file.path(userprofile, ".ollama", "models"))
    }
  } else {
    roots <- c(
      roots,
      "/var/snap/ollama/common/models",
      "/usr/share/ollama/models"
    )
  }

  unique(normalizePath(roots, winslash = "/", mustWork = FALSE))
}

.scan_ollama_root <- function(root, min_size_mb, verify) {
  manifest_dir <- file.path(root, "manifests")
  blob_root <- if (basename(root) == "blobs") root else file.path(root, "blobs")

  manifest_map <- list()
  if (dir.exists(manifest_dir)) {
    manifest_map <- .read_ollama_manifests(manifest_dir)
  }

  blob_candidates <- character()
  if (dir.exists(blob_root)) {
    blob_candidates <- .safe_list(blob_root, pattern = "^sha256-", full.names = TRUE)
  }

  if (length(blob_candidates) == 0L && dir.exists(root)) {
    blob_candidates <- .safe_list(root, pattern = "^sha256-", full.names = TRUE)
  }

  if (length(blob_candidates) == 0L) {
    return(list(models = list(), total_candidates = 0L))
  }

  min_size_bytes <- min_size_mb * 1024 * 1024
  models <- list()

  for (candidate in blob_candidates) {
    info <- suppressWarnings(file.info(candidate))
    if (!nrow(info) || is.na(info$size) || info$size < min_size_bytes) {
      next
    }

    sha <- sub("^sha256-", "", basename(candidate))
    manifest_entry <- manifest_map[[sha]]

    if (verify && !.is_valid_gguf_file(candidate)) {
      next
    }

    display_name <- if (!is.null(manifest_entry)) manifest_entry$name else .fallback_ollama_name(info$size, sha)

    models[[length(models) + 1L]] <- list(
      name = display_name,
      path = candidate,
      size_mb = round(info$size / 1024 / 1024, 1),
      size_gb = round(info$size / 1024 / 1024 / 1024, 2),
      size_bytes = info$size,
      sha256 = sha,
      modified = info$mtime,
      source = "ollama",
      root = root,
      tag = if (!is.null(manifest_entry)) manifest_entry$tag else NA_character_,
      model = if (!is.null(manifest_entry)) manifest_entry$model else NA_character_
    )
  }

  list(models = models, total_candidates = length(blob_candidates))
}

.read_ollama_manifests <- function(manifest_dir) {
  files <- .safe_list(manifest_dir, recursive = TRUE, full.names = TRUE)
  if (length(files) == 0L) {
    return(list())
  }

  mapping <- new.env(parent = emptyenv())

  for (manifest_path in files) {
    manifest <- .parse_ollama_manifest(manifest_path)
    if (is.null(manifest)) {
      next
    }

    for (entry in manifest$layers) {
      if (!isTRUE(entry$is_model)) {
        next
      }
      sha <- entry$sha256
      if (nzchar(sha) && !exists(sha, envir = mapping, inherits = FALSE)) {
        assign(sha, list(
          name = manifest$name,
          model = manifest$model,
          tag = manifest$tag
        ), envir = mapping)
      }
    }
  }

  as.list(mapping)
}

.parse_ollama_manifest <- function(path) {
  contents <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
  if (is.null(contents) || length(contents) == 0L) {
    return(NULL)
  }

  json <- tryCatch(jsonlite::fromJSON(paste(contents, collapse = "\n")), error = function(e) NULL)
  if (is.null(json) || is.null(json$layers)) {
    return(NULL)
  }

  layers <- json$layers
  digests <- vapply(layers$digest, function(x) sub("^sha256:", "", x %||% ""), character(1))
  media <- layers$mediaType

  model_layers <- Map(function(digest, media_type) {
    if (!nzchar(digest)) {
      return(NULL)
    }
    list(
      sha256 = digest,
      media_type = media_type %||% "",
      is_model = grepl("model", media_type %||% "", fixed = TRUE)
    )
  }, digests, media)

  model_layers <- Filter(Negate(is.null), model_layers)
  if (length(model_layers) == 0L) {
    return(NULL)
  }

  parent_dir <- dirname(path)
  tag <- basename(path)
  model <- basename(parent_dir)

  list(
    model = model,
    tag = tag,
    name = if (identical(tag, "latest")) model else sprintf("%s:%s", model, tag),
    layers = model_layers
  )
}

.fallback_ollama_name <- function(size_bytes, sha) {
  size_mb <- round(size_bytes / 1024 / 1024, 1)
  sprintf("ollama_%smb_%s", format(size_mb, trim = TRUE, scientific = FALSE), substr(sha, 1, 8))
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

.match_ollama_reference <- function(models, query) {
  if (length(models) == 0L) {
    return(list())
  }

  q <- tolower(query)
  keep <- vapply(models, function(model) {
    name <- tolower(model$name %||% "")
    sha <- tolower(model$sha256 %||% "")
    base <- tolower(basename(model$path %||% ""))
    startsWith(name, q) || startsWith(sha, q) || identical(q, name) ||
      identical(q, sha) || identical(q, base)
  }, logical(1))

  models[keep]
}

.match_ollama_reference_df <- function(models_df, query) {
  if (nrow(models_df) == 0L) {
    return(integer())
  }

  q <- tolower(query)
  keep <- vapply(seq_len(nrow(models_df)), function(i) {
    name <- tolower(models_df$name[i])
    sha <- tolower(models_df$sha256[i])
    base <- tolower(basename(models_df$path[i]))
    startsWith(name, q) || startsWith(sha, q) || identical(q, name) ||
      identical(q, sha) || identical(q, base)
  }, logical(1))

  which(keep)
}

.select_ollama_model <- function(models, context = "Ollama") {
  if (length(models) == 0L) {
    return(NULL)
  }

  ordered <- models[order(vapply(models, function(x) x$size_bytes,
                                 numeric(1), USE.NAMES = FALSE),
                          decreasing = TRUE)]

  for (idx in seq_along(ordered)) {
    .localllm_message(sprintf("[%d] %s (%.1f MB) - %s", idx, ordered[[idx]]$name,
                    ordered[[idx]]$size_mb, ordered[[idx]]$path))
  }

  selection_option <- getOption("localllm.cache_selection", default = NULL)
  if (!is.null(selection_option)) {
    idx <- suppressWarnings(as.integer(selection_option))
    if (!is.na(idx) && idx >= 1 && idx <= length(ordered)) {
      .localllm_message("Selected ", context, " model via option ",
              "localllm.cache_selection = ", idx)
      return(ordered[[idx]])
    }
    warning("Ignoring invalid localllm.cache_selection option; ",
            "falling back to interactive prompt.")
  }

  if (!interactive()) {
    stop(
      sprintf(
        "Multiple %s models matched. Use list_ollama_models() to inspect ",
        "options and provide a more specific reference.",
        tolower(context)
      ),
      call. = FALSE
    )
  }

  repeat {
    answer <- readline(sprintf("Enter the number of the %s model to use ",
                               "(press Enter to cancel): ", tolower(context)))
    if (identical(answer, "")) {
      .localllm_message("Selection cancelled. Provide a more specific model name or ",
              "sha256 prefix.")
      return(NULL)
    }
    idx <- suppressWarnings(as.integer(answer))
    if (!is.na(idx) && idx >= 1 && idx <= length(ordered)) {
      return(ordered[[idx]])
    }
    .localllm_message(sprintf("Invalid selection. Please enter a number between 1 ",
                    "and %d.", length(ordered)))
  }
}

.select_ollama_model_df <- function(models_df, context = "Ollama") {
  if (nrow(models_df) == 0L) {
    return(NULL)
  }

  ordered_idx <- order(models_df$size_bytes, decreasing = TRUE)
  ordered <- models_df[ordered_idx, , drop = FALSE]

  for (i in seq_len(nrow(ordered))) {
    .localllm_message(sprintf("[%d] %s (%.1f MB) - %s", i, ordered$name[i],
                    ordered$size_mb[i], ordered$path[i]))
  }

  selection_option <- getOption("localllm.cache_selection", default = NULL)
  if (!is.null(selection_option)) {
    idx <- suppressWarnings(as.integer(selection_option))
    if (!is.na(idx) && idx >= 1 && idx <= nrow(ordered)) {
      .localllm_message("Selected ", context, " model via option ",
              "localllm.cache_selection = ", idx)
      return(ordered_idx[idx])
    }
    warning("Ignoring invalid localllm.cache_selection option; ",
            "falling back to interactive prompt.")
  }

  if (!interactive()) {
    stop(
      sprintf(
        "Multiple %s models matched. Use list_ollama_models() to inspect ",
        "options and provide a more specific reference.",
        tolower(context)
      ),
      call. = FALSE
    )
  }

  repeat {
    answer <- readline(sprintf("Enter the number of the %s model to use ",
                               "(press Enter to cancel): ", tolower(context)))
    if (identical(answer, "")) {
      .localllm_message("Selection cancelled. Provide a more specific model name or ",
              "sha256 prefix.")
      return(NULL)
    }
    idx <- suppressWarnings(as.integer(answer))
    if (!is.na(idx) && idx >= 1 && idx <= nrow(ordered)) {
      return(ordered_idx[idx])
    }
    .localllm_message(sprintf("Invalid selection. Please enter a number between 1 ",
                    "and %d.", nrow(ordered)))
  }
}

.safe_list <- function(...) {
  tryCatch(list.files(...), warning = function(w) character(), error = function(e) character())
}

.is_ollama_reference <- function(x) {
  if (!is.character(x) || length(x) != 1L) {
    return(FALSE)
  }
  lx <- tolower(trimws(x))
  identical(lx, "ollama") || startsWith(lx, "ollama:")
}
