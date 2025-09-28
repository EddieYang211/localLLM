# Simple installation script for localLLM package
# Run this script to install the package locally

# Install devtools if not already installed
if (!require(devtools, quietly = TRUE)) {
  install.packages("devtools")
  library(devtools)
}

# Install the localLLM package from local directory
devtools::install("/Users/yaoshengleo/Desktop/localLLM_4_project/localLLM")

# Load the package and install backend
library(localLLM)
install_localLLM()

# Verify installation
if (lib_is_installed()) {
  message("✅ Installation successful! Package is ready to use.")
  message("Try: quick_llama('Hello, world!')")
} else {
  message("❌ Installation failed. Please check error messages above.")
}
