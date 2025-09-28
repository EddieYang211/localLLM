# localLLM Function Reference

Quick reference for the exported public API. Use `?function_name` inside R for full help pages.

## Installation and backend management
- `install_localLLM()` – download and install the prebuilt backend shared library for the current platform.
- `lib_is_installed()` – return `TRUE`/`FALSE` depending on whether the backend library is already present.
- `get_lib_path()` – absolute path to the installed shared library (errors if not installed).
- `backend_init()` / `backend_free()` – initialise or shut down the backend; usually called automatically.

## Model lifecycle
- `model_load()` – load a GGUF model from a local path or URL (includes caching logic and safety checks).
- `context_create()` – create an inference context with configurable `n_ctx`, `n_threads`, and sequence capacity.
- `tokenize()` / `detokenize()` – convert between text and token ids using the loaded model.
- `apply_chat_template()` – format a list of chat messages using the model’s built-in template.

## Generation APIs
- `generate()` – single-sequence generation with configurable sampling parameters.
- `generate_parallel()` – batch/parallel generation for multiple prompts in a single context.
- `quick_llama()` – one-line helper that handles model download, templating, and generation.
- `quick_llama_reset()` – clear cached model/context objects created by `quick_llama()`.

## Cache and download utilities
- `download_model()` – fetch a remote model into the local cache.
- `get_model_cache_dir()` / `list_cached_models()` – manage cached model artefacts.
- `tokenize_test()` – internal diagnostic function exposed for regression tests.

## Internal helpers (access with `localLLM:::`)
- `.clean_output()` – strip chat template control tokens from generated text.
- `.get_default_model()` – URL of the default GGUF model used by `quick_llama()`.
- `.detect_gpu_layers()` – heuristic for deciding how many layers to offload to GPU.
- `.ensure_model_loaded()` – cache-aware loader used internally by `quick_llama()`.

Additional examples live under `inst/examples/`; see `list.files(system.file("examples", package = "localLLM"))` for an overview.
