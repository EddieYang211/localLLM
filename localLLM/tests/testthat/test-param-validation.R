# Argument validation added in 1.4.0. CRAN-safe: no backend, model or network is
# needed -- the backend check is mocked out and every case stops before the first
# .Call() into the backend.

fake_context <- structure(list(), class = "localllm_context")

test_that("model_metadata is exported", {
  # exists() would also find unexported functions here, since tests run in the namespace
  expect_true("model_metadata" %in% getNamespaceExports("localLLM"))
})

test_that("generate() and generate_parallel() reject invalid repeat_last_n", {
  with_mocked_bindings(.ensure_backend_loaded = function() invisible(TRUE), .package = "localLLM", {
    for (bad in list(-1L, -64, NA_integer_, "64", c(1L, 2L))) {
      expect_error(generate(fake_context, "hi", repeat_last_n = bad),
                   "repeat_last_n must be a single non-negative number")
      expect_error(generate_parallel(fake_context, c("a", "b"), repeat_last_n = bad),
                   "repeat_last_n must be a single non-negative number")
    }
  })
})

test_that("quick_llama() rejects invalid repeat_last_n before loading a model", {
  expect_error(quick_llama("hi", repeat_last_n = -1L),
               "repeat_last_n must be a single non-negative number")
})

test_that("model_load() rejects use_mmap / use_mlock that are not TRUE or FALSE", {
  with_mocked_bindings(.ensure_backend_loaded = function() invisible(TRUE), .package = "localLLM", {
    expect_error(model_load("model.gguf", use_mmap = NA), "use_mmap must be TRUE or FALSE")
    expect_error(model_load("model.gguf", use_mmap = "yes"), "use_mmap must be TRUE or FALSE")
    expect_error(model_load("model.gguf", use_mlock = NA), "use_mlock must be TRUE or FALSE")
    expect_error(model_load("model.gguf", use_mlock = c(TRUE, FALSE)), "use_mlock must be TRUE or FALSE")
  })
})

test_that("model_load() expands ~ before the path reaches the backend", {
  with_mocked_bindings(
    .ensure_backend_loaded = function() invisible(TRUE),
    .resolve_model_path = function(...) "~/models/model.gguf",
    .check_model_memory_requirements = function(model_path) {
      stop("backend got: ", model_path, call. = FALSE)
    },
    .package = "localLLM",
    expect_error(model_load("~/models/model.gguf"),
                 paste0("backend got: ", path.expand("~/models/model.gguf")), fixed = TRUE)
  )
})
