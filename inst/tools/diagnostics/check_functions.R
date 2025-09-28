#!/usr/bin/env Rscript

# Inspect exported symbols from the localLLM package.
library(localLLM)

cat("=== Exported functions in localLLM ===\n\n")

exported_functions <- sort(ls("package:localLLM"))
cat(paste(exported_functions, collapse = "\n"), "\n\n", sep = "")

cat("Searching for template-related helpers...\n")
template_functions <- exported_functions[grepl("template", exported_functions, ignore.case = TRUE)]
if (length(template_functions)) {
  cat(paste("  -", template_functions), sep = "\n")
} else {
  cat("  (none found)\n")
}

cat("\nSearching for chat/format helpers...\n")
chat_functions <- exported_functions[grepl("chat|format|apply", exported_functions, ignore.case = TRUE)]
if (length(chat_functions)) {
  cat(paste("  -", chat_functions), sep = "\n")
} else {
  cat("  (none found)\n")
}
