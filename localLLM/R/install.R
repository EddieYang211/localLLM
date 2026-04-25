# --- FILE: localLLM/R/install.R ---

# Define library version and base URL
.lib_version <- "1.3.0"
.base_url <- "https://github.com/EddieYang211/localLLM/releases/download/v1.3.0/"

# Get path for local library storage
.lib_path <- function() {
  path <- tools::R_user_dir("localLLM", which = "data")
  # Include version number in path for future upgrades
  file.path(path, .lib_version) 
}

#' Check if Backend Library is Installed
#'
#' Checks whether the localLLM backend library has been downloaded and installed.
#'
#' @return Logical value indicating whether the backend library is installed.
#' @export
#' @examples
#' # Check if backend library is installed
#' if (lib_is_installed()) {
#'   message("Backend library is ready")
#' } else {
#'   message("Please run install_localLLM() first")
#' }
#' @seealso \code{\link{install_localLLM}}, \code{\link{get_lib_path}}
lib_is_installed <- function() {
  path <- .lib_path()
  # Check if platform-specific library file exists
  sysname <- Sys.info()["sysname"]
  
  if (sysname == "Darwin") {
    # On macOS, look for any dylib file
    lib_files <- list.files(path, pattern = "\\.dylib$", recursive = TRUE)
    return(length(lib_files) > 0)
  } else {
    lib_file <- if (sysname == "Windows") "localllm.dll" else "liblocalllm.so"
    # Check both root directory and lib/ subdirectory (for zip structure compatibility)
    return(file.exists(file.path(path, lib_file)) || file.exists(file.path(path, "lib", lib_file)))
  }
}

#' Get Backend Library Path
#'
#' Returns the full path to the installed localLLM backend library.
#'
#' @return Character string containing the path to the backend library file.
#' @details This function will throw an error if the backend library is not installed.
#'   Use \code{\link{lib_is_installed}} to check installation status first.
#' @export
#' @examples
#' \dontrun{
#' # Get the library path (only if installed)
#' if (lib_is_installed()) {
#'   lib_path <- get_lib_path()
#'   message("Library is at: ", lib_path)
#' }
#' }
#' @seealso \code{\link{lib_is_installed}}, \code{\link{install_localLLM}}
get_lib_path <- function() {
  if (!lib_is_installed()) {
    stop("localLLM backend library is not installed. Please run install_localLLM() first.", call. = FALSE)
  }
  
  path <- .lib_path()
  sysname <- Sys.info()["sysname"]
  
  if (sysname == "Darwin") {
    # On macOS, find the first dylib file
    lib_files <- list.files(path, pattern = "\\.dylib$", recursive = TRUE, full.names = TRUE)
    if (length(lib_files) == 0) {
      stop("Library files not found after installation check passed.", call. = FALSE)
    }
    return(lib_files[1])  # Return the first found dylib file
  } else {
    lib_file <- if (sysname == "Windows") "localllm.dll" else "liblocalllm.so"
    # Check root directory first, then lib/ subdirectory
    root_path <- file.path(path, lib_file)
    lib_subdir_path <- file.path(path, "lib", lib_file)
    
    if (file.exists(root_path)) {
      return(root_path)
    } else if (file.exists(lib_subdir_path)) {
      return(lib_subdir_path)
    } else {
      stop("Library file not found after installation check passed.", call. = FALSE)
    }
  }
}

# Detect Vulkan runtime on Windows: vulkan-1.dll is installed by any modern GPU driver
.detect_vulkan_windows <- function() {
  if (.Platform$OS.type != "windows") return(FALSE)
  file.exists(file.path(Sys.getenv("SystemRoot"), "System32", "vulkan-1.dll"))
}

# Detect a hardware Vulkan GPU on Linux.
# Requires both (a) the Vulkan loader and (b) a hardware ICD config file.
# The ICD check rules out lavapipe (Mesa software renderer), which installs
# libvulkan.so.1 but provides no GPU acceleration.
.detect_vulkan_linux <- function() {
  if (Sys.info()["sysname"] != "Linux") return(FALSE)

  # Check for the Vulkan loader in standard locations
  vulkan_paths <- c(
    "/usr/lib/x86_64-linux-gnu/libvulkan.so.1",
    "/usr/lib/libvulkan.so.1",
    "/usr/lib64/libvulkan.so.1",
    "/usr/local/lib/libvulkan.so.1"
  )
  has_loader <- any(file.exists(vulkan_paths))
  if (!has_loader) {
    # Fallback: ldconfig handles non-standard paths (e.g. NVIDIA on Fedora)
    ldconfig_out <- tryCatch(
      system("ldconfig -p 2>/dev/null", intern = TRUE, ignore.stderr = TRUE),
      error   = function(e) character(0),
      warning = function(w) character(0)
    )
    has_loader <- any(grepl("libvulkan\\.so\\.1", ldconfig_out))
  }
  if (!has_loader) return(FALSE)

  # Require a hardware ICD — rules out software-only Vulkan (lavapipe)
  icd_paths <- c(
    "/usr/share/vulkan/icd.d/nvidia_icd.json",
    "/usr/share/vulkan/icd.d/radeon_icd.x86_64.json",
    "/usr/share/vulkan/icd.d/intel_icd.x86_64.json",
    "/etc/vulkan/icd.d/nvidia_icd.json"
  )
  any(file.exists(icd_paths))
}

# Get platform-specific download URL
.get_download_url <- function(use_gpu = NULL) {
  sys  <- Sys.info()["sysname"]
  arch <- Sys.info()["machine"]

  filename <- NULL
  if (sys == "Darwin") {
    if (arch == "arm64")       filename <- "liblocalllm_macos_arm64.zip"
    else if (arch == "x86_64") filename <- "liblocalllm_macos_x64.zip"
  } else if (sys == "Windows") {
    if (arch == "x86-64") {
      gpu <- if (is.null(use_gpu)) .detect_vulkan_windows() else isTRUE(use_gpu)
      if (gpu) {
        filename <- "localllm_windows_x64_vulkan.zip"
        .localllm_message("Vulkan GPU detected — using GPU-accelerated build.")
      } else {
        filename <- "localllm_windows_x64.zip"
      }
    }
  } else if (sys == "Linux") {
    if (arch == "x86_64") {
      gpu <- if (is.null(use_gpu)) .detect_vulkan_linux() else isTRUE(use_gpu)
      if (gpu) {
        filename <- "liblocalllm_linux_x64_vulkan.zip"
        .localllm_message("Vulkan GPU detected — using GPU-accelerated build.")
      } else {
        filename <- "liblocalllm_linux_x64.zip"
      }
    }
  }

  if (is.null(filename)) {
    stop(
      "Your platform (", sys, "/", arch, ") is not currently supported. ",
      "Please open an issue on GitHub for support.",
      call. = FALSE
    )
  }

  paste0(.base_url, filename)
}

#' Install localLLM Backend Library
#'
#' This function downloads and installs the pre-compiled C++ backend library
#' required for the localLLM package to function.
#'
#' @details This function downloads platform-specific pre-compiled binaries from GitHub releases.
#'   The backend library is stored in the user's data directory and loaded at runtime.
#'   Internet connection is required for the initial download.
#'
#'   On Windows and Linux, GPU support is auto-detected: if a Vulkan-capable GPU driver
#'   is found, the GPU-accelerated build is downloaded automatically. Use
#'   \code{force_cpu = TRUE} to override this and install the CPU build instead.
#'
#'   macOS always downloads the Metal-enabled build (both Apple Silicon and Intel).
#'
#' @param force_cpu Logical. If \code{TRUE}, always download the CPU-only build even
#'   when a GPU is detected. Default \code{FALSE}.
#' @param force_reinstall Logical. If \code{TRUE}, remove any existing installation
#'   and re-download. Useful for switching from a CPU build to a GPU build after
#'   installing a GPU driver. Default \code{FALSE}.
#' @return Returns NULL invisibly. Called for side effects.
#' @export
#' @examples
#' \dontrun{
#' # Standard install (auto-detects GPU)
#' install_localLLM()
#'
#' # Force CPU build
#' install_localLLM(force_cpu = TRUE)
#'
#' # Reinstall after adding a GPU driver
#' install_localLLM(force_reinstall = TRUE)
#' }
#' @seealso \code{\link{lib_is_installed}}, \code{\link{get_lib_path}}
install_localLLM <- function(force_cpu = FALSE, force_reinstall = FALSE) {
  if (lib_is_installed() && !force_reinstall) {
    .localllm_message("localLLM backend library is already installed.")
    return(invisible(NULL))
  }

  if (lib_is_installed() && force_reinstall) {
    .localllm_message("Removing existing installation for reinstall...")
    unlink(.lib_path(), recursive = TRUE)
  }

  # Get user consent
  if (interactive()) {
    ans <- utils::askYesNo(
      "The localLLM C++ backend library is not installed.
      This will download pre-compiled binaries (~1MB) to your local cache.
      Do you want to proceed?",
      default = TRUE
    )
    if (!isTRUE(ans)) {
      stop("Installation cancelled by user.", call. = FALSE)
    }
  }

  lib_dir <- .lib_path()
  if (!dir.exists(lib_dir)) {
    dir.create(lib_dir, recursive = TRUE)
  }

  gpu_hint     <- if (force_cpu) FALSE else NULL
  download_url <- .get_download_url(use_gpu = gpu_hint)
  dest_file    <- file.path(lib_dir, basename(download_url))

  .localllm_message("Downloading from: ", download_url)
  tryCatch({
    utils::download.file(download_url, destfile = dest_file, mode = "wb")
  }, error = function(e) {
    stop("Failed to download backend library. Please check your internet connection.\nError: ",
         e$message, call. = FALSE)
  })

  .localllm_message("Download complete. Unzipping...")
  utils::unzip(dest_file, exdir = lib_dir)
  unlink(dest_file)

  if (lib_is_installed()) {
    .localllm_message("localLLM backend library successfully installed to: ", lib_dir)
  } else {
    stop("Installation failed. The library file was not found after unpacking.", call. = FALSE)
  }

  invisible(NULL)
}
