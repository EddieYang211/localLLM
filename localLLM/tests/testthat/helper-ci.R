# Helper functions for CI testing environment
# This file provides utilities to handle testing in CI environments
# where network access, memory, or model loading might be limited

#' Check if we're running in a CI environment
is_ci <- function() {
  ci_vars <- c("CI", "CONTINUOUS_INTEGRATION", "GITHUB_ACTIONS", "TRAVIS", "APPVEYOR")
  any(sapply(ci_vars, function(x) Sys.getenv(x) != ""))
}

#' Check if we're in test mode (set by environment variable)
is_test_mode <- function() {
  Sys.getenv("LOCALLLM_TEST_MODE", "FALSE") == "TRUE"
}

#' Check if extended tests should be run
should_run_extended_tests <- function() {
  Sys.getenv("LOCALLLM_EXTENDED_TESTS", "FALSE") == "TRUE"
}

#' Skip test if in CI environment
skip_if_ci <- function(message = "Skipping test in CI environment") {
  if (is_ci()) {
    testthat::skip(message)
  }
}

#' Skip test if on Windows platform (to avoid segfaults)
skip_if_windows <- function(message = "Skipping test on Windows platform") {
  if (Sys.info()["sysname"] == "Windows") {
    testthat::skip(message)
  }
}

#' Skip test if backend library is not available
skip_if_no_backend <- function() {
  if (!lib_is_installed()) {
    testthat::skip("Backend library not installed")
  }
}

#' Skip test if network is not available or in CI
skip_if_no_network <- function() {
  if (is_ci() || is_test_mode()) {
    testthat::skip("Skipping network-dependent test")
  }
  
  # Try a simple network check
  tryCatch({
    con <- url("https://www.google.com", open = "r")
    close(con)
  }, error = function(e) {
    testthat::skip("Network not available")
  })
}

#' Skip test if it requires large memory or model loading
skip_if_memory_intensive <- function() {
  if (is_ci() || is_test_mode()) {
    testthat::skip("Skipping memory-intensive test")
  }
}

#' Get a mock model response for testing
get_mock_response <- function(prompt) {
  paste0("Mock response for: ", substr(prompt, 1, 50), 
         if (nchar(prompt) > 50) "..." else "")
}

#' Set up minimal test environment
setup_test_env <- function() {
  # Set test mode environment variable
  Sys.setenv(LOCALLLM_TEST_MODE = "TRUE")
  
  # Create a temporary cache directory for tests
  temp_cache <- file.path(tempdir(), "localllm_test_cache")
  if (!dir.exists(temp_cache)) {
    dir.create(temp_cache, recursive = TRUE)
  }
  Sys.setenv(LOCALLLM_CACHE_DIR = temp_cache)
  
  invisible(NULL)
}

#' Clean up test environment
cleanup_test_env <- function() {
  # Clean up temporary cache
  temp_cache <- Sys.getenv("LOCALLLM_CACHE_DIR", "")
  if (nchar(temp_cache) > 0 && dir.exists(temp_cache)) {
    unlink(temp_cache, recursive = TRUE)
  }
  
  # Reset environment variables
  Sys.unsetenv("LOCALLLM_TEST_MODE")
  Sys.unsetenv("LOCALLLM_CACHE_DIR")
  
  invisible(NULL)
}

#' Try to install backend with CI-specific handling
try_install_backend <- function() {
  if (is_ci() || is_test_mode()) {
    # In CI, we may have pre-installed the backend or it may not be available
    # Try to install but don't fail if it doesn't work
    tryCatch({
      install_localLLM()
      return(TRUE)
    }, error = function(e) {
      message("Backend installation failed in CI environment: ", e$message)
      return(FALSE)
    })
  } else {
    # In interactive mode, try normal installation
    install_localLLM()
    return(TRUE)
  }
}

#' Create a minimal mock model object for testing
#' This is used when the real backend is not available
create_mock_model <- function() {
  # Create a mock external pointer
  mock_ptr <- new.env()
  class(mock_ptr) <- "localllm_model"
  attr(mock_ptr, "mock") <- TRUE
  return(mock_ptr)
}

#' Create a minimal mock context object for testing
create_mock_context <- function() {
  mock_ptr <- new.env()
  class(mock_ptr) <- "localllm_context"
  attr(mock_ptr, "mock") <- TRUE
  return(mock_ptr)
}

#' Check if an object is a mock object
is_mock_object <- function(obj) {
  !is.null(attr(obj, "mock", exact = TRUE))
}

#' Expect that an object is a function (helper for testthat)
expect_function <- function(object, info = NULL, label = NULL) {
  if (is.null(label)) {
    label <- deparse(substitute(object))
  }
  if (is.null(info)) {
    info <- paste(label, "is not a function")
  }
  testthat::expect_true(is.function(object), info = info)
}

# Set up test environment when this file is loaded
if (is_ci() || is_test_mode()) {
  setup_test_env()
}
