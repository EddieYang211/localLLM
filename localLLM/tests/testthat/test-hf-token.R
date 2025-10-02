test_that("set_hf_token updates environment", {
  old <- Sys.getenv("HF_TOKEN", unset = NA)
  on.exit({
    if (is.na(old)) {
      Sys.unsetenv("HF_TOKEN")
    } else {
      Sys.setenv(HF_TOKEN = old)
    }
  }, add = TRUE)

  expect_invisible(set_hf_token("hf_dummy_token"))
  expect_equal(Sys.getenv("HF_TOKEN"), "hf_dummy_token")
})

test_that("set_hf_token can persist to file", {
  tmp <- tempfile(fileext = "Renviron")
  on.exit(unlink(tmp, force = TRUE), add = TRUE)

  set_hf_token("hf_persist_token", persist = TRUE, renviron_path = tmp)
  expect_true(file.exists(tmp))
  lines <- readLines(tmp)
  expect_true(any(grepl("^HF_TOKEN=hf_persist_token$", lines)))
})

test_that(".with_hf_token scopes environment changes", {
  old <- Sys.getenv("HF_TOKEN", unset = NA)
  on.exit({
    if (is.na(old)) {
      Sys.unsetenv("HF_TOKEN")
    } else {
      Sys.setenv(HF_TOKEN = old)
    }
  }, add = TRUE)
  Sys.setenv(HF_TOKEN = "hf_original")

  localLLM:::.with_hf_token("hf_mock", {
    expect_equal(Sys.getenv("HF_TOKEN"), "hf_mock")
  })

  expect_equal(Sys.getenv("HF_TOKEN"), "hf_original")
})
