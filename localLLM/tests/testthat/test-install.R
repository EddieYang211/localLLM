test_that("installation functions work", {
  
  # Test lib_is_installed function (should work without backend)
  expect_type(lib_is_installed(), "logical")
  
  # Test get_lib_path function only if backend is available
  if (lib_is_installed()) {
    lib_path <- get_lib_path()
    expect_type(lib_path, "character")
    expect_true(length(lib_path) > 0)
    expect_true(grepl("localllm", lib_path, ignore.case = TRUE))
  } else {
    # In CI environment, backend may not be installed
    # Just test that the function exists and can be called
    expect_error(get_lib_path(), "backend library is not installed")
  }
})

test_that("installation parameters are valid", {

  # Test that we can check installation status
  expect_silent({
    is_installed <- lib_is_installed()
    expect_type(is_installed, "logical")
  })

  # Test that installation directory can be created
  temp_dir <- tempdir()
  expect_true(dir.exists(temp_dir))
})