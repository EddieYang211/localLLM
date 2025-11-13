test_that("document_start/end capture explore events", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  document_start(tmp)
  on.exit(try(document_end(), silent = TRUE), add = TRUE)

  models <- list(list(id = "mock", predictor = function(prompts, ...) rep("X", length(prompts))))
  builder <- function(spec) data.frame(sample_id = 1:2, prompt = c("Doc A", "Doc B"), stringsAsFactors = FALSE)

  explore(models = models, prompt_builder = builder)

  path <- document_end()
  expect_equal(normalizePath(path, winslash = "/", mustWork = TRUE), normalizePath(tmp, winslash = "/", mustWork = TRUE))

  log_lines <- readLines(tmp)
  expect_true(any(grepl("document_start", log_lines, fixed = TRUE)))
  expect_true(any(grepl("explore_model", log_lines, fixed = TRUE)))
  expect_true(any(grepl("document_end", log_lines, fixed = TRUE)))
})

test_that("document_start prevents nested sessions", {
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  document_start(tmp)
  on.exit(try(document_end(), silent = TRUE), add = TRUE)

  expect_error(document_start(tmp), "already been called")

  document_end()
})
