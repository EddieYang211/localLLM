# Test script comparing localLLM's intercoder reliability implementations
# against the irr package (the standard R package for reliability statistics)
#
# Run with: testthat::test_file("tests/testthat/test-irr-comparison.R")

# Skip all tests if irr package is not available
skip_if_not_installed("irr")

# Helper to convert localLLM annotation format to irr format
# irr expects a matrix where rows = subjects, columns = raters
.to_irr_matrix <- function(ann_df, sample_col = "sample_id",
                           model_col = "model_id", label_col = "label") {
  wide <- stats::reshape(
    ann_df[, c(sample_col, model_col, label_col)],
    idvar = sample_col,
    timevar = model_col,
    direction = "wide"
  )
  mat <- as.matrix(wide[, -1, drop = FALSE])
  colnames(mat) <- sub(paste0("^", label_col, "\\."), "", colnames(mat))
  mat
}

# =============================================================================
# COHEN'S KAPPA TESTS
# =============================================================================

test_that("Cohen's Kappa matches irr::kappa2 - perfect agreement", {
  annotations <- data.frame(
    sample_id = rep(1:5, times = 2),
    model_id = rep(c("m1", "m2"), each = 5),
    label = c("A", "B", "A", "B", "A", "A", "B", "A", "B", "A"),
    stringsAsFactors = FALSE
  )

  # localLLM result

local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_kappa <- as.numeric(local_rel$cohen[1, "kappa"])

# irr result
  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kappa2(mat)
  irr_kappa <- irr_result$value

  expect_equal(local_kappa, irr_kappa, tolerance = 1e-10)
})

test_that("Cohen's Kappa matches irr::kappa2 - partial agreement", {
  annotations <- data.frame(
    sample_id = rep(1:6, times = 2),
    model_id = rep(c("m1", "m2"), each = 6),
    label = c("A", "B", "A", "B", "A", "B",   # m1
              "A", "B", "B", "A", "A", "B"),  # m2 (2 disagreements)
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_kappa <- as.numeric(local_rel$cohen[1, "kappa"])

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kappa2(mat)
  irr_kappa <- irr_result$value

  expect_equal(local_kappa, irr_kappa, tolerance = 1e-10)
})

test_that("Cohen's Kappa matches irr::kappa2 - no agreement beyond chance", {
  # Construct a case where observed = expected (kappa = 0)
  annotations <- data.frame(
    sample_id = rep(1:4, times = 2),
    model_id = rep(c("m1", "m2"), each = 4),
    label = c("A", "A", "B", "B",   # m1: 2 A, 2 B
              "A", "B", "A", "B"),  # m2: 2 A, 2 B, but different pattern
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_kappa <- as.numeric(local_rel$cohen[1, "kappa"])

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kappa2(mat)
  irr_kappa <- irr_result$value

  expect_equal(local_kappa, irr_kappa, tolerance = 1e-10)
})

test_that("Cohen's Kappa matches irr::kappa2 - multiple categories", {
  annotations <- data.frame(
    sample_id = rep(1:9, times = 2),
    model_id = rep(c("m1", "m2"), each = 9),
    label = c("A", "B", "C", "A", "B", "C", "A", "B", "C",  # m1
              "A", "B", "C", "A", "C", "B", "B", "B", "C"), # m2
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B", "C"))
  local_kappa <- as.numeric(local_rel$cohen[1, "kappa"])

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kappa2(mat)
  irr_kappa <- irr_result$value

  expect_equal(local_kappa, irr_kappa, tolerance = 1e-10)
})

test_that("Cohen's Kappa matches irr::kappa2 - three raters pairwise", {
  annotations <- data.frame(
    sample_id = rep(1:5, times = 3),
    model_id = rep(c("m1", "m2", "m3"), each = 5),
    label = c("A", "B", "A", "B", "A",   # m1
              "A", "B", "B", "B", "A",   # m2
              "A", "A", "A", "B", "B"),  # m3
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))

  # Should have 3 pairwise comparisons
  expect_equal(nrow(local_rel$cohen), 3)

  mat <- .to_irr_matrix(annotations)

  # Check each pair
  for (i in seq_len(nrow(local_rel$cohen))) {
    pair_a <- local_rel$cohen[i, "model_a"]
    pair_b <- local_rel$cohen[i, "model_b"]
    local_kappa <- as.numeric(local_rel$cohen[i, "kappa"])

    irr_result <- irr::kappa2(mat[, c(pair_a, pair_b)])
    expect_equal(local_kappa, irr_result$value, tolerance = 1e-10,
                 label = sprintf("Pair %s vs %s", pair_a, pair_b))
  }
})

# =============================================================================
# KRIPPENDORFF'S ALPHA TESTS
# =============================================================================

test_that("Krippendorff's Alpha matches irr::kripp.alpha - 2 raters perfect", {
annotations <- data.frame(
    sample_id = rep(1:5, times = 2),
    model_id = rep(c("m1", "m2"), each = 5),
    label = c("A", "B", "A", "B", "A",
              "A", "B", "A", "B", "A"),
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Krippendorff's Alpha matches irr::kripp.alpha - 2 raters partial", {
  annotations <- data.frame(
    sample_id = rep(1:6, times = 2),
    model_id = rep(c("m1", "m2"), each = 6),
    label = c("A", "B", "A", "B", "A", "B",
              "A", "B", "B", "A", "A", "B"),  # 2 disagreements
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Krippendorff's Alpha matches irr::kripp.alpha - 3 raters", {
  annotations <- data.frame(
    sample_id = rep(1:5, times = 3),
    model_id = rep(c("m1", "m2", "m3"), each = 5),
    label = c("A", "B", "A", "B", "A",
              "A", "B", "B", "B", "A",
              "A", "A", "A", "B", "B"),
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Krippendorff's Alpha matches irr::kripp.alpha - multiple categories", {
  annotations <- data.frame(
    sample_id = rep(1:8, times = 2),
    model_id = rep(c("m1", "m2"), each = 8),
    label = c("A", "B", "C", "A", "B", "C", "A", "B",
              "A", "B", "C", "B", "B", "A", "A", "C"),
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B", "C"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Krippendorff's Alpha matches irr::kripp.alpha - with missing data", {
  # Create data with some missing values
  annotations <- data.frame(
    sample_id = c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 1, 2, 3, 4),
    model_id = c(rep("m1", 5), rep("m2", 5), rep("m3", 4)),  # m3 missing sample 5
    label = c("A", "B", "A", "B", "A",
              "A", "B", "B", "B", "A",
              "A", "A", "A", "B"),
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_alpha <- local_rel$krippendorff$alpha

  # For irr, missing data is represented as NA in the matrix
  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Krippendorff's Alpha matches irr::kripp.alpha - 4 raters", {
  annotations <- data.frame(
    sample_id = rep(1:6, times = 4),
    model_id = rep(c("m1", "m2", "m3", "m4"), each = 6),
    label = c("A", "B", "A", "B", "A", "B",
              "A", "B", "A", "A", "A", "B",
              "A", "B", "B", "B", "A", "B",
              "B", "B", "A", "B", "A", "A"),
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Krippendorff's Alpha handles complete disagreement", {
  # Systematic disagreement pattern
  annotations <- data.frame(
    sample_id = rep(1:4, times = 2),
    model_id = rep(c("m1", "m2"), each = 4),
    label = c("A", "A", "B", "B",
              "B", "B", "A", "A"),  # Complete reversal
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

# =============================================================================
# EDGE CASES
# =============================================================================

test_that("Both metrics handle single category gracefully", {
  annotations <- data.frame(
    sample_id = rep(1:5, times = 2),
    model_id = rep(c("m1", "m2"), each = 5),
    label = rep("A", 10),  # All same category
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B"))

  # Perfect agreement should give kappa = 1 (or NA if pe = 1)
  # Krippendorff's alpha = 1 for perfect agreement
  expect_true(is.na(local_rel$cohen[1, "kappa"]) ||
              as.numeric(local_rel$cohen[1, "kappa"]) == 1)
  expect_equal(local_rel$krippendorff$alpha, 1)
})

test_that("intercoder_reliability returns correct structure", {
  annotations <- data.frame(
    sample_id = rep(1:5, times = 2),
    model_id = rep(c("m1", "m2"), each = 5),
    label = c("A", "B", "A", "B", "A", "A", "B", "B", "B", "A"),
    stringsAsFactors = FALSE
  )

  result <- intercoder_reliability(annotations, label_levels = c("A", "B"))

  # Check structure
expect_true("cohen" %in% names(result))
  expect_true("krippendorff" %in% names(result))

  # Cohen should have model_a, model_b, kappa, observed, expected
  expect_true(all(c("model_a", "model_b", "kappa", "observed", "expected") %in%
                  colnames(result$cohen)))

  # Krippendorff should have alpha, per_item, category_proportions
  expect_true(all(c("alpha", "per_item", "category_proportions") %in%
                  names(result$krippendorff)))
})

test_that("Krippendorff's Alpha matches irr::kripp.alpha - 2 raters partial with 3 categories", {
  annotations <- data.frame(
    sample_id = rep(1:6, times = 2),
    model_id = rep(c("m1", "m2"), each = 6),
    label = c("A", "B", "A", "B", "A", "B",
              "A", "B", "B", "A", "A", "C"),  # 2 disagreements
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B", "C"))
  local_alpha <- local_rel$krippendorff$alpha

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kripp.alpha(t(mat), method = "nominal")
  irr_alpha <- irr_result$value

  expect_equal(local_alpha, irr_alpha, tolerance = 1e-10)
})

test_that("Cohen's Kappa matches irr::kappa2 - 2 raters partial with 3 categories", {
  annotations <- data.frame(
    sample_id = rep(1:6, times = 2),
    model_id = rep(c("m1", "m2"), each = 6),
    label = c("A", "B", "A", "B", "A", "B",
              "A", "B", "B", "A", "A", "C"),  # 2 disagreements
    stringsAsFactors = FALSE
  )

  local_rel <- intercoder_reliability(annotations, label_levels = c("A", "B", "C"))
  local_kappa <- as.numeric(local_rel$cohen[1, "kappa"])

  mat <- .to_irr_matrix(annotations)
  irr_result <- irr::kappa2(mat)
  irr_kappa <- irr_result$value

  expect_equal(local_kappa, irr_kappa, tolerance = 1e-10)
})