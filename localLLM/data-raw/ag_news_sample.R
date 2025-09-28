# Script to generate the ag_news_sample dataset shipped with the package.
# Source data: textdata::dataset_ag_news() (AG News Topic Classification dataset).

suppressPackageStartupMessages({
  library(dplyr)
  library(textdata)
})

# Load full dataset (approximately 120k rows)
ag_news <- textdata::dataset_ag_news()

# Sample 25 observations per class (100 rows total), keeping key columns
set.seed(123)
ag_news_sample <- ag_news %>%
  group_by(class) %>%
  slice_sample(n = 25, replace = FALSE) %>%
  ungroup() %>%
  select(class, title, description)

# Ensure plain data.frame to avoid tibble dependency when loading
ag_news_sample <- as.data.frame(ag_news_sample, stringsAsFactors = FALSE)

# Save to package data directory
output_path <- file.path("data", "ag_news_sample.rda")
if (!dir.exists(dirname(output_path))) {
  dir.create(dirname(output_path), recursive = TRUE)
}

save(ag_news_sample, file = output_path, compress = "xz")
message("Saved ag_news_sample to ", normalizePath(output_path))
