# localLLM

[![R-CMD-check](https://github.com/EddieYang211/localLLM/workflows/R-CMD-check/badge.svg)](https://github.com/EddieYang211/localLLM/actions)
[![CRAN status](https://www.r-pkg.org/badges/version/localLLM)](https://cran.r-project.org/package=localLLM)
[![R Package](https://img.shields.io/badge/R-package-blue.svg)](https://www.r-project.org/)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![](https://cranlogs.r-pkg.org/badges/grand-total/localLLM)](https://cran.r-project.org/package=localLLM)

**localLLM** provides an easy-to-use interface to run large language models (LLMs) directly in R. It uses the performant `llama.cpp` library as the backend and allows you to generate text and analyze data with LLM. Everything runs locally on your own machine, completely free. It also ensures reproducibility by default. Our goal is to develop it into a reliable toolkit for scientific research.

**Tutorial:** https://www.eddieyang.net/software/localLLM

---

### Installation

Getting started requires two simple steps: installing the R package from CRAN and then downloading the backend C++ library that handles the heavy computations. The `install_localLLM()` function automatically detects your operating system (Windows, macOS, Linux) to download the appropriate pre-compiled library.

```r
# 1. Install the R package from CRAN
install.packages("localLLM")

# 2. Load the package and install the backend library
library(localLLM)
install_localLLM()
```

#### Older R, or a version that is not on CRAN yet

CRAN builds binary packages only for the current and the previous R release, so on an older R `install.packages()` can install an older localLLM. For example, on R 4.4 the Windows and Apple Silicon binaries stopped at 1.2.1. Update R, or install from source or from GitHub. Both compile C++ code, so you need a toolchain: [Rtools](https://cran.r-project.org/bin/windows/Rtools/) on Windows, the Xcode Command Line Tools on macOS (`xcode-select --install`), or the usual build tools on Linux.

```r
# Current CRAN version, built from source
install.packages("localLLM", type = "source")

# A GitHub release (the R package lives in the localLLM/ subdirectory)
# install.packages("remotes")
remotes::install_github("EddieYang211/localLLM@v1.4.0", subdir = "localLLM")

# The latest development version
remotes::install_github("EddieYang211/localLLM", subdir = "localLLM")
```

Then run `library(localLLM); install_localLLM()` as above.
---

### Quick Start

You can start running an LLM using quick_llama().

```r
library(localLLM)

# Ask a question and get a response
response <- quick_llama('Classify whether the sentiment of the tweet is Positive
  or Negative.\n\nTweet: "This paper is amazing! I really like it."')

cat(response) # Output: The sentiment of this tweet is Positive.
```

### Reproducibility

By default, all generation functions in **localLLM** (`quick_llama()`, `generate()`, and `generate_parallel()`) use deterministic greedy decoding. Even when temperature > 0, results are reproducible.

```r
response1 <- quick_llama('Classify whether the sentiment of the tweet is Positive
  or Negative.\n\nTweet: "This paper is amazing! I really like it."', 
  temperature=0.9, seed=92092)

response2 <- quick_llama('Classify whether the sentiment of the tweet is Positive
  or Negative.\n\nTweet: "This paper is amazing! I really like it."', 
  temperature=0.9, seed=92092)

print(response1==response2)
```

Results also depend on the **package version**. A newer localLLM, or its llama.cpp backend, can change the output for the same model, prompt and seed (for example, 1.4.0 fixed how chat-template tokens are tokenized). Record `packageVersion("localLLM")` together with your results.

To reproduce results that were produced with an older version, install that version and its matching backend:

```r
# install.packages("remotes")
remotes::install_version("localLLM", version = "1.3.0")  # from the CRAN archive
# or from GitHub:
# remotes::install_github("EddieYang211/localLLM@v1.3.0", subdir = "localLLM")

library(localLLM)
install_localLLM()          # downloads the backend that matches this package version
packageVersion("localLLM")
```

Each package version keeps its own backend, so you can switch between versions without downloading it again. Use the same model file and, for bit-identical output, the same hardware. See the *Reproducible Output* vignette for details.

### Report bugs
Please report bugs to **xu2009@purdue.edu** with your sample
code and data file. Much appreciated!
