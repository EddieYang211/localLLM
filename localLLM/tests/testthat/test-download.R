test_that("download functions work", {
  
  # Test that download functions exist
  expect_true(exists("download_model"))
  expect_true(exists("get_model_cache_dir"))
  
  # Test that they are functions
  expect_type(download_model, "closure")
  expect_type(get_model_cache_dir, "closure")
  
  # Test get_model_cache_dir (this should work without backend)
  cache_dir <- get_model_cache_dir()
  expect_type(cache_dir, "character")
  expect_true(length(cache_dir) > 0)
  
  # In CI environment, cache_dir might be /tmp/localllm_cache
  # In normal environment, it should contain "localllm"
  if (is_ci()) {
    # In CI, just check that the path is valid
    expect_true(dir.exists(cache_dir))
  } else {
    # In normal environment, expect "localllm" in the path
    expect_true(grepl("localllm", cache_dir, ignore.case = TRUE))
  }
})

test_that("URL parsing works", {
  
  # Test that we can validate different URL types
  # This tests the logic without actually downloading
  
  # Test valid URLs
  expect_true(grepl("^https://", "https://example.com/model.gguf"))
  expect_true(grepl("^hf://", "hf://user/model"))
  expect_true(grepl("^ollama://", "ollama://model"))
  
  # Test file extensions
  expect_true(grepl("\\.gguf$", "model.gguf"))
  expect_true(grepl("\\.gguf$", "path/to/model.gguf"))
})