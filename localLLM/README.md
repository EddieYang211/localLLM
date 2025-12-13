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

By default , all generation functions in **localLLM** (`quick_llama()`, `generate()`, and `generate_parallel()`) use deterministic greedy decoding. Even when temperature > 0, results are reproducibile.

```r
response1 <- quick_llama('Classify whether the sentiment of the tweet is Positive
  or Negative.\n\nTweet: "This paper is amazing! I really like it."', 
  temperature=0.9, seed=92092)

response2 <- quick_llama('Classify whether the sentiment of the tweet is Positive
  or Negative.\n\nTweet: "This paper is amazing! I really like it."', 
  temperature=0.9, seed=92092)

print(response1==response2)
```

### Report bugs
Please report bugs to **xu2009@purdue.edu** with your sample
code and data file. Much appreciated!
