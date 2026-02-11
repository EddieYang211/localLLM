# --- FILE: localLLM/R/annotations.R ---

#' Compare multiple LLMs over a shared set of prompts
#'
#' `explore()` orchestrates running several models over the same prompts,
#' captures their predictions, and returns both long and wide annotation
#' tables that can be fed into confusion-matrix and reliability helpers.
#'
#' @param models Model definitions. Accepts one of the following formats:
#'   \itemize{
#'     \item A single model path string (consistent with [model_load()] syntax)
#'     \item A named character vector where names become `model_id`s
#'     \item A list of model specification lists
#'   }
#'
#'   Each model specification list supports the following keys:
#'   \describe{
#'     \item{id}{(Required unless auto-generated) Unique identifier for this model}
#'     \item{model_path}{(Required unless using `predictor`) Path to local GGUF file,
#'       URL, or cached model name. Supports the same formats as [model_load()]}
#'     \item{n_gpu_layers}{Number of layers to offload to GPU. Use `"auto"` (default)
#'       for automatic detection, `0` for CPU-only, or `-1` for all layers on GPU}
#'     \item{n_ctx}{Context window size (default: 2048)}
#'     \item{n_threads}{Number of CPU threads (default: auto-detected)}
#'     \item{cache_dir}{Custom cache directory for model downloads}
#'     \item{use_mmap}{Enable memory mapping (default: TRUE)}
#'     \item{use_mlock}{Lock model in memory (default: FALSE)}
#'     \item{check_memory}{Check memory availability before loading (default: TRUE)}
#'     \item{force_redownload}{Force re-download even if cached (default: FALSE)}
#'     \item{verify_integrity}{Verify file integrity (default: TRUE)}
#'     \item{hf_token}{Hugging Face access token for gated models. Can also be set
#'       globally via [set_hf_token()]}
#'     \item{verbosity}{Backend logging level (default: 1)}
#'     \item{chat_template}{Override the global `chat_template` setting for this model}
#'     \item{system_prompt}{Override the global `system_prompt` for this model}
#'     \item{instruction}{Task instruction to use for this model}
#'     \item{generation}{List of generation parameters (max_tokens, temperature, etc.)}
#'     \item{prompts}{Custom prompts for this model}
#'     \item{predictor}{Function for mock/testing scenarios (bypasses model loading)}
#'   }
#' @param instruction Default task instruction inserted into `spec` whenever a
#'   model entry does not override it.
#' @param prompts One of: (1) a function (for example `function(spec)`)
#'   that returns prompts (character vector or a data frame with a `prompt` column);
#'   (2) a character vector of ready-made prompts; or (3) a template list where
#'   each named element becomes a section in the rendered prompt. Field names are
#'   used as-is for headers. Vector fields matching `sample_id` length are treated
#'   as per-item values. Use `sample_id` to specify item IDs (meta, not rendered).
#'   When `NULL`, each model must provide its own `prompts` entry.
#' @param engine One of `"auto"`, `"parallel"`, or `"single"`. Controls whether
#'   `generate_parallel()` or `generate()` is used under the hood.
#' @param batch_size Number of prompts to send per backend call when the
#'   parallel engine is active. Must be >= 1.
#' @param reuse_models If `TRUE`, model/context handles stay alive for the
#'   duration of the function (useful when exploring lots of prompts). When
#'   `FALSE` (default) handles are released after each model to minimise peak
#'   memory usage.
#' @param sink Optional function that accepts `(chunk, model_id)` and is invoked
#'   after each model finishes. This makes it easy to stream intermediate
#'   results to disk via helpers such as [annotation_sink_csv()].
#' @param progress Whether to print progress messages for each model/batch.
#' @param clean Forwarded to `generate()`/`generate_parallel()` to remove control
#'   tokens from the outputs.
#' @param keep_prompts If `TRUE`, the generated prompts are preserved in the
#'   long-format output (useful for audits). Defaults to `FALSE`.
#' @param hash When `TRUE` (default), computes SHA-256 hashes for each model's prompts and
#'   resulting labels so replication collaborators can verify inputs and
#'   outputs. Hashes are attached to the returned list via the `"hashes"`
#'   attribute.
#' @param chat_template When `TRUE`, wraps prompts using the model's built-in chat
#'   template before generation. This uses [apply_chat_template()] to format
#'   prompts with appropriate special tokens for instruction-tuned models.
#'   Individual models can override this via their spec. Default: `TRUE`.
#' @param system_prompt Optional system message to include when `chat_template = TRUE`.
#'   This is prepended as a system role message before the user prompt. Individual
#'   models can override this via their spec. Default: `NULL`.
#' @return A list with elements `annotations` (long table) and `matrix` (wide
#'   annotation matrix). When `sink` is supplied the `annotations` and `matrix`
#'   entries are set to `NULL` to avoid duplicating the streamed output.
#' @export
explore <- function(models,
                    instruction = NULL,
                    prompts = NULL,
                    engine = c("auto", "parallel", "single"),
                    batch_size = 8L,
                    reuse_models = FALSE,
                    sink = NULL,
                    progress = interactive(),
                    clean = TRUE,
                    keep_prompts = FALSE,
                    hash = TRUE,
                    chat_template = TRUE,
                    system_prompt = NULL) {
  # Validate engine parameter
  engine <- match.arg(engine)

  # Validate batch_size
  batch_size <- as.integer(batch_size)
  if (is.na(batch_size) || batch_size < 1L) {
    stop("batch_size must be a positive integer >= 1", call. = FALSE)
  }

  # Validate models is provided and not empty
  if (missing(models) || is.null(models) || length(models) == 0L) {
    stop("models must not be empty", call. = FALSE)
  }

  # Validate boolean parameters
 if (!is.logical(reuse_models) || length(reuse_models) != 1L || is.na(reuse_models)) {
    stop("reuse_models must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.logical(progress) || length(progress) != 1L || is.na(progress)) {
    stop("progress must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.logical(clean) || length(clean) != 1L || is.na(clean)) {
    stop("clean must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.logical(keep_prompts) || length(keep_prompts) != 1L || is.na(keep_prompts)) {
    stop("keep_prompts must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.logical(hash) || length(hash) != 1L || is.na(hash)) {
    stop("hash must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.logical(chat_template) || length(chat_template) != 1L || is.na(chat_template)) {
    stop("chat_template must be TRUE or FALSE", call. = FALSE)
  }

  # Validate instruction (optional, but if provided must be character)
  if (!is.null(instruction) && (!is.character(instruction) || length(instruction) != 1L)) {
    stop("instruction must be a single character string or NULL", call. = FALSE)
  }
  if (!is.null(system_prompt) && (!is.character(system_prompt) || length(system_prompt) != 1L)) {
    stop("system_prompt must be a single character string or NULL", call. = FALSE)
  }

  sink <- .validate_sink(sink)
  specs <- .normalise_model_specs(models, instruction, chat_template, system_prompt)

  # Only load backend if at least one model needs it (i.e., doesn't use predictor)
  needs_backend <- any(vapply(specs, function(s) !is.function(s$predictor), logical(1)))
  if (needs_backend) {
    .ensure_backend_loaded()
  }

  spec_summaries <- lapply(specs, .explore_spec_summary)
  .document_record_event("explore_start", list(
    total_models = length(specs),
    engine = engine,
    batch_size = batch_size,
    reuse_models = reuse_models,
    sink = !is.null(sink),
    model_summaries = spec_summaries
  ))

  collected <- list()
  hash_records <- list()
  model_cache <- if (reuse_models) new.env(parent = emptyenv()) else NULL

  for (spec in specs) {
    builder <- .resolve_prompts_source(spec$prompts %||% prompts, spec)
    if (is.null(builder)) {
      stop(sprintf("Model '%s' is missing a prompt builder", spec$id), call. = FALSE)
    }

    prompt_data <- builder(spec)
    prompt_frame <- .coerce_prompt_frame(prompt_data)
    prompt_values <- prompt_frame$prompt

    run_info <- .run_model_over_data(prompts = prompt_values,
                                     spec = spec,
                                     engine = engine,
                                     batch_size = batch_size,
                                     reuse_models = reuse_models,
                                     model_cache = model_cache,
                                     progress = progress,
                                     clean = clean,
                                     hash = hash)

    chunk <- data.frame(
      sample_id = prompt_frame$sample_id,
      model_id = spec$id,
      label = run_info$output,
      stringsAsFactors = FALSE
    )

    if (!is.null(prompt_frame$truth)) {
      chunk$truth <- prompt_frame$truth
    }

    if (keep_prompts) {
      chunk$prompt <- prompt_values
    }

    if (is.null(sink)) {
      collected[[length(collected) + 1L]] <- chunk
    } else {
      sink(chunk, spec$id)
    }

    if (isTRUE(hash)) {
      hash_records[[length(hash_records) + 1L]] <- list(
        model_id = spec$id,
        input_hash = run_info$input_hash,
        output_hash = run_info$output_hash
      )
      .document_record_event("explore_model_hash", list(
        model_id = spec$id,
        input_hash = run_info$input_hash,
        output_hash = run_info$output_hash
      ))
    }

    .document_record_event("explore_model", list(
      model_id = spec$id,
      prompt_count = length(prompt_values),
      engine = engine,
      batch_size = batch_size,
      reuse_models = reuse_models,
      sink = !is.null(sink),
      has_predictor = isTRUE(is.function(spec$predictor)),
      generation = .explore_generation_summary(spec$generation)
    ))
  }

  annotations <- if (is.null(sink)) do.call(rbind, collected) else NULL
  matrix_view <- if (!is.null(annotations)) .wide_annotation_matrix(annotations) else NULL

  total_annotations <- if (is.null(annotations)) 0L else nrow(annotations)
  .document_record_event("explore_complete", list(
    total_models = length(specs),
    annotations = total_annotations,
    sink = !is.null(sink)
  ))

  result <- list(
    annotations = annotations,
    matrix = matrix_view
  )

  if (isTRUE(hash) && length(hash_records)) {
    hash_df <- do.call(rbind, lapply(hash_records, function(x) {
      data.frame(x, stringsAsFactors = FALSE)
    }))
    rownames(hash_df) <- NULL
    attr(result, "hashes") <- hash_df
    .document_record_event("explore_hash_summary", list(records = hash_df))
  }

  result
}

#' Compute confusion matrices from multi-model annotations
#'
#' @param annotations Output from [explore()] or a compatible data
#'   frame with at least `sample_id`, `model_id`, and `label` columns.
#' @param gold Optional vector of gold labels. Overrides the `truth` column when
#'   supplied.
#' @param pairwise When `TRUE`, cross-model confusion tables are returned even
#'   if no gold labels exist.
#' @param label_levels Optional factor levels to enforce a consistent ordering
#'   in the resulting tables.
#' @param sample_col,model_col,label_col,truth_col Column names to use when
#'   `annotations` is a custom data frame.
#' @return A list with elements `vs_gold` (named list of matrices, one per
#'   model) and `pairwise` (list of pairwise confusion tables).
#' @export
compute_confusion_matrices <- function(annotations,
                                       gold = NULL,
                                       pairwise = TRUE,
                                       label_levels = NULL,
                                       sample_col = "sample_id",
                                       model_col = "model_id",
                                       label_col = "label",
                                       truth_col = "truth") {
  ann_df <- .as_annotation_df(annotations, sample_col, model_col, label_col, truth_col)
  label_levels <- label_levels %||% .infer_levels(ann_df[[label_col]], gold, ann_df[[truth_col]])

  truth_map <- .truth_column(ann_df, gold, sample_col, truth_col)

  result <- list(vs_gold = NULL, pairwise = NULL)

  if (!is.null(truth_map)) {
    per_model <- split(ann_df, ann_df[[model_col]])
    result$vs_gold <- lapply(per_model, function(df) {
      truth <- truth_map[match(df[[sample_col]], names(truth_map))]
      table(factor(df[[label_col]], levels = label_levels),
            factor(truth, levels = label_levels))
    })
  }

  if (isTRUE(pairwise)) {
    model_ids <- unique(ann_df[[model_col]])
    if (length(model_ids) >= 2L) {
      combos <- utils::combn(model_ids, 2L, simplify = FALSE)
      result$pairwise <- lapply(combos, function(pair_ids) {
        sub <- ann_df[ann_df[[model_col]] %in% pair_ids, , drop = FALSE]
        tab <- stats::reshape(sub[, c(sample_col, model_col, label_col)],
                       idvar = sample_col,
                       timevar = model_col,
                       direction = "wide")
        colnames(tab) <- sub("^label\\.", "", colnames(tab))
        table(factor(tab[[pair_ids[1]]], levels = label_levels),
              factor(tab[[pair_ids[2]]], levels = label_levels))
      })
      names(result$pairwise) <- vapply(combos, function(x) paste(x, collapse = " vs "), character(1), USE.NAMES = FALSE)
    }
  }

  result
}

#' Intercoder reliability for LLM annotations
#'
#' @inheritParams compute_confusion_matrices
#' @param method One of `"auto"`, `"cohen"`, or `"krippendorff"`. The `"auto"`
#'   setting computes both pairwise Cohen's Kappa and Krippendorff's Alpha (when
#'   applicable).
#' @param sample_col Column name that identifies samples when `annotations` is a
#'   user-provided data frame.
#' @param model_col Column name for the model identifier when using a custom
#'   `annotations` data frame.
#' @param label_col Column name containing model predictions when using a custom
#'   `annotations` data frame.
#' @return A list containing `cohen` (data frame of pairwise kappas) and/or
#'   `krippendorff` (overall alpha statistic with per-item agreement scores).
#' @export
intercoder_reliability <- function(annotations,
                                   method = c("auto", "cohen", "krippendorff"),
                                   label_levels = NULL,
                                   sample_col = "sample_id",
                                   model_col = "model_id",
                                   label_col = "label") {
  method <- match.arg(method)
  ann_df <- .as_annotation_df(annotations, sample_col, model_col, label_col, truth_col = NULL)
  label_levels <- label_levels %||% .infer_levels(ann_df[[label_col]])

  out <- list()
  need_cohen <- method %in% c("auto", "cohen")
  need_krippendorff <- method %in% c("auto", "krippendorff")

  if (need_cohen) {
    model_ids <- unique(ann_df[[model_col]])
    if (length(model_ids) >= 2L) {
      combos <- utils::combn(model_ids, 2L, simplify = FALSE)
      cohen_list <- lapply(combos, function(pair_ids) {
        tab <- stats::reshape(ann_df[ann_df[[model_col]] %in% pair_ids, c(sample_col, model_col, label_col)],
                       idvar = sample_col,
                       timevar = model_col,
                       direction = "wide")
        # Fix column name extraction: handle custom label_col properly
        colnames(tab) <- sub(paste0("^", label_col, "\\."), "", colnames(tab))
        stats <- .cohen_kappa(tab[[pair_ids[1]]], tab[[pair_ids[2]]], label_levels)
        # Return as data frame to preserve types (character for IDs, numeric for stats)
        data.frame(
          model_a = pair_ids[1],
          model_b = pair_ids[2],
          kappa = stats$kappa,
          observed = stats$observed,
          expected = stats$expected,
          stringsAsFactors = FALSE
        )
      })
      out$cohen <- do.call(rbind, cohen_list)
      rownames(out$cohen) <- NULL
    }
  }

  if (need_krippendorff) {
    kripp <- .krippendorff_alpha(ann_df, label_levels, sample_col, model_col, label_col)
    out$krippendorff <- kripp
  }

  out
}

#' Validate model predictions against gold labels and peer agreement
#'
#' `validate()` is a convenience wrapper that runs both
#' [compute_confusion_matrices()] and [intercoder_reliability()] so that a
#' single call yields per-model confusion matrices (vs gold labels and
#' pairwise) as well as Cohen's Kappa / Krippendorff's Alpha scores.
#'
#' @inheritParams compute_confusion_matrices
#' @inheritParams intercoder_reliability
#' @param include_confusion When `TRUE` (default) the confusion matrices section
#'   is included in the output.
#' @param include_reliability When `TRUE` (default) the intercoder reliability
#'   section is included in the output.
#' @return A list containing up to two elements: `confusion` (the full result of
#'   [compute_confusion_matrices()]) and `reliability` (the result of
#'   [intercoder_reliability()]). Elements are omitted when the corresponding
#'   `include_*` argument is `FALSE`.
#' @export
#' @examples
#' annotations <- data.frame(
#'   sample_id = rep(1:3, times = 2),
#'   model_id = rep(c("llama", "qwen"), each = 3),
#'   label = c("pos", "neg", "pos", "pos", "neg", "neg"),
#'   truth = c("pos", "neg", "pos", "pos", "pos", "neg"),
#'   stringsAsFactors = FALSE
#' )
#'
#' result <- validate(annotations)
#' names(result)
validate <- function(annotations,
                     gold = NULL,
                     pairwise = TRUE,
                     label_levels = NULL,
                     sample_col = "sample_id",
                     model_col = "model_id",
                     label_col = "label",
                     truth_col = "truth",
                     method = c("auto", "cohen", "krippendorff"),
                     include_confusion = TRUE,
                     include_reliability = TRUE) {
  method <- match.arg(method)

  if (length(unique(annotations[[label_col]])) > 5) {
    warning("The number of unique labels/categories is greater than 5 Check if there are problems with the labels.")
  }

  if (!isTRUE(include_confusion) && !isTRUE(include_reliability)) {
    stop("At least one of include_confusion/include_reliability must be TRUE", call. = FALSE)
  }

  output <- list()

  if (isTRUE(include_confusion)) {
    output$confusion <- compute_confusion_matrices(
      annotations = annotations,
      gold = gold,
      pairwise = pairwise,
      label_levels = label_levels,
      sample_col = sample_col,
      model_col = model_col,
      label_col = label_col,
      truth_col = truth_col
    )
  }

  if (isTRUE(include_reliability)) {
    output$reliability <- intercoder_reliability(
      annotations = annotations,
      method = method,
      label_levels = label_levels,
      sample_col = sample_col,
      model_col = model_col,
      label_col = label_col
    )
  }

  output
}

#' Create a CSV sink for streaming annotation chunks
#'
#' The returned closure can be passed to `explore(sink = ...)` to
#' append each per-model chunk to a CSV file without holding everything in
#' memory.
#'
#' @param path Destination CSV path.
#' @param append If `TRUE`, new chunks are appended to an existing file.
#' @return A function with signature `(chunk, model_id)`.
#' @export
annotation_sink_csv <- function(path, append = FALSE) {
  wrote_header <- append && file.exists(path)

  function(chunk, model_id) {
    if (!is.data.frame(chunk)) {
      stop("Chunk passed to sink must be a data frame", call. = FALSE)
    }
    utils::write.table(chunk,
                       file = path,
                       sep = ",",
                       row.names = FALSE,
                       col.names = !wrote_header,
                       append = wrote_header)
    wrote_header <<- TRUE
    invisible(model_id)
  }
}

# --- Internal helpers ---

.coerce_prompt_frame <- function(builder_output) {
  if (is.null(builder_output)) {
    stop("prompts input must return at least one prompt", call. = FALSE)
  }

  if (is.character(builder_output)) {
    prompts <- builder_output
    sample_id <- seq_along(prompts)
    truth <- NULL
  } else if (is.data.frame(builder_output)) {
    if (!"prompt" %in% names(builder_output)) {
      stop("prompts data frame output must contain a 'prompt' column", call. = FALSE)
    }
    prompts <- as.character(builder_output$prompt)
    sample_id <- if ("sample_id" %in% names(builder_output)) builder_output$sample_id else seq_along(prompts)
    truth <- if ("truth" %in% names(builder_output)) builder_output$truth else NULL
  } else if (is.list(builder_output)) {
    prompts <- builder_output$prompt %||% builder_output$prompts
    if (is.null(prompts)) {
      stop("prompts list output must include 'prompt' or 'prompts'", call. = FALSE)
    }
    sample_id <- builder_output$sample_id %||% seq_along(prompts)
    truth <- builder_output$truth %||% NULL
  } else {
    stop("prompts must be provided as a character vector, data frame, or list", call. = FALSE)
  }

  if (!is.character(prompts)) {
    stop("prompts must resolve to a character vector", call. = FALSE)
  }

  if (length(prompts) == 0L) {
    stop("prompts input must return at least one prompt", call. = FALSE)
  }

  if (length(sample_id) != length(prompts)) {
    stop("sample_id must be the same length as prompts", call. = FALSE)
  }

  sample_id <- unname(sample_id)
  if (is.factor(sample_id)) {
    sample_id <- as.character(sample_id)
  }

  if (!is.null(truth)) {
    truth <- unname(truth)
    if (is.factor(truth)) {
      truth <- as.character(truth)
    }
  }

  list(
    prompt = prompts,
    sample_id = sample_id,
    truth = truth
  )
}

.validate_sink <- function(sink) {
  if (is.null(sink)) {
    return(NULL)
  }
  if (!is.function(sink)) {
    stop("sink must be NULL or a function", call. = FALSE)
  }
  sink
}

.resolve_prompts_source <- function(prompts_source, spec = NULL) {
  if (is.null(prompts_source)) {
    return(NULL)
  }
  if (is.function(prompts_source)) {
    return(prompts_source)
  }
  if (is.character(prompts_source)) {
    return(.prompts_from_vector(prompts_source))
  }
  if (is.list(prompts_source)) {
    return(.prompts_from_template(prompts_source))
  }
  stop("`prompts` must be a function, character vector, or template list", call. = FALSE)
}

.prompts_from_vector <- function(prompts) {
  prompts <- as.character(prompts)
  function(spec) { # nolint
    data.frame(
      sample_id = seq_along(prompts),
      prompt = prompts,
      stringsAsFactors = FALSE
    )
  }
}

.prompts_from_template <- function(config) {
  if (!is.list(config)) {
    stop("Template prompts configuration must be supplied as a list", call. = FALSE)
  }

  # Meta keys don't render as content
  meta_keys <- c("sample_id", "format", "truth")

  # Get sample_id to determine iteration count
 sample_id <- config$sample_id
  if (is.null(sample_id)) {
    # Find first vector field to determine length
    for (key in names(config)) {
      if (!key %in% meta_keys && length(config[[key]]) > 1 && !is.list(config[[key]])) {
        sample_id <- seq_along(config[[key]])
        break
      }
    }
    if (is.null(sample_id)) {
      stop("Template must have sample_id or at least one vector field", call. = FALSE)
    }
  }
  n_items <- length(sample_id)

  # Get content keys in original order
 content_keys <- names(config)[!names(config) %in% meta_keys]

  # Identify which fields are per-item (vectors with matching length)
  per_item_keys <- vapply(content_keys, function(key) {
    val <- config[[key]]
    !is.list(val) && length(val) == n_items && n_items > 1
  }, logical(1))

  function(spec) { # nolint
    prompts <- vapply(
      seq_len(n_items),
      function(i) {
        # Build sections in original order
        sections <- vapply(content_keys, function(key) {
          val <- config[[key]]
          if (per_item_keys[[key]]) {
            # Per-item field - use i-th element
            val <- val[i]
          }
          .render_field(key, val, depth = 0)
        }, character(1))

        paste(sections, collapse = "\n\n")
      },
      character(1)
    )

    data.frame(
      sample_id = sample_id,
      prompt = prompts,
      stringsAsFactors = FALSE
    )
  }
}


# -----------------------------------------------------------------------------
# Prompt template rendering helpers (generic nested list support)
# -----------------------------------------------------------------------------

#' Convert snake_case or camelCase names to Title Case
#' @param name Character string to convert
#' @return Title-cased string
#' @noRd
.name_to_title <- function(name) {

  # Handle snake_case: split on underscores

  parts <- strsplit(name, "_")[[1]]
  # Handle camelCase: split on uppercase letters

  parts <- unlist(lapply(parts, function(p) {
    # Insert space before uppercase letters (camelCase)
    p <- gsub("([a-z])([A-Z])", "\\1 \\2", p)
    strsplit(p, " ")[[1]]
  }))
  # Capitalize first letter of each word
  parts <- vapply(parts, function(w) {
    paste0(toupper(substr(w, 1, 1)), tolower(substr(w, 2, nchar(w))))
  }, character(1))
  paste(parts, collapse = " ")
}

#' Singularize a name by stripping trailing 's' (simple heuristic)
#' @param name Character string to singularize
#' @return Singularized and title-cased string
#' @noRd
.singularize <- function(name) {
  # First convert to title case

  title <- .name_to_title(name)
  # Simple heuristic: strip trailing 's' if present and word is > 2 chars
  words <- strsplit(title, " ")[[1]]
  last_word <- words[length(words)]
  if (nchar(last_word) > 2 && grepl("s$", last_word)) {
    words[length(words)] <- sub("s$", "", last_word)
  }
  paste(words, collapse = " ")
}

#' Format a section header at the appropriate depth
#' @param name Section name (will be title-cased)
#' @param depth Nesting depth (0 = ##, 1 = ###, 2+ = bold inline)
#' @return Formatted header string
#' @noRd
.format_prompt_header <- function(name, depth) {
  title <- .name_to_title(name)
  if (depth == 0) {
    sprintf("## %s", title)
  } else if (depth == 1) {
    sprintf("### %s", title)
  } else {
    sprintf("**%s:**", title)
  }
}

#' Render a vector as bullet points or inline text
#' @param x Vector to render
#' @param indent Number of spaces to indent bullets
#' @return Formatted string
#' @noRd
.render_prompt_vector <- function(x, indent = 0) {
  x <- as.character(x)
  if (length(x) == 1L) {
    return(x)
  }
  prefix <- paste0(strrep(" ", indent), "- ")
  paste0(prefix, x, collapse = "\n")
}

#' Render a data frame as numbered sections
#' @param df Data frame to render
#' @param depth Current nesting depth
#' @param parent_name Name of parent element (for singularization)
#' @return Formatted string
#' @noRd
.render_prompt_dataframe <- function(df, depth, parent_name = NULL) {
  singular <- if (!is.null(parent_name)) .singularize(parent_name) else "Item"
  rows <- lapply(seq_len(nrow(df)), function(i) {
    header <- .format_prompt_header(sprintf("%s %d", singular, i), depth)
    fields <- vapply(names(df), function(col) {
      sprintf("- %s: %s", .name_to_title(col), as.character(df[i, col]))
    }, character(1))
    paste(c(header, fields), collapse = "\n")
  })
  paste(rows, collapse = "\n\n")
}

#' Render a single field with its name and value
#' @param name Field name (used as-is for header)
#' @param value Field value
#' @param depth Nesting depth
#' @return Formatted string
#' @noRd
.render_field <- function(name, value, depth = 0) {
  header <- if (depth == 0) {
    sprintf("## %s", name)
  } else if (depth == 1) {
    sprintf("### %s", name)
  } else {
    sprintf("**%s:**", name)
  }

  if (is.null(value)) {
    return(header)
  }

  if (is.data.frame(value)) {
    content <- .render_prompt_dataframe(value, depth + 1, name)
    return(paste0(header, "\n\n", content))
  }

  if (is.list(value)) {
    # Check if unnamed list (numbered items)
    nms <- names(value)
    if (is.null(nms) || !all(nzchar(nms))) {
      content <- .render_unnamed_list(value, depth + 1, name)
      return(paste0(header, "\n\n", content))
    } else {
      # Named list - render nested fields
      nested <- vapply(names(value), function(k) {
        .render_field(k, value[[k]], depth + 1)
      }, character(1))
      return(paste0(header, "\n", paste(nested, collapse = "\n")))
    }
  }

  # Atomic vector
  if (length(value) > 1) {
    content <- paste0("- ", as.character(value), collapse = "\n")
    return(paste0(header, "\n", content))
  }

  # Scalar
  paste0(header, "\n", as.character(value))
}

#' Render an unnamed list as numbered items
#' @param x Unnamed list
#' @param depth Current depth
#' @param parent_name Parent name for singularization
#' @return Formatted string
#' @noRd
.render_unnamed_list <- function(x, depth, parent_name) {
  singular <- .singularize(parent_name)
  items <- lapply(seq_along(x), function(i) {
    item <- x[[i]]
    header <- if (depth == 1) {
      sprintf("### %s %d", singular, i)
    } else {
      sprintf("**%s %d:**", singular, i)
    }

    if (is.list(item) && !is.data.frame(item)) {
      item_nms <- names(item)
      if (!is.null(item_nms) && all(nzchar(item_nms))) {
        # Named list item - render as indented bullet points
        fields <- vapply(item_nms, function(k) {
          sprintf("- %s: %s", k, as.character(item[[k]]))
        }, character(1))
        paste(c(header, fields), collapse = "\n")
      } else {
        paste0(header, "\n", .render_unnamed_list(item, depth + 1, parent_name))
      }
    } else if (is.data.frame(item)) {
      paste0(header, "\n", .render_prompt_dataframe(item, depth + 1, NULL))
    } else {
      paste0(header, "\n", .render_prompt_vector(item))
    }
  })
  paste(items, collapse = "\n\n")
}

#' Recursively render a list structure as a formatted prompt
#' @param x List, vector, data frame, or scalar to render
#' @param depth Current nesting depth
#' @param parent_name Name of parent element (for unnamed list singularization)
#' @return Formatted string
#' @noRd
.render_list_as_prompt <- function(x, depth = 0, parent_name = NULL) {
  # Handle NULL

if (is.null(x)) {
    return("")
  }

  # Handle data frames
  if (is.data.frame(x)) {
    return(.render_prompt_dataframe(x, depth + 1, parent_name))
  }

  # Handle atomic vectors (not lists)
  if (!is.list(x)) {
    return(.render_prompt_vector(x, indent = depth * 2))
  }

  # Handle lists
  nms <- names(x)
  has_names <- !is.null(nms) && all(nzchar(nms))

  if (has_names) {
    # Named list: render each element with its name as header
    sections <- vapply(seq_along(x), function(i) {
      nm <- nms[i]
      val <- x[[i]]
      header <- .format_prompt_header(nm, depth)

      # Determine content based on type
      if (is.null(val)) {
        content <- ""
      } else if (is.data.frame(val)) {
        content <- paste0("\n\n", .render_prompt_dataframe(val, depth + 1, nm))
      } else if (is.list(val)) {
        # Check if it's an unnamed list (numbered items)
        sub_nms <- names(val)
        if (is.null(sub_nms) || !all(nzchar(sub_nms))) {
          # Unnamed list: render as numbered items
          content <- paste0("\n\n", .render_list_as_prompt(val, depth + 1, nm))
        } else {
          # Named list: recursive render
          content <- paste0("\n", .render_list_as_prompt(val, depth + 1, nm))
        }
      } else if (length(val) > 1) {
        # Multi-element vector: bullet list
        content <- paste0("\n", .render_prompt_vector(val, indent = 0))
      } else {
        # Scalar: inline
        content <- paste0("\n", as.character(val))
      }

      paste0(header, content)
    }, character(1))
    paste(sections, collapse = "\n\n")
  } else {
    # Unnamed list: render as numbered items (Example 1, Example 2, etc.)
    singular <- if (!is.null(parent_name)) .singularize(parent_name) else "Item"
    items <- lapply(seq_along(x), function(i) {
      item <- x[[i]]
      header <- .format_prompt_header(sprintf("%s %d", singular, i), depth)

      if (is.list(item) && !is.data.frame(item)) {
        item_nms <- names(item)
        if (!is.null(item_nms) && all(nzchar(item_nms))) {
          # Named list item: render fields as bullet points
          fields <- vapply(seq_along(item), function(j) {
            sprintf("- %s: %s", .name_to_title(item_nms[j]), as.character(item[[j]]))
          }, character(1))
          paste(c(header, fields), collapse = "\n")
        } else {
          # Nested unnamed list
          paste0(header, "\n", .render_list_as_prompt(item, depth + 1, parent_name))
        }
      } else if (is.data.frame(item)) {
        paste0(header, "\n", .render_prompt_dataframe(item, depth + 1, NULL))
      } else {
        paste0(header, "\n", .render_prompt_vector(item))
      }
    })
    paste(items, collapse = "\n\n")
  }
}

.normalise_model_specs <- function(models, instruction, chat_template = TRUE, system_prompt = NULL) {

  # Handle single model_path string (consistent with model_load() syntax)
  if (is.character(models) && length(models) == 1L && is.null(names(models))) {
    models <- list(list(id = "model_1", model_path = models))
  } else if (is.character(models)) {
    # Named character vector: c(llama = "path.gguf", qwen = "path2.gguf")
    ids <- names(models)
    models <- as.list(models)
    specs <- Map(function(path, id, idx) {
      list(id = id %||% sprintf("model_%d", idx), model_path = path)
    }, models, ids, seq_along(models))
    models <- specs
  } else if (!is.list(models)) {
    stop("models must be a character vector, a single model path, or a list of model specs", call. = FALSE)
  }

  lapply(seq_along(models), function(i) {
    spec <- models[[i]]

    # Ensure spec is a list
    if (!is.list(spec)) {
      stop(sprintf("Model entry %d must be a list, got %s", i, class(spec)[1]), call. = FALSE)
    }

    # Auto-generate id if missing
    if (is.null(spec$id)) {
      spec$id <- sprintf("model_%d", i)
    }

    # Validate id
    if (!is.character(spec$id) || length(spec$id) != 1L || !nzchar(spec$id)) {
      stop(sprintf("Model entry %d: 'id' must be a non-empty string", i), call. = FALSE)
    }

    # Check for common mistake: using 'model' instead of 'model_path'
    # Use [["model"]] for exact matching ($ does partial matching and would match model_path)
    if (!is.null(spec[["model"]])) {
      stop(sprintf("Model '%s' must declare 'model_path' instead of 'model'", spec$id), call. = FALSE)
    }

    # Only require model_path if no predictor function is provided
    has_predictor <- is.function(spec$predictor)
    if (!has_predictor) {
      if (is.null(spec$model_path)) {
        stop(sprintf("Model '%s' is missing the required 'model_path' entry", spec$id), call. = FALSE)
      }
      if (!is.character(spec$model_path) || length(spec$model_path) < 1L || !nzchar(trimws(spec$model_path[[1L]]))) {
        stop(sprintf("Model '%s' must supply a non-empty character 'model_path'", spec$id), call. = FALSE)
      }
    }

    # Validate n_gpu_layers: must be "auto", integer, or numeric coercible to integer
    if (!is.null(spec$n_gpu_layers)) {
      if (identical(spec$n_gpu_layers, "auto")) {
        # Valid - will be resolved later
      } else if (is.numeric(spec$n_gpu_layers)) {
        spec$n_gpu_layers <- as.integer(spec$n_gpu_layers)
        if (spec$n_gpu_layers < -1L) {
          stop(sprintf("Model '%s': n_gpu_layers must be >= -1 (got %d)", spec$id, spec$n_gpu_layers), call. = FALSE)
        }
      } else {
        stop(sprintf("Model '%s': n_gpu_layers must be 'auto', an integer, or NULL (got %s)",
                     spec$id, class(spec$n_gpu_layers)[1]), call. = FALSE)
      }
    }

    # Validate n_ctx: must be positive integer
    if (!is.null(spec$n_ctx)) {
      if (!is.numeric(spec$n_ctx) || length(spec$n_ctx) != 1L) {
        stop(sprintf("Model '%s': n_ctx must be a single numeric value", spec$id), call. = FALSE)
      }
      spec$n_ctx <- as.integer(spec$n_ctx)
      if (spec$n_ctx < 1L) {
        stop(sprintf("Model '%s': n_ctx must be >= 1 (got %d)", spec$id, spec$n_ctx), call. = FALSE)
      }
    }

    # Validate n_threads: must be positive integer
    if (!is.null(spec$n_threads)) {
      if (!is.numeric(spec$n_threads) || length(spec$n_threads) != 1L) {
        stop(sprintf("Model '%s': n_threads must be a single numeric value", spec$id), call. = FALSE)
      }
      spec$n_threads <- as.integer(spec$n_threads)
      if (spec$n_threads < 1L) {
        stop(sprintf("Model '%s': n_threads must be >= 1 (got %d)", spec$id, spec$n_threads), call. = FALSE)
      }
    }

    # Validate verbosity: must be integer
    if (!is.null(spec$verbosity)) {
      if (!is.numeric(spec$verbosity) || length(spec$verbosity) != 1L) {
        stop(sprintf("Model '%s': verbosity must be a single numeric value", spec$id), call. = FALSE)
      }
      spec$verbosity <- as.integer(spec$verbosity)
    }

    # Validate boolean parameters
    for (param in c("use_mmap", "use_mlock", "check_memory", "force_redownload", "verify_integrity")) {
      if (!is.null(spec[[param]])) {
        if (!is.logical(spec[[param]]) || length(spec[[param]]) != 1L) {
          stop(sprintf("Model '%s': %s must be TRUE or FALSE", spec$id, param), call. = FALSE)
        }
      }
    }

    # Validate hf_token: must be NULL or non-empty string
    if (!is.null(spec$hf_token)) {
      if (!is.character(spec$hf_token) || length(spec$hf_token) != 1L || !nzchar(spec$hf_token)) {
        stop(sprintf("Model '%s': hf_token must be a non-empty string or NULL", spec$id), call. = FALSE)
      }
    }

    # Validate cache_dir: must be NULL or character
    if (!is.null(spec$cache_dir)) {
      if (!is.character(spec$cache_dir) || length(spec$cache_dir) != 1L) {
        stop(sprintf("Model '%s': cache_dir must be a single string or NULL", spec$id), call. = FALSE)
      }
    }

    # Validate chat_template: must be logical (TRUE/FALSE)
    if (!is.null(spec$chat_template)) {
      if (!is.logical(spec$chat_template) || length(spec$chat_template) != 1L) {
        stop(sprintf("Model '%s': chat_template must be TRUE or FALSE", spec$id), call. = FALSE)
      }
    }

    # Validate system_prompt: must be NULL or character string
    if (!is.null(spec$system_prompt)) {
      if (!is.character(spec$system_prompt) || length(spec$system_prompt) != 1L) {
        stop(sprintf("Model '%s': system_prompt must be a single string or NULL", spec$id), call. = FALSE)
      }
    }

    # Clean up: remove 'model' key if present (already validated above)
    spec$model <- NULL
    spec$instruction <- spec$instruction %||% instruction
    # Apply global defaults for chat_template and system_prompt (model spec overrides)
    spec$chat_template <- spec$chat_template %||% chat_template
    spec$system_prompt <- spec$system_prompt %||% system_prompt
    spec
  })
}

.spec_model_source <- function(spec) {
  if (is.null(spec$model_path)) return(NA_character_)
  trimws(as.character(spec$model_path[[1L]]))
}

.explore_spec_summary <- function(spec) {
  list(
    id = spec$id,
    model = .spec_model_source(spec) %||% NA_character_,
    has_predictor = isTRUE(is.function(spec$predictor)),
    has_custom_prompts = !is.null(spec$prompts),
    n_gpu_layers = spec$n_gpu_layers %||% "auto",
    n_ctx = spec$n_ctx %||% 2048L,
    has_hf_token = !is.null(spec$hf_token),
    generation = .explore_generation_summary(spec$generation)
  )
}

.explore_generation_summary <- function(gen) {
  if (is.null(gen) || !is.list(gen)) {
    return(gen)
  }
  keep <- !vapply(gen, is.function, logical(1))
  gen[keep]
}

.run_model_over_data <- function(prompts,
                                 spec,
                                 engine,
                                 batch_size,
                                 reuse_models,
                                 model_cache,
                                 progress,
                                 clean,
                                 hash = FALSE) {
  outputs <- NULL
  input_hash <- NULL
  output_hash <- NULL
  model_source <- .spec_model_source(spec)

  if (isTRUE(hash)) {
    input_payload <- list(
      type = "explore",
      model_id = spec$id,
      model_source = .hash_normalise_model_source(model_source, fallback = spec$id),
      prompts = prompts,
      generation = .explore_generation_summary(spec$generation),
      engine = engine,
      batch_size = batch_size,
      reuse_models = isTRUE(reuse_models),
      clean = isTRUE(clean)
    )
    input_hash <- .hash_payload(input_payload)
  }

  if (is.function(spec$predictor)) {
    outputs <- spec$predictor(prompts, NULL, spec)
    if (!is.character(outputs) || length(outputs) != length(prompts)) {
      stop(sprintf("predictor for model '%s' must return character vector of length %d", spec$id, length(prompts)), call. = FALSE)
    }
  } else {
    handles <- .get_or_create_handles(spec, reuse_models, model_cache, progress)

    # Apply chat template if enabled (uses model's built-in template)
    if (isTRUE(spec$chat_template)) {
      prompts <- .apply_model_chat_template(prompts, handles$model, spec$system_prompt)
    }

    outputs <- .generate_in_batches(prompts, handles$context, engine, batch_size, spec, progress,
                                    clean, hash_backend = FALSE)
    if (!reuse_models) {
      handles$model <- NULL
      handles$context <- NULL
      gc()
    }
  }

  if (isTRUE(hash)) {
    output_payload <- list(
      type = "explore",
      model_id = spec$id,
      output = outputs
    )
    output_hash <- .hash_payload(output_payload)
  }

  list(output = outputs, input_hash = input_hash, output_hash = output_hash)
}

# Apply chat template to prompts using model's built-in template
.apply_model_chat_template <- function(prompts, model, system_prompt = NULL) {
  vapply(prompts, function(p) {
    messages <- list()
    if (!is.null(system_prompt) && nzchar(system_prompt)) {
      messages[[1]] <- list(role = "system", content = system_prompt)
      messages[[2]] <- list(role = "user", content = p)
    } else {
      messages[[1]] <- list(role = "user", content = p)
    }
    apply_chat_template(model, messages, add_assistant = TRUE)
  }, character(1), USE.NAMES = FALSE)
}

# Detect optimal GPU layers based on system capabilities
# This mirrors the logic in quick_llama.R for consistency
.explore_detect_gpu_layers <- function() {
  sysname <- Sys.info()["sysname"]

  if (sysname == "Darwin") {
    # On macOS, assume Metal is available
    return(999L)
  } else if (sysname == "Linux") {
    # On Linux, check if NVIDIA GPU tools are available
    nvidia_smi <- Sys.which("nvidia-smi")
    if (nvidia_smi != "") {
      return(999L)
    }
  }

  # Default to CPU-only
  return(0L)
}

.get_or_create_handles <- function(spec, reuse_models, model_cache, progress) {
  cache_key <- spec$id
  if (reuse_models && exists(cache_key, envir = model_cache, inherits = FALSE)) {
    return(get(cache_key, envir = model_cache, inherits = FALSE))
  }

  model_source <- .spec_model_source(spec)
  if (is.null(model_source) || !nzchar(model_source)) {
    stop(sprintf("Model '%s' is missing the 'model_path' value", spec$id), call. = FALSE)
  }

  n_threads <- spec$n_threads %||% max(1L, parallel::detectCores() - 1L)
  n_ctx <- spec$n_ctx %||% 2048L
  verbosity <- as.integer(spec$verbosity %||% 1L)
  n_seq_max <- spec$n_seq_max %||% 1L

  # Handle n_gpu_layers with "auto" support (consistent with quick_llama)
  n_gpu_layers <- spec$n_gpu_layers %||% "auto"
  if (identical(n_gpu_layers, "auto")) {
    n_gpu_layers <- .explore_detect_gpu_layers()
  } else {
    n_gpu_layers <- as.integer(n_gpu_layers)
  }

  quiet_state <- .localllm_set_quiet(verbosity < 0L)
  on.exit(.localllm_restore_quiet(quiet_state), add = TRUE)

  if (isTRUE(progress)) {
    .localllm_message(sprintf("[%s] Loading model...", spec$id))
  }

  # Pass all model_load() parameters for full consistency
  model_obj <- model_load(model_source,
                          cache_dir = spec$cache_dir,
                          n_gpu_layers = n_gpu_layers,
                          use_mmap = spec$use_mmap %||% TRUE,
                          use_mlock = spec$use_mlock %||% FALSE,
                          show_progress = isTRUE(progress),
                          force_redownload = spec$force_redownload %||% FALSE,
                          verify_integrity = spec$verify_integrity %||% TRUE,
                          check_memory = spec$check_memory %||% TRUE,
                          hf_token = spec$hf_token,
                          verbosity = verbosity)

  ctx <- context_create(model_obj,
                        n_ctx = as.integer(n_ctx),
                        n_threads = as.integer(n_threads),
                        n_seq_max = as.integer(n_seq_max),
                        verbosity = verbosity)

  handles <- list(model = model_obj, context = ctx)

  if (reuse_models) {
    assign(cache_key, handles, envir = model_cache)
  }

  handles
}

.generate_in_batches <- function(prompts, context, engine, batch_size, spec, progress, clean,
                                 hash_backend = FALSE) {
  n <- length(prompts)
  outputs <- character(n)
  use_parallel <- switch(engine,
                         parallel = TRUE,
                         single = FALSE,
                         auto = batch_size > 1L)

  # Validate parallel mode requirements
  if (use_parallel) {
    ctx_seq_max <- attr(context, "n_seq_max")
    if (is.null(ctx_seq_max)) ctx_seq_max <- 1L
    if (ctx_seq_max < 2L) {
      # For explicit "parallel", throw error
      # For "auto", fall back to single-sequence mode
      if (engine == "parallel") {
        stop("engine='parallel' requires a context with n_seq_max >= 2.\n",
             "Current context has n_seq_max=", ctx_seq_max, ".\n\n",
             "To fix this, either:\n",
             "  1. Increase n_seq_max in your model specification:\n",
             "     models <- list(\n",
             "       list(model_id = \"mymodel\", path = \"...\", n_seq_max = 8L)\n",
             "     )\n",
             "  2. Use engine=\"auto\" (automatically chooses best mode)\n",
             "  3. Use engine=\"single\" (sequential processing)",
             call. = FALSE)
      } else {
        # Auto mode: silently fall back to single-sequence
        use_parallel <- FALSE
      }
    }
  }

  remaining <- seq_len(n)
  gen_args <- spec$generation %||% list()
  gen_args$max_tokens <- gen_args$max_tokens %||% 100L
  gen_args$top_k <- gen_args$top_k %||% 40L
  gen_args$top_p <- gen_args$top_p %||% 1.0
  gen_args$temperature <- gen_args$temperature %||% 0.0
  gen_args$repeat_last_n <- gen_args$repeat_last_n %||% 0L
  gen_args$penalty_repeat <- gen_args$penalty_repeat %||% 1.0
  gen_args$seed <- gen_args$seed %||% 1234L
  gen_args$hash <- isTRUE(hash_backend)

  idx <- 1L
  while (idx <= n) {
    end <- min(idx + batch_size - 1L, n)
    batch_prompts <- prompts[idx:end]
    if (use_parallel && length(batch_prompts) > 1L) {
      chunk <- do.call(generate_parallel, c(list(context = context,
                                                 prompts = batch_prompts,
                                                 clean = clean,
                                                 progress = progress && length(batch_prompts) > 1L),
                                            gen_args))
      outputs[idx:end] <- unname(if (is.list(chunk)) unlist(chunk, use.names = FALSE) else chunk)
    } else {
      chunk <- vapply(batch_prompts, function(p) {
        do.call(generate, c(list(context = context,
                                 prompt = p,
                                 clean = clean), gen_args))
      }, character(1))
      outputs[idx:end] <- chunk
    }
    idx <- end + 1L
  }

  outputs
}

.wide_annotation_matrix <- function(annotations) {
  if (is.null(annotations) || nrow(annotations) == 0L) {
    return(annotations)
  }
  wide <- stats::reshape(annotations, idvar = "sample_id", timevar = "model_id", direction = "wide", sep = "_")
  names(wide) <- sub("^label_", "", names(wide))
  wide
}

.as_annotation_df <- function(annotations, sample_col, model_col, label_col, truth_col) {
  if (is.list(annotations) && !is.null(annotations$annotations)) {
    df <- annotations$annotations
  } else if (is.data.frame(annotations)) {
    df <- annotations
  } else {
    stop("annotations must be a data frame or the result of explore()", call. = FALSE)
  }

  required <- c(sample_col, model_col, label_col)
  missing <- setdiff(required, names(df))
  if (length(missing)) {
    stop(sprintf("annotations is missing required column(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  if (!is.null(truth_col) && !truth_col %in% names(df)) {
    df[[truth_col]] <- NA_character_
  }

  df
}


.truth_column <- function(df, gold, sample_col, truth_col) {
  ids <- as.character(unique(df[[sample_col]]))
  if (!is.null(gold)) {
    if (length(gold) == length(ids)) {
      if (!is.null(names(gold))) {
        gold <- gold[match(ids, names(gold))]
      }
      names(gold) <- ids
      return(gold)
    }
    if (is.character(gold) && gold %in% names(df)) {
      truth <- tapply(df[[gold]], df[[sample_col]], function(x) x[1])
      return(truth)
    }
    stop("gold must either be a vector aligned with unique samples or the name of a column in annotations", call. = FALSE)
  }

  if (truth_col %in% names(df)) {
    truth <- tapply(df[[truth_col]], df[[sample_col]], function(x) x[1])
    truth <- truth[match(ids, names(truth))]
    names(truth) <- ids
    return(truth)
  }

  NULL
}

.infer_levels <- function(...) {
  vals <- unlist(list(...), use.names = FALSE)
  vals <- vals[!is.na(vals)]
  if (length(vals) == 0L) {
    return(NULL)
  }
  unique(as.character(vals))
}

.cohen_kappa <- function(a, b, levels) {
  tab <- table(factor(a, levels = levels), factor(b, levels = levels))
  total <- sum(tab)
  if (total == 0) {
    return(list(kappa = NA_real_, observed = NA_real_, expected = NA_real_))
  }
  p0 <- sum(diag(tab)) / total
  px <- rowSums(tab) / total
  py <- colSums(tab) / total
  pe <- sum(px * py)
  kappa <- if (abs(1 - pe) < .Machine$double.eps) NA_real_ else (p0 - pe) / (1 - pe)
  list(kappa = kappa, observed = p0, expected = pe)
}

.krippendorff_alpha <- function(ann_df, levels, sample_col, model_col, label_col) {
  counts_list <- tapply(seq_len(nrow(ann_df)), ann_df[[sample_col]], function(idx) {
    table(factor(ann_df[[label_col]][idx], levels = levels))
  }, simplify = FALSE)

  if (length(counts_list) == 0) {
    return(list(alpha = NA_real_, per_item = numeric(), category_proportions = rep(NA_real_, length(levels))))
  }

  counts_mat <- do.call(rbind, counts_list)
  rownames(counts_mat) <- names(counts_list)

  item_totals <- rowSums(counts_mat)
  per_item <- rep(NA_real_, length(item_totals))
  names(per_item) <- rownames(counts_mat)

  coincidence <- matrix(0, nrow = length(levels), ncol = length(levels),
                        dimnames = list(levels, levels))

  # Check for missing data: either NA labels OR varying number of coders per unit
  # This matches irr::kripp.alpha behavior which uses mc=1 for complete data
  # and mc=(n_i-1) per unit when there are missing values
  has_na_labels <- any(is.na(ann_df[[label_col]]))
  has_varying_coders <- length(unique(item_totals[item_totals > 0])) > 1
  has_missing <- has_na_labels || has_varying_coders

  for (i in seq_len(nrow(counts_mat))) {
    counts_vec <- as.numeric(counts_mat[i, ])
    n_i <- sum(counts_vec)
    if (n_i <= 1) {
      next
    }

    denom <- n_i * (n_i - 1)
    per_item[i] <- if (denom > 0) {
      1 - ((n_i^2 - sum(counts_vec^2)) / denom)
    } else {
      NA_real_
    }

    # Match irr::kripp.alpha behavior:
    # - When data is complete (no NAs, same number of coders per unit): mc = 1
    # - When data has missing values: mc = n_i - 1 per unit
    mc <- if (has_missing) n_i - 1 else 1
    item_matrix <- (counts_vec %o% counts_vec) / mc
    diag(item_matrix) <- counts_vec * (counts_vec - 1) / mc
    coincidence <- coincidence + item_matrix
  }

  n_match <- sum(coincidence)
  observed <- sum(coincidence[upper.tri(coincidence, diag = FALSE)])
  nc <- rowSums(coincidence)
  expected <- 0
  if (length(nc) >= 2) {
    for (r in seq_along(nc)) {
      if (nc[r] == 0) next
      if (r == 1) next
      expected <- expected + sum(nc[r] * nc[seq_len(r - 1)])
    }
  }

  alpha <- NA_real_
  if (length(levels) < 2) {
    alpha <- 1
  } else if (observed == 0 && n_match > 0) {
    # Perfect agreement: no off-diagonal coincidences
    alpha <- 1
  } else if (expected > 0 && n_match > 1) {
    alpha <- 1 - ((n_match - 1) * observed) / expected
  }

  category_totals <- colSums(counts_mat)
  total_assignments <- sum(category_totals)
  proportions <- if (total_assignments > 0) {
    category_totals / total_assignments
  } else {
    rep(NA_real_, length(levels))
  }
  names(proportions) <- colnames(counts_mat)

  list(alpha = alpha, per_item = per_item, category_proportions = proportions)
}
