test_that("lib_is_installed detects platform-specific libraries", {
  tmp <- tempfile("localllm-lib")
  dir.create(tmp)
  with_mocked_bindings(Sys.info = function() c(sysname = "Darwin"), .package = "base", {
    with_mocked_bindings(.lib_path = function() tmp, .package = "localLLM", {
      expect_false(lib_is_installed())
      file.create(file.path(tmp, "liblocalllm.dylib"))
      expect_true(lib_is_installed())
    })
  })
  unlink(tmp, recursive = TRUE)
})

test_that("get_lib_path locates library files", {
  tmp <- tempfile("localllm-lib-path")
  dir.create(file.path(tmp, "lib"), recursive = TRUE)
  dylib <- file.path(tmp, "liblocalllm.dylib")
  file.create(dylib)
  with_mocked_bindings(Sys.info = function() c(sysname = "Darwin"), .package = "base", {
    with_mocked_bindings(.lib_path = function() tmp, .package = "localLLM", {
      expect_equal(get_lib_path(), dylib)
    })
  })
  unlink(tmp, recursive = TRUE)
})
