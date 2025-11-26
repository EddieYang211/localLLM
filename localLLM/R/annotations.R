# --- FILE: localLLM/R/annotations.R ---

#' Compare multiple LLMs over a shared set of prompts
#'
#' `explore()` orchestrates running several models over the same prompts,
#' captures their predictions, and returns both long and wide annotation
#' tables that can be fed into confusion-matrix and reliability helpers.
#'
#' @param models Model definitions. Accepts either a named character vector
#'   (names become `model_id`s) or a list where each element is a list with at
#'   least `id` and `model` (path/URL). Each model entry can optionally specify
#'   `instruction`, `generation` parameters, a custom `prompt_builder`, or a
#'   `predictor` function for mock/testing scenarios.
#' @param instruction Default task instruction inserted into `spec` whenever a
#'   model entry does not override it.
#' @param prompts One of: (1) a function (for example `function(spec)`)
#'   that returns prompts (character vector or a data frame with a `prompt` column);
#'   (2) a character vector of ready-made prompts; or (3) a template list with
#'   entries such as `annotation_task`, `coding_rules`, `examples`,
#'   `target_text`, `sample_id`, `output_format`, and optional
#'   `data`/`text_col`/`id_col` keys. Template lists are rendered using the
#'   built-in annotation format described in the README. When `NULL`, each model
#'   must provide its own `prompt_builder`.
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
                    keep_prompts = FALSE) {
  engine <- match.arg(engine)
  batch_size <- as.integer(batch_size)
  if (batch_size < 1L) {
    stop("batch_size must be >= 1", call. = FALSE)
  }

  if (missing(models) || length(models) == 0L) {
    stop("models must not be empty", call. = FALSE)
  }

  sink <- .validate_sink(sink)
  specs <- .normalise_model_specs(models, instruction)

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
  model_cache <- if (reuse_models) new.env(parent = emptyenv()) else NULL

  for (spec in specs) {
    builder <- .resolve_prompt_builder(spec$prompt_builder %||% prompts)
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
                                     clean = clean)

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

  list(
    annotations = annotations,
    matrix = matrix_view
  )
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
#' @param method One of `"auto"`, `"cohen"`, or `"fleiss"`. The `"auto"`
#'   setting computes both pairwise Cohen's Kappa and Fleiss' Kappa (when
#'   applicable).
#' @param sample_col Column name that identifies samples when `annotations` is a
#'   user-provided data frame.
#' @param model_col Column name for the model identifier when using a custom
#'   `annotations` data frame.
#' @param label_col Column name containing model predictions when using a custom
#'   `annotations` data frame.
#' @return A list containing `cohen` (data frame of pairwise kappas) and/or
#'   `fleiss` (overall statistic with per-item agreement scores).
#' @export
intercoder_reliability <- function(annotations,
                                   method = c("auto", "cohen", "fleiss"),
                                   label_levels = NULL,
                                   sample_col = "sample_id",
                                   model_col = "model_id",
                                   label_col = "label") {
  method <- match.arg(method)
  ann_df <- .as_annotation_df(annotations, sample_col, model_col, label_col, truth_col = NULL)
  label_levels <- label_levels %||% .infer_levels(ann_df[[label_col]])

  out <- list()
  need_cohen <- method %in% c("auto", "cohen")
  need_fleiss <- method %in% c("auto", "fleiss")

  if (need_cohen) {
    model_ids <- unique(ann_df[[model_col]])
    if (length(model_ids) >= 2L) {
      combos <- utils::combn(model_ids, 2L, simplify = FALSE)
      cohen_df <- lapply(combos, function(pair_ids) {
        tab <- stats::reshape(ann_df[ann_df[[model_col]] %in% pair_ids, c(sample_col, model_col, label_col)],
                       idvar = sample_col,
                       timevar = model_col,
                       direction = "wide")
        colnames(tab) <- sub("^label\\.", "", colnames(tab))
        stats <- .cohen_kappa(tab[[pair_ids[1]]], tab[[pair_ids[2]]], label_levels)
        c(model_a = pair_ids[1], model_b = pair_ids[2], kappa = stats$kappa, observed = stats$observed, expected = stats$expected)
      })
      out$cohen <- do.call(rbind, cohen_df)
      rownames(out$cohen) <- NULL
    }
  }

  if (need_fleiss) {
    fleiss <- .fleiss_kappa(ann_df, label_levels, sample_col, model_col, label_col)
    out$fleiss <- fleiss
  }

  out
}

#' Validate model predictions against gold labels and peer agreement
#'
#' `validate()` is a convenience wrapper that runs both
#' [compute_confusion_matrices()] and [intercoder_reliability()] so that a
#' single call yields per-model confusion matrices (vs gold labels and
#' pairwise) as well as Cohen/Fleiss kappa scores.
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
                     method = c("auto", "cohen", "fleiss"),
                     include_confusion = TRUE,
                     include_reliability = TRUE) {
  method <- match.arg(method)

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
    stop("prompt_builder must return prompts", call. = FALSE)
  }

  if (is.character(builder_output)) {
    prompts <- builder_output
    sample_id <- seq_along(prompts)
    truth <- NULL
  } else if (is.data.frame(builder_output)) {
    if (!"prompt" %in% names(builder_output)) {
      stop("prompt_builder data frame output must contain a 'prompt' column", call. = FALSE)
    }
    prompts <- as.character(builder_output$prompt)
    sample_id <- if ("sample_id" %in% names(builder_output)) builder_output$sample_id else seq_along(prompts)
    truth <- if ("truth" %in% names(builder_output)) builder_output$truth else NULL
  } else if (is.list(builder_output)) {
    prompts <- builder_output$prompt %||% builder_output$prompts
    if (is.null(prompts)) {
      stop("prompt_builder list output must include 'prompt' or 'prompts'", call. = FALSE)
    }
    sample_id <- builder_output$sample_id %||% seq_along(prompts)
    truth <- builder_output$truth %||% NULL
  } else {
    stop("prompt_builder must return a character vector, data frame, or list", call. = FALSE)
  }

  if (!is.character(prompts)) {
    stop("prompts returned by prompt_builder must be character", call. = FALSE)
  }

  if (length(prompts) == 0L) {
    stop("prompt_builder must return at least one prompt", call. = FALSE)
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

.resolve_prompt_builder <- function(builder) {
  if (is.null(builder)) {
    return(NULL)
  }
  if (is.function(builder)) {
    return(builder)
  }
  if (is.character(builder)) {
    return(.vector_prompt_builder(builder))
  }
  if (is.list(builder)) {
    return(.template_prompt_builder(builder))
  }
  stop("prompt_builder must be a function, character vector, or template list", call. = FALSE)
}

.vector_prompt_builder <- function(prompts) {
  prompts <- as.character(prompts)
  function(spec) { # nolint
    data.frame(
      sample_id = seq_along(prompts),
      prompt = prompts,
      stringsAsFactors = FALSE
    )
  }
}

.template_prompt_builder <- function(config) {
  if (!is.list(config)) {
    stop("Template prompt builder must be supplied as a list", call. = FALSE)
  }

  fmt <- tolower(config$format %||% "localllm_template")
  if (!identical(fmt, "localllm_template")) {
    stop(sprintf("Unsupported template format '%s'", config$format), call. = FALSE)
  }

  target_info <- .template_target_data(config)
  annotation_task <- config$annotation_task
  coding_rules <- config$coding_rules
  examples <- config$examples
  output_format <- config$output_format %||% '{"answer": "Your choice here"}'

  function(spec) { # nolint
    task_text <- annotation_task %||% spec$instruction %||% "Review the target text and provide the requested annotation."
    prompts <- vapply(
      seq_along(target_info$target_text),
      function(i) {
        .render_annotation_template(
          task = task_text,
          coding_rules = coding_rules,
          examples = examples,
          target_text = target_info$target_text[i],
          output_format = output_format
        )
      },
      character(1)
    )

    data.frame(
      sample_id = target_info$sample_id,
      prompt = prompts,
      stringsAsFactors = FALSE
    )
  }
}

.template_target_data <- function(config) {
  if (!is.null(config$data)) {
    data <- config$data
    if (!is.data.frame(data)) {
      stop("config$data must be a data frame", call. = FALSE)
    }
    text_col <- config$text_col
    if (is.null(text_col) || !text_col %in% names(data)) {
      stop("When using config$data you must supply text_col present in that data frame", call. = FALSE)
    }
    target_text <- data[[text_col]]
    sample_id <- if (!is.null(config$id_col)) {
      if (!config$id_col %in% names(data)) {
        stop("id_col not found in data", call. = FALSE)
      }
      data[[config$id_col]]
    } else {
      seq_len(nrow(data))
    }
  } else {
    target_text <- config$target_text
    if (is.null(target_text)) {
      stop("Template configuration must include target_text", call. = FALSE)
    }
    sample_id <- config$sample_id %||% seq_along(target_text)
  }

  target_text <- as.character(target_text)
  sample_id <- .coerce_sample_id(sample_id, length(target_text))

  list(target_text = target_text, sample_id = sample_id)
}

.coerce_sample_id <- function(sample_id, n) {
  if (length(sample_id) != n) {
    stop("sample_id must have the same length as target_text", call. = FALSE)
  }
  if (is.factor(sample_id)) {
    sample_id <- as.character(sample_id)
  }
  unname(sample_id)
}

.render_annotation_template <- function(task,
                                        coding_rules,
                                        examples,
                                        target_text,
                                        output_format) {
  rule_block <- .format_coding_rules(coding_rules)
  example_block <- .format_examples(examples)

  paste(
    sprintf("## Annotation Task: %s", task),
    "",
    "## Coding Rules:",
    rule_block,
    "",
    "## Examples:",
    example_block,
    "",
    sprintf("## Target Text: %s", target_text),
    "",
    "## Output Format:",
    output_format,
    "Remember to replace the placeholder text in the 'answer' field with your actual annotation.",
    "Respond only with a valid JSON object and nothing else.",
    sep = "\n"
  )
}

.format_coding_rules <- function(rules) {
  if (is.null(rules)) {
    return("Follow the task instructions carefully.")
  }
  if (length(rules) == 1L) {
    return(as.character(rules))
  }
  paste0("- ", as.character(rules), collapse = "\n")
}

.format_examples <- function(examples) {
  if (is.null(examples)) {
    return("No explicit examples were provided.")
  }

  if (is.data.frame(examples)) {
    required <- c("text", "label")
    if (!all(required %in% names(examples))) {
      stop("Example data frame must contain 'text' and 'label' columns", call. = FALSE)
    }
    lines <- sprintf("- Input: %s\n  Output: %s", examples$text, examples$label)
    return(paste(lines, collapse = "\n"))
  }

  if (is.list(examples) && !is.data.frame(examples)) {
    examples <- unlist(examples, use.names = FALSE)
  }

  examples <- as.character(examples)
  if (length(examples) == 1L) {
    return(examples)
  }
  paste0("- ", examples, collapse = "\n")
}

.normalise_model_specs <- function(models, instruction) {
  if (is.character(models)) {
    ids <- names(models)
    models <- as.list(models)
    specs <- Map(function(path, id, idx) {
      list(id = id %||% sprintf("model_%d", idx), model = path)
    }, models, ids, seq_along(models))
  } else if (is.list(models)) {
    specs <- models
  } else {
    stop("models must be a list or a named character vector", call. = FALSE)
  }

  lapply(seq_along(specs), function(i) {
    spec <- specs[[i]]
    if (is.null(spec$id)) {
      spec$id <- sprintf("model_%d", i)
    }
    spec$instruction <- spec$instruction %||% instruction
    spec
  })
}

.explore_spec_summary <- function(spec) {
  list(
    id = spec$id,
    model = spec$model %||% NA_character_,
    has_predictor = isTRUE(is.function(spec$predictor)),
    has_prompt_builder = isTRUE(is.function(spec$prompt_builder)),
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
                                 clean) {
  outputs <- NULL

  if (is.function(spec$predictor)) {
    outputs <- spec$predictor(prompts, NULL, spec)
    if (!is.character(outputs) || length(outputs) != length(prompts)) {
      stop(sprintf("predictor for model '%s' must return character vector of length %d", spec$id, length(prompts)), call. = FALSE)
    }
  } else {
    handles <- .get_or_create_handles(spec, reuse_models, model_cache, progress)
    outputs <- .generate_in_batches(prompts, handles$context, engine, batch_size, spec, progress, clean)
    if (!reuse_models) {
      handles$model <- NULL
      handles$context <- NULL
      gc()
    }
  }

  list(output = outputs)
}

.get_or_create_handles <- function(spec, reuse_models, model_cache, progress) {
  cache_key <- spec$id
  if (reuse_models && exists(cache_key, envir = model_cache, inherits = FALSE)) {
    return(get(cache_key, envir = model_cache, inherits = FALSE))
  }

  if (is.null(spec$model)) {
    stop(sprintf("Model '%s' is missing the 'model' path or URL", spec$id), call. = FALSE)
  }

  n_threads <- spec$n_threads %||% max(1L, parallel::detectCores() - 1L)
  n_ctx <- spec$n_ctx %||% 2048L
  n_gpu_layers <- spec$n_gpu_layers %||% 0L
  verbosity <- spec$verbosity %||% 1L
  n_seq_max <- spec$n_seq_max %||% 1L

  if (isTRUE(progress)) {
    message(sprintf("[%s] Loading model...", spec$id))
  }
  model_obj <- model_load(spec$model,
                          n_gpu_layers = as.integer(n_gpu_layers),
                          use_mmap = spec$use_mmap %||% TRUE,
                          use_mlock = spec$use_mlock %||% FALSE,
                          show_progress = isTRUE(progress),
                          check_memory = spec$check_memory %||% TRUE,
                          verbosity = as.integer(verbosity))
  ctx <- context_create(model_obj,
                        n_ctx = as.integer(n_ctx),
                        n_threads = as.integer(n_threads),
                        n_seq_max = as.integer(n_seq_max),
                        verbosity = as.integer(verbosity))

  handles <- list(model = model_obj, context = ctx)

  if (reuse_models) {
    assign(cache_key, handles, envir = model_cache)
  }

  handles
}

.generate_in_batches <- function(prompts, context, engine, batch_size, spec, progress, clean) {
  n <- length(prompts)
  outputs <- character(n)
  use_parallel <- switch(engine,
                         parallel = TRUE,
                         single = FALSE,
                         auto = batch_size > 1L)

  remaining <- seq_len(n)
  gen_args <- spec$generation %||% list()
  gen_args$max_tokens <- gen_args$max_tokens %||% 100L
  gen_args$top_k <- gen_args$top_k %||% 40L
  gen_args$top_p <- gen_args$top_p %||% 1.0
  gen_args$temperature <- gen_args$temperature %||% 0.0
  gen_args$repeat_last_n <- gen_args$repeat_last_n %||% 0L
  gen_args$penalty_repeat <- gen_args$penalty_repeat %||% 1.0
  gen_args$seed <- gen_args$seed %||% 1234L

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

.fleiss_kappa <- function(ann_df, levels, sample_col, model_col, label_col) {
  counts <- tapply(seq_len(nrow(ann_df)), ann_df[[sample_col]], function(idx) {
    table(factor(ann_df[[label_col]][idx], levels = levels))
  })
  counts_mat <- do.call(rbind, counts)

  m <- unique(rowSums(counts_mat))
  if (length(m) != 1L) {
    warning("Samples have different numbers of annotations; Fleiss' Kappa assumes a constant number of raters.")
  }
  m <- m[1]

  p_j <- colSums(counts_mat) / (nrow(counts_mat) * m)
  P_i <- (rowSums(counts_mat^2) - m) / (m * (m - 1))
  P_bar <- mean(P_i)
  P_e_bar <- sum(p_j^2)
  kappa <- if (abs(1 - P_e_bar) < .Machine$double.eps) NA_real_ else (P_bar - P_e_bar) / (1 - P_e_bar)

  list(kappa = kappa, per_item = P_i, category_proportions = p_j)
}
