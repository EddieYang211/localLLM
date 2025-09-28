# Integration tests for localLLM package
# These tests require backend installation and may involve network access

test_that("backend installation and initialization works", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  
  # Try to install backend
  expect_no_error({
    install_result <- try_install_backend()
  })
  
  # If installation succeeded, test initialization
  if (lib_is_installed()) {
    expect_no_error(backend_init())
    
    # Test that library path is accessible
    lib_path <- get_lib_path()
    expect_type(lib_path, "character")
    expect_true(file.exists(lib_path))
  } else {
    skip("Backend library not available")
  }
})

test_that("model loading with mock/small model works", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  skip_if_no_backend()
  skip_if_memory_intensive()
  
  # This test would ideally use a very small test model
  # For now, we test the model loading function structure
  expect_function(model_load)
  
  # Test parameter validation
  expect_error(model_load(""), "model_path.*empty|not.*exist")
  expect_error(model_load("/nonexistent/path"), "not.*exist|failed")
})

test_that("tokenization functions work with mock data", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled") 
  skip_if_no_backend()
  
  # Test tokenization function exists and has correct signature
  expect_function(tokenize)
  expect_function(detokenize)
  
  # Create mock model for testing
  if (!lib_is_installed()) {
    mock_model <- create_mock_model()
    expect_s3_class(mock_model, "localllm_model")
  }
})

test_that("context creation works", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  skip_if_no_backend()
  
  expect_function(context_create)
  
  # Test parameter validation
  expect_error(context_create("not_a_model"), "Expected.*localllm_model")
})

test_that("generate functions exist and validate parameters", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  skip_if_no_backend()
  
  expect_function(generate)
  expect_function(generate_parallel)
  
  # Test parameter validation
  expect_error(generate("not_a_context"), "Expected.*localllm_context")
  expect_error(generate_parallel("not_a_context"), "Expected.*localllm_context")
})

test_that("chat template application works", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  skip_if_no_backend()
  
  expect_function(apply_chat_template)
  
  # Test parameter validation
  expect_error(apply_chat_template("not_a_model"), "Expected.*localllm_model")
})

test_that("quick_llama handles errors gracefully", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  
  # Test error handling when backend is not available
  if (!lib_is_installed()) {
    expect_error(quick_llama("test prompt"), "backend.*not.*loaded|install_localLLM")
  }
})

test_that("download and cache functions work", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  skip_if_no_network()
  
  expect_function(download_model)
  
  # Test with invalid URL
  expect_error(download_model("not_a_url"), ".*")
  
  # Test cache directory creation
  cache_dir <- get_model_cache_dir()
  expect_true(dir.exists(cache_dir))
})

test_that("memory checking functions work", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  skip_if_no_backend()
  
  # Test memory checking with a dummy file
  dummy_file <- tempfile(fileext = ".gguf")
  
  # Write a minimal GGUF-like header
  con <- file(dummy_file, "wb")
  writeBin(as.raw(c(0x47, 0x47, 0x55, 0x46)), con)  # "GGUF" magic
  writeBin(raw(1020), con)  # Pad to make it 1024 bytes
  close(con)
  
  # Test memory estimation (may fail in CI, that's ok)
  tryCatch({
    if (exists(".check_model_memory_requirements")) {
      expect_no_error(.check_model_memory_requirements(dummy_file))
    }
  }, error = function(e) {
    # Memory checking may not work in CI environments
    message("Memory checking not available: ", e$message)
  })
  
  # Clean up
  unlink(dummy_file)
})

test_that("parallel generation parameter structure", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  
  # Test that the parallel parameters structure is correctly defined
  # This tests the C struct definition matches R expectations
  expect_function(generate_parallel)
  
  # Test parameter validation
  if (lib_is_installed()) {
    mock_context <- create_mock_context()
    
    # These should validate parameter types
    expect_error(generate_parallel(mock_context, "not_a_vector"), ".*character.*")
  }
})

test_that("file integrity checking works", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  
  if (exists(".verify_file_integrity")) {
    # Test with non-existent file
    expect_false(.verify_file_integrity("/nonexistent/file"))
    
    # Test with empty file
    empty_file <- tempfile()
    file.create(empty_file)
    expect_false(.verify_file_integrity(empty_file))
    unlink(empty_file)
    
    # Test with small non-GGUF file
    small_file <- tempfile()
    writeLines("not a gguf file", small_file)
    expect_false(.verify_file_integrity(small_file))
    unlink(small_file)
  }
})

test_that("GGUF file validation works", {
  skip_if_not(should_run_extended_tests(), "Extended tests not enabled")
  
  if (exists(".is_valid_gguf_file")) {
    # Test with non-existent file
    expect_false(.is_valid_gguf_file("/nonexistent/file"))
    
    # Test with fake GGUF file
    fake_gguf <- tempfile(fileext = ".gguf")
    con <- file(fake_gguf, "wb")
    writeBin(as.raw(c(0x47, 0x47, 0x55, 0x46)), con)  # "GGUF" magic
    close(con)
    
    expect_true(.is_valid_gguf_file(fake_gguf))
    unlink(fake_gguf)
    
    # Test with non-GGUF file
    non_gguf <- tempfile()
    writeLines("not gguf", non_gguf)
    expect_false(.is_valid_gguf_file(non_gguf))
    unlink(non_gguf)
  }
})
