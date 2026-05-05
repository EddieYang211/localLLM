# CRAN Submission Comments — localLLM 1.3.0

## Resubmission

This is a resubmission. The previous accepted version was 1.2.1.

Changes since 1.2.1 are documented in NEWS.md. Key additions:

- GPU acceleration on all platforms: Metal (macOS arm64 + x86_64),
  Vulkan (Windows + Linux), CPU fallback. `install_localLLM()` now
  auto-detects the appropriate binary.
- Linux aarch64 (Raspberry Pi / ARM64) binary support.
- New `model_metadata()` function returning GGUF key-value metadata.
- `apply_chat_template()` Jinja2 fallback for Gemma 4 and other
  models not on the C API whitelist.
- Stop-token fixes for ChatML (OLMo) and Llama 3.x models.
- Various verbosity and error-handling fixes.
- llama.cpp backend upgraded from b7825 to b8766 (~940 new commits).

## Runtime binary download

The package downloads a platform-specific compiled backend binary via
`install_localLLM()`. This download is user-initiated, explicit, and
documented in the README and vignette. The binary is too large and
too platform-specific to bundle in the source package; the same
approach is used by packages such as 'torch' and 'llama'.

The download URL points to GitHub Releases on the package repository
(https://github.com/EddieYang211/localLLM/releases). Users can
inspect or override the URL. No network access occurs at package
load time; the library loads the binary from a local path only after
the user has run `install_localLLM()`.

## Test environments

- macOS 26.3.1, Apple M3 Pro (arm64), R 4.4.1 — local machine
- macOS (latest), R release — GitHub Actions CI
- Windows (latest), R release — GitHub Actions CI
- Ubuntu (latest), R release — GitHub Actions CI
- Ubuntu (latest), R devel — GitHub Actions CI
- Ubuntu (latest), R oldrel-1 — GitHub Actions CI

## R CMD check results

```
R CMD build localLLM
R CMD check --as-cran localLLM_1.3.0.tar.gz
```

**Status: 1 NOTE, 0 WARNINGs, 0 ERRORs**

The single NOTE:

```
checking for future file timestamps ... NOTE
unable to verify current time
```

This NOTE is caused by a local network restriction that prevents
the check from reaching a time server. It does not appear on CRAN
check servers and is not reproducible outside this environment.
