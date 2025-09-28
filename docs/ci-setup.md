# R CMD check CI Configuration

This note summarises how the GitHub Actions pipelines for **localLLM** are organised and which constraints they address.

## Project characteristics

- Bridges R and C++ (Rcpp interface talking to `llama.cpp`)
- Ships prebuilt backend binaries that must be downloaded during tests
- Loads shared libraries at runtime via `dlopen`
- Needs to exercise macOS (arm64), Linux (x86_64), and Windows (x86_64)
- Performs memory-intensive operations when full models are involved

## Workflow outline

### `R-CMD-check`
Runs the standard `rcmdcheck` matrix.
- Matrix covers macOS, Linux, Windows
- Multiple R versions (devel, release, oldrel-1)
- Installs system requirements and pre-release binary backends before running `R CMD check`

### `extended-tests`
Optional job that performs smoke tests against the real backend: installing the binary bundle, basic generation, and tolerant error handling.

### `package-structure`
Light-weight validation of DESCRIPTION/NAMESPACE, presence of required files, and the ability to load package metadata without building the full backend.

## Environment configuration

```yaml
env:
  GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
  R_KEEP_PKG_SOURCE: yes
  _R_CHECK_INTERNET_: true
  _R_CHECK_TESTS_NLINES_: 0
  LOCALLLM_CACHE_DIR: ${{ runner.temp }}/localllm_cache
  LOCALLLM_TEST_MODE: true
```

## System dependencies

macOS (arm64):
```bash
brew install cmake
xcode-select --install || true
```

Linux (Ubuntu):
```bash
sudo apt-get install -y \
  cmake build-essential \
  libcurl4-openssl-dev libssl-dev \
  libxml2-dev libfontconfig1-dev \
  libharfbuzz-dev libfribidi-dev \
  libfreetype6-dev libpng-dev \
  libtiff5-dev libjpeg-dev \
  pciutils
```

Windows: rely on Rtools and the MSYS2 toolchain provided by the GH Action runner.

## Test strategy in CI

The helper functions in `tests/testthat/helper-ci.R` gate expensive or backend-dependent tests. Common helpers include:

- `is_ci()` – detect CI execution
- `skip_if_ci()` – skip interactive-only tests
- `skip_if_no_backend()` – skip when the shared library is unavailable
- `skip_if_no_network()` – skip download tests offline
- `skip_if_memory_intensive()` – guard memory-heavy scenarios

### Layers of automated tests

1. **Core smoke tests** (`test-basic.R`) verify exported functions, parameter validation, and configuration helpers.
2. **Integration tests** (`test-integration.R`) check backend installation, mocked objects, and download / caching helpers.

## Troubleshooting tips

- **Compilation failures** – ensure system requirements are installed, confirm the Rcpp toolchain, and inspect CMake output.
- **Backend download failures** – check the release URL, confirm the GitHub token, and ensure `_R_CHECK_INTERNET_` is set.
- **Memory pressure** – lower `n_ctx` or limit CI scenarios to mock-based tests only.

Keep these notes in sync with `.github/workflows/*.yml` whenever the CI matrix or installation steps change.
