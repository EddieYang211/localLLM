# --- FILE: localLLM/R/install.R ---

# Define library version and base URL
.lib_version <- "1.2.1"
.base_url <- "https://github.com/EddieYang211/localLLM/releases/download/v1.2.1/"

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

# Get platform-specific download URL
.get_download_url <- function() {
  sys <- Sys.info()["sysname"]
  arch <- Sys.info()["machine"]
  
  filename <- NULL
  if (sys == "Darwin") {
    if (arch == "arm64") filename <- "liblocalllm_macos_arm64.zip"
    # else if (arch == "x86_64") filename <- "liblocalllm_macos_x64.zip" # Future expansion
  } else if (sys == "Windows") {
    if (arch == "x86-64") filename <- "localllm_windows_x64.zip"
  } else if (sys == "Linux") {
    if (arch == "x86_64") filename <- "liblocalllm_linux_x64.zip"
  }
  
  if (is.null(filename)) {
    stop(
      "Your platform (", sys, "/", arch, ") is not currently supported. ",
      "Please open an issue on GitHub for support."
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
#' @return Returns NULL invisibly. Called for side effects.
#' @export
#' @examples
#' \dontrun{
#' # Install the backend library
#' install_localLLM()
#' }
#' @seealso \code{\link{lib_is_installed}}, \code{\link{get_lib_path}}
install_localLLM <- function() {
  if (lib_is_installed()) {
    .localllm_message("localLLM backend library is already installed.")
    return(invisible(NULL))
  }
  
  # Get user consent
  if (interactive()) {
    ans <- utils::askYesNo(
      "The localLLM C++ backend library is not installed.
      This will download pre-compiled binaries (~1MB) to your local cache.
      Do you want to proceed?",
      default = TRUE
    )
    if (!ans) {
      stop("Installation cancelled by user.", call. = FALSE)
    }
  }

  lib_dir <- .lib_path()
  if (!dir.exists(lib_dir)) {
    dir.create(lib_dir, recursive = TRUE)
  }
  
  download_url <- .get_download_url()
  dest_file <- file.path(lib_dir, basename(download_url))
  
  .localllm_message("Downloading from: ", download_url)
  tryCatch({
    utils::download.file(download_url, destfile = dest_file, mode = "wb")
  }, error = function(e) {
    stop("Failed to download backend library. Please check your internet connection.\nError: ", e$message, call. = FALSE)
  })
  
  .localllm_message("Download complete. Unzipping...")
  utils::unzip(dest_file, exdir = lib_dir)
  unlink(dest_file) # Delete zip file
  
  if (lib_is_installed()) {
    .localllm_message("localLLM backend library successfully installed to: ", lib_dir)
  } else {
    stop("Installation failed. The library file was not found after unpacking.", call. = FALSE)
  }
  
  invisible(NULL)
} 
