# Basic tests for localLLM package
# These tests focus on package structure and basic functionality

test_that("package loads correctly", {
  expect_true(exists("quick_llama"))
  expect_true(exists("model_load"))
  expect_true(exists("install_localLLM"))
  expect_true(exists("backend_init"))
})

test_that("installation functions exist and work", {
  # Test that installation functions are callable
  expect_function(lib_is_installed)
  expect_function(install_localLLM)
  
  # Test library detection (should work even if library is not installed)
  expect_type(lib_is_installed(), "logical")
})

test_that("utility functions work", {
  skip_if_ci("Skipping utility tests in CI")
  
  # Test cache directory creation
  cache_dir <- get_model_cache_dir()
  expect_type(cache_dir, "character")
  expect_true(dir.exists(cache_dir))
})

test_that("quick_llama parameter validation", {
  skip_if_windows("Skipping on Windows to avoid potential segfaults")
  
  # Test parameter validation without actually running inference
  expect_error(quick_llama(), "Prompt cannot be empty")
  expect_error(quick_llama(NULL), "Prompt cannot be empty")
  expect_error(quick_llama(""), "Prompt cannot be empty")
})

test_that("backend installation works in CI", {
  skip_if_not(is_ci(), "Only run in CI environment")
  
  # Try to install backend - should not error even if it fails
  result <- try_install_backend()
  expect_type(result, "logical")
  
  # If installation succeeded, test basic backend functionality
  if (result && lib_is_installed()) {
    expect_true(lib_is_installed())
    
    # Try to get library path
    expect_no_error({
      lib_path <- get_lib_path()
      expect_type(lib_path, "character")
    })
  }
})

test_that("environment variable handling", {
  # Test cache directory environment variable
  old_cache <- Sys.getenv("LOCALLLM_CACHE_DIR", unset = NA)
  
  test_dir <- file.path(tempdir(), "test_cache")
  Sys.setenv(LOCALLLM_CACHE_DIR = test_dir)
  
  cache_dir <- get_model_cache_dir()
  expect_equal(cache_dir, test_dir)
  expect_true(dir.exists(cache_dir))
  
  # Restore original environment
  if (is.na(old_cache)) {
    Sys.unsetenv("LOCALLLM_CACHE_DIR")
  } else {
    Sys.setenv(LOCALLLM_CACHE_DIR = old_cache)
  }
  
  # Clean up test directory
  unlink(test_dir, recursive = TRUE)
})

test_that("URL detection works correctly", {
  # Test URL detection function (if accessible)
  if (exists(".is_url")) {
    expect_true(.is_url("https://example.com/model.gguf"))
    expect_true(.is_url("hf://model/file.gguf"))
    expect_false(.is_url("/local/path/model.gguf"))
    expect_false(.is_url("model.gguf"))
    expect_false(.is_url(""))
    expect_false(.is_url(NULL))
  }
})

test_that("model cache path generation", {
  # Test cache path generation (if accessible)
  if (exists(".get_cache_path")) {
    cache_path <- .get_cache_path("https://example.com/model.gguf")
    expect_type(cache_path, "character")
    expect_true(grepl("\\.gguf$", cache_path))
    expect_true(grepl("model\\.gguf", basename(cache_path)))
  }
})

test_that("GPU layer detection works", {
  # Test GPU layer detection function (if accessible)
  if (exists(".detect_gpu_layers")) {
    gpu_layers <- .detect_gpu_layers()
    expect_type(gpu_layers, "integer")
    expect_gte(gpu_layers, 0L)
  }
})

test_that("quick_llama_reset works", {
  # Test that reset function exists and runs without error
  expect_function(quick_llama_reset)
  expect_no_error(quick_llama_reset())
})

test_that("backend functions exist", {
  # Test that all expected backend interface functions exist
  expected_functions <- c(
    "backend_init",
    "backend_free", 
    "model_load",
    "context_create",
    "tokenize",
    "detokenize",
    "generate",
    "generate_parallel",
    "apply_chat_template"
  )
  
  for (func_name in expected_functions) {
    expect_true(exists(func_name), 
                info = paste("Function", func_name, "should exist"))
  }
})

test_that("mock objects work for testing", {
  # Test mock object creation for CI testing
  mock_model <- create_mock_model()
  expect_s3_class(mock_model, "localllm_model")
  expect_true(is_mock_object(mock_model))
  
  mock_context <- create_mock_context()
  expect_s3_class(mock_context, "localllm_context")
  expect_true(is_mock_object(mock_context))
})
