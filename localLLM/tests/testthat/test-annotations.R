test_that("explore works with predictors", {
  dataset <- data.frame(
    doc_id = c("doc_a", "doc_b", "doc_c"),
    text = c("Doc A", "Doc B", "Doc C"),
    truth = c("POS", "NEG", "POS"),
    stringsAsFactors = FALSE
  )
  predictor_a <- function(prompts, data, spec) rep("POS", length(prompts))
  predictor_b <- function(prompts, data, spec) rep(c("POS", "NEG", "POS"), length.out = length(prompts))

  models <- list(
    list(id = "model_a", predictor = predictor_a),
    list(id = "model_b", predictor = predictor_b)
  )

  builder <- function(spec) {
    data.frame(
      sample_id = dataset$doc_id,
      prompt = paste(spec$id, dataset$text),
      truth = dataset$truth,
      stringsAsFactors = FALSE
    )
  }

  res <- explore(
    models = models,
    prompts = builder,
    keep_prompts = TRUE
  )

  expect_true(is.data.frame(res$annotations))
  expect_equal(nrow(res$annotations), nrow(dataset) * length(models))
  expect_true(all(c("sample_id", "model_id", "label", "truth", "prompt") %in% names(res$annotations)))
  expect_false(is.factor(res$annotations$label))
})

test_that("template prompt builder generates structured prompts", {
  dataset <- data.frame(
    doc_id = c("doc_a", "doc_b"),
    text = c("Doc A text", "Doc B text"),
    stringsAsFactors = FALSE
  )

  # Use proper field names - they render as-is
  template <- list(
    "Annotation Task" = "Classify whether the text is positive or negative.",
    "Coding Rules" = "Return only POS or NEG. Respond in JSON.",
    "Examples" = data.frame(
      text = c("I love it", "Hate it"),
      label = c("POS", "NEG"),
      stringsAsFactors = FALSE
    ),
    "Target Text" = dataset$text,
    sample_id = dataset$doc_id
  )

  models <- list(list(id = "tmpl", predictor = function(prompts, ...) rep("POS", length(prompts))))

  res <- explore(models = models,
                 prompts = template,
                 keep_prompts = TRUE)

  expect_equal(nrow(res$annotations), nrow(dataset))
  # Field names render as-is
 expect_true(all(grepl("## Annotation Task", res$annotations$prompt, fixed = TRUE)))
  expect_true(all(grepl("## Target Text", res$annotations$prompt, fixed = TRUE)))
  expect_true(all(mapply(function(txt, prompt) grepl(txt, prompt, fixed = TRUE),
                         dataset$text,
                         res$annotations$prompt)))
})

test_that("character vector prompt builder passes prompts through", {
  ready <- c("Prompt 1", "Prompt 2", "Prompt 3")
  models <- list(list(id = "vec", predictor = function(prompts, ...) prompts))

  res <- explore(models = models,
                 prompts = ready,
                 keep_prompts = TRUE)

  prompts_seen <- res$annotations$prompt[res$annotations$model_id == "vec"]
  expect_equal(sort(unique(prompts_seen)), sort(ready))
})

test_that("confusion matrices and reliability stats are returned", {
  annotations <- data.frame(
    sample_id = rep(1:3, times = 2),
    model_id = rep(c("m1", "m2"), each = 3),
    label = c("A", "B", "A", "A", "B", "B"),
    truth = rep(c("A", "B", "A"), times = 2),
    stringsAsFactors = FALSE
  )

  cms <- compute_confusion_matrices(annotations)
  expect_true("vs_gold" %in% names(cms))
  expect_length(cms$vs_gold, 2)

  rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  expect_true("cohen" %in% names(rel))
  expect_true("krippendorff" %in% names(rel))
  expect_equal(ncol(rel$cohen), 5)
})

test_that("annotation sink streams chunks to CSV", {
  tmp <- tempfile(fileext = ".csv")
  sink_fn <- annotation_sink_csv(tmp)
  data <- data.frame(id = c(1, 2), text = c("Doc A", "Doc B"), stringsAsFactors = FALSE)
  models <- list(list(id = "mock", predictor = function(prompts, ...) rep("X", length(prompts))))

  builder <- function(spec) data.frame(sample_id = data$id, prompt = data$text, stringsAsFactors = FALSE)

  res <- explore(models = models,
                 prompts = builder,
                 sink = sink_fn)

  expect_null(res$annotations)
  expect_true(file.exists(tmp))
  streamed <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(streamed), nrow(data))
  expect_equal(unique(streamed$model_id), "mock")
})
