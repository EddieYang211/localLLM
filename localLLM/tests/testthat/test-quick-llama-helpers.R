test_that(".clean_output removes trailing special tokens", {
  raw <- "Hello<|end_of_turn|>"
  expect_equal(localLLM:::.clean_output(raw), "Hello")
})

test_that(".clean_output handles non character inputs", {
  expect_equal(localLLM:::.clean_output(NULL), NULL)
  expect_equal(localLLM:::.clean_output(123), 123)
})

test_that(".clean_output strips llama 3 control tokens", {
  expect_equal(localLLM:::.clean_output("Business<|start_header|>assistant"), "Business")
  expect_equal(localLLM:::.clean_output("Summary<|end_header|>"), "Summary")
})

test_that(".clean_output strips fullwidth control tokens", {
  expect_equal(localLLM:::.clean_output("Answer<｜Assistant｜>"), "Answer")
})

test_that(".get_default_model returns valid URL", {
  url <- localLLM:::.get_default_model()
  expect_true(is.character(url) && length(url) == 1)
  expect_true(grepl("^https://", url))
})

test_that(".detect_gpu_layers heuristics respect platform", {
  with_mocked_bindings(Sys.info = function() c(sysname = "Darwin"), .package = "base", {
    expect_equal(localLLM:::.detect_gpu_layers(), 999L)
  })
  with_mocked_bindings(Sys.info = function() c(sysname = "Linux"), Sys.which = function(x) if (x == "nvidia-smi") "/usr/bin/nvidia-smi" else "", .package = "base", {
    expect_equal(localLLM:::.detect_gpu_layers(), 999L)
  })
  with_mocked_bindings(Sys.info = function() c(sysname = "Linux"), Sys.which = function(x) "", .package = "base", {
    expect_equal(localLLM:::.detect_gpu_layers(), 0L)
  })
})

test_that(".ensure_model_loaded caches model/context", {
  calls <- list(model = 0L, context = 0L)
  with_mocked_bindings(
    model_load = function(...) {
      calls$model <<- calls$model + 1L
      structure(list(), class = "localllm_model")
    },
    context_create = function(...) {
      calls$context <<- calls$context + 1L
      structure(list(), class = "localllm_context")
    },
    .package = "localLLM",
    {
      rm(list = ls(envir = localLLM:::.quick_llama_env), envir = localLLM:::.quick_llama_env)
      localLLM:::.ensure_model_loaded("dummy", 0L, 128L, 1L, verbosity = 0L)
      expect_equal(calls, list(model = 1L, context = 1L))
      localLLM:::.ensure_model_loaded("dummy", 0L, 128L, 1L, verbosity = 0L)
      expect_equal(calls, list(model = 1L, context = 1L))
    }
  )
})

test_that("quick_llama clean flag controls post-processing", {
  skip("Skipping: cannot modify locked binding .quick_llama_env")
})
