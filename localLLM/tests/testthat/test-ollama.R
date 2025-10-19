test_that("list_ollama_models returns valid data.frame structure", {
  # This test works whether or not Ollama is actually installed
  res <- list_ollama_models()

  # Check it's a data.frame
  expect_s3_class(res, "data.frame")
  expect_named(res, c("name", "path", "size_mb", "size_gb", "size_bytes",
                      "sha256", "modified", "source", "tag", "model"))

  # Check column types
  expect_type(res$name, "character")
  expect_type(res$path, "character")
  expect_type(res$size_mb, "double")
  expect_type(res$size_gb, "double")
  expect_type(res$size_bytes, "double")
  expect_type(res$sha256, "character")
  expect_s3_class(res$modified, "POSIXct")
  expect_type(res$source, "character")
  expect_type(res$tag, "character")
  expect_type(res$model, "character")

  # If models found, verify values
  if (nrow(res) > 0) {
    expect_equal(res$source[1], "ollama")
    expect_true(file.exists(res$path[1]))
    expect_gt(res$size_bytes[1], 0)
  }
})

test_that("list_ollama_models detects manifest-mapped GGUF blobs", {
  old_env <- Sys.getenv("OLLAMA_MODELS", unset = NA_character_)
  on.exit({
    if (is.na(old_env)) {
      Sys.unsetenv("OLLAMA_MODELS")
    } else {
      Sys.setenv(OLLAMA_MODELS = old_env)
    }
  }, add = TRUE)

  tmp_root <- file.path(tempdir(), paste0("ollama_test_", as.integer(Sys.time())))
  manifest_dir <- file.path(tmp_root, "manifests", "registry.ollama.ai", "library", "foo")
  blob_dir <- file.path(tmp_root, "blobs")

  dir.create(manifest_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(blob_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)

  manifest <- list(
    schemaVersion = 2,
    mediaType = "application/vnd.oci.image.manifest.v1+json",
    layers = list(
      list(
        mediaType = "application/vnd.ollama.image.model",
        digest = "sha256:abc123"
      )
    )
  )

  manifest_path <- file.path(manifest_dir, "latest")
  writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), manifest_path)

  blob_path <- file.path(blob_dir, "sha256-abc123")
  writeBin(charToRaw("GGUF"), blob_path)

  orphan_blob <- file.path(blob_dir, "sha256-deadbeef")
  writeBin(charToRaw("GGUF"), orphan_blob)

  Sys.setenv(OLLAMA_MODELS = tmp_root)

  old_opts <- options(
    localllm.ollama_min_size_mb = 0,
    localllm.ollama_verify = FALSE
  )
  on.exit(options(old_opts), add = TRUE)

  res <- list_ollama_models()
  expect_gte(nrow(res), 2L)

  expect_true("foo" %in% res$name)

  expect_true(any(grepl("deadbeef", substr(res$sha256, 1, 8))))

  foo_row <- res[res$name == "foo", , drop = FALSE]
  expect_true(endsWith(foo_row$path[1], "sha256-abc123"))

  resolved <- localLLM:::`.resolve_model_path`("ollama:foo",
                                               verify_integrity = FALSE)
  expect_equal(resolved, foo_row$path[1])
})
