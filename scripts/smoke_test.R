# End-to-end smoke test for a downloaded backend release artifact.
# Used by .github/workflows/smoke-test.yml; also runs locally.
#
# Usage: Rscript scripts/smoke_test.R <backend_dir> <model.gguf>
#   <backend_dir> contains lib/<liblocalllm.so|liblocalllm.dylib|localllm.dll>
#   <model.gguf>  a small chat model with a ChatML template (SmolLM2-135M-Instruct)
#
# Exits with status 1 if any check fails. CPU only (n_gpu_layers = 0), so it runs
# on CI runners without a GPU even for the Vulkan/Metal builds.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: Rscript smoke_test.R <backend_dir> <model.gguf>")
backend_dir <- normalizePath(args[1], mustWork = TRUE)
model_path  <- normalizePath(args[2], mustWork = TRUE)

# Point the package at the artifact under test instead of the install_localLLM() location,
# before library() attaches and loads a backend.
loadNamespace("localLLM")
assignInNamespace(".lib_path", function() backend_dir, ns = "localLLM")
suppressMessages(library(localLLM))

failures <- character()
check <- function(ok, what) {
  cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", what))
  if (!isTRUE(ok)) failures <<- c(failures, what)
}

cat("localLLM", as.character(packageVersion("localLLM")), "| backend:", localLLM:::.pkg_env$lib[["path"]], "\n")
check(!is.null(localLLM:::.pkg_env$lib), "backend library loaded")

model <- model_load(model_path, n_gpu_layers = 0L, verbosity = 0L)
check(nzchar(model_metadata(model)["general.architecture"]), "model_metadata() is exported and works")

# PR #7: chat-template markers must tokenize as single special tokens
check(length(tokenize(model, "<|im_start|>", add_special = FALSE)) == 1L,
      "special tokens are parsed (<|im_start|> is 1 token)")

ask <- function(q) apply_chat_template(model, list(list(role = "user", content = q)))
prompts <- c(ask("What is the capital of France?"),
             ask("What is the capital of France?"),   # identical: exercises the shared-prefix path
             ask("Name a primary color."))

ctx <- context_create(model, n_ctx = 1024L, n_seq_max = 3L, verbosity = 0L)
seq_out <- vapply(prompts, function(p) generate(ctx, p, max_tokens = 16L, temperature = 0, seed = 42L),
                  "", USE.NAMES = FALSE)
# n_seq_max = 3 -> 2 prompts per C call, so 3 prompts give a 2 + 1 split (single-prompt leftover)
par_out <- generate_parallel(ctx, prompts, max_tokens = 16L, temperature = 0, seed = 42L, progress = FALSE)

for (i in seq_along(prompts)) {
  cat(sprintf("  #%d generate():          %s\n  #%d generate_parallel(): %s\n",
              i, gsub("\n", " / ", seq_out[i]), i, gsub("\n", " / ", par_out[i])))
}
check(all(nzchar(trimws(seq_out))), "generate() returns non-empty text")
check(!any(grepl("^\\[ERROR\\]", par_out)) && all(nzchar(trimws(par_out))),
      "generate_parallel() returns non-empty text without [ERROR]")
check(length(par_out) == length(seq_out) && all(as.character(par_out) == seq_out),
      "generate_parallel() matches generate() at temperature 0")
check(!any(grepl("im_end|im_start", c(seq_out, par_out))), "no chat-template markers leak into output")

if (length(failures)) {
  cat(sprintf("\n%d check(s) failed:\n", length(failures)), paste0("  - ", failures, "\n"), sep = "")
  quit(status = 1L)
}
cat("\nAll smoke checks passed.\n")
