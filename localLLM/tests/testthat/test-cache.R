test_that("cache listing and resolution behave as expected", {
  original_env <- Sys.getenv("LOCALLLM_CACHE_DIR", unset = NA)
  cache_dir <- file.path(tempdir(), "localllm-cache-test")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  Sys.setenv(LOCALLLM_CACHE_DIR = cache_dir)
  on.exit({
    if (is.na(original_env)) {
      Sys.unsetenv("LOCALLLM_CACHE_DIR")
    } else {
      Sys.setenv("LOCALLLM_CACHE_DIR" = original_env)
    }
    options(localllm.cache_selection = NULL)
    unlink(cache_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  expect_message(empty <- list_cached_models(), "No cached models")
  expect_equal(nrow(empty), 0)

  model_a <- file.path(cache_dir, "alpha-model.gguf")
  model_b <- file.path(cache_dir, "beta-model.gguf")
  model_c <- file.path(cache_dir, "gamma-model.gguf")

  file.create(model_a)
  Sys.sleep(1)
  file.create(model_b)
  Sys.sleep(1)
  file.create(model_c)

  listing <- list_cached_models()
  expect_s3_class(listing, "data.frame")
  expect_true(all(c("name", "path", "size_bytes", "modified") %in% names(listing)))
  expect_equal(nrow(listing), 3)

  resolved_single <- localLLM:::.resolve_model_name("alpha", cache_dir = NULL)
  expect_equal(basename(resolved_single), "alpha-model.gguf")

  options(localllm.cache_selection = 2)
  matches <- localLLM:::.list_cached_models(NULL)
  matches <- matches[grepl("model", matches$name, ignore.case = TRUE), , drop = FALSE]
  matches <- matches[order(matches$modified, decreasing = TRUE), , drop = FALSE]
  resolved_multi <- localLLM:::.resolve_model_name("model", cache_dir = NULL)
  expect_equal(normalizePath(resolved_multi, winslash = "/", mustWork = FALSE),
               normalizePath(matches$path[2], winslash = "/", mustWork = FALSE))

  options(localllm.cache_selection = NULL)
  expect_null(localLLM:::.resolve_model_name("does-not-exist", cache_dir = NULL))
})
