test_that("validate bundles confusion and reliability", {
  annotations <- data.frame(
    sample_id = rep(1:3, times = 2),
    model_id = rep(c("m1", "m2"), each = 3),
    label = c("pos", "neg", "pos", "pos", "neg", "neg"),
    truth = c("pos", "neg", "pos", "pos", "pos", "neg"),
    stringsAsFactors = FALSE
  )

  res <- validate(annotations)

  expect_named(res, c("confusion", "reliability"))
  expect_true(is.list(res$confusion))
  expect_true(is.list(res$reliability))
  expect_true("vs_gold" %in% names(res$confusion))
  expect_true("pairwise" %in% names(res$confusion))
  expect_equal(dim(res$confusion$vs_gold$m1), c(2, 2))
  expect_equal(nrow(res$reliability$cohen), 1)
})

test_that("validate respects include flags", {
  annotations <- data.frame(
    sample_id = rep(1:3, times = 2),
    model_id = rep(c("m1", "m2"), each = 3),
    label = c("pos", "neg", "pos", "pos", "neg", "neg"),
    truth = c("pos", "neg", "pos", "pos", "pos", "neg"),
    stringsAsFactors = FALSE
  )

  confusion_only <- validate(annotations, include_reliability = FALSE)
  expect_named(confusion_only, "confusion")

  reliability_only <- validate(annotations, include_confusion = FALSE)
  expect_named(reliability_only, "reliability")
})
