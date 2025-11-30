# --- FILE: localLLM/R/capacity.R ---

#' Inspect detected hardware resources
#'
#' Returns the cached system profile recorded by localLLM when the package was
#' attached. Use `refresh = TRUE` to force a re-detection.
#'
#' @param refresh When `TRUE`, forces a fresh detection rather than returning
#'   the cached profile.
#' @return A list describing the operating system, CPU cores, total RAM (bytes),
#'   GPU information (if detected) and detection timestamp.
#' @export
hardware_profile <- function(refresh = FALSE) {
  if (isTRUE(refresh)) {
    .pkg_env$system_profile <- NULL
  }
  .ensure_system_profile()
}

.ensure_system_profile <- function() {
  if (is.null(.pkg_env$system_profile)) {
    .pkg_env$system_profile <- .localllm_detect_system_profile()
  }
  .pkg_env$system_profile
}

.localllm_detect_system_profile <- function() {
  sys <- Sys.info()
  list(
    os = sys[["sysname"]],
    release = sys[["release"]],
    cpu_cores = .safe_detect_cores(),
    ram_total = .detect_total_ram_bytes(),
    gpu = .detect_gpu_info(sys[["sysname"]]),
    detected_at = Sys.time()
  )
}

.safe_detect_cores <- function() {
  cores <- NA_integer_
  try({
    cores <- parallel::detectCores()
  }, silent = TRUE)
  cores
}

.detect_total_ram_bytes <- function() {
  sysname <- Sys.info()[["sysname"]]
  if (identical(sysname, "Darwin")) {
    output <- suppressWarnings(system2("sysctl", c("-n", "hw.memsize"), stdout = TRUE))
    bytes <- suppressWarnings(as.numeric(output[1]))
    return(ifelse(is.na(bytes), NA_real_, bytes))
  }
  if (identical(sysname, "Linux")) {
    meminfo <- tryCatch(readLines("/proc/meminfo"), error = function(e) NULL)
    if (!is.null(meminfo)) {
      line <- meminfo[grepl("^MemTotal:", meminfo)]
      if (length(line)) {
        value <- as.numeric(sub("[^0-9]", "", line)) * 1024
        return(value)
      }
    }
  }
  if (.Platform$OS.type == "windows") {
    limit <- suppressWarnings(utils::memory.limit())
    if (!is.na(limit)) {
      return(limit * 1024 * 1024)
    }
  }
  NA_real_
}

.detect_gpu_info <- function(sysname) {
  info <- list(
    name = NA_character_,
    vram_bytes = NA_real_,
    source = "undetected"
  )
  if (identical(sysname, "Linux") || .Platform$OS.type == "windows") {
    output <- suppressWarnings(system2("nvidia-smi",
                                       c("--query-gpu=name,memory.total", "--format=csv,noheader"),
                                       stdout = TRUE, stderr = FALSE))
    if (length(output) && !grepl("not found", output[1], ignore.case = TRUE)) {
      parts <- strsplit(output[1], ",")[[1]]
      if (length(parts) >= 2) {
        name <- trimws(parts[1])
        mem <- suppressWarnings(as.numeric(gsub("[^0-9\\.]", "", parts[2])))
        if (!is.na(mem)) {
          info$name <- name
          info$vram_bytes <- mem * 1024 * 1024
          info$source <- "nvidia-smi"
          return(info)
        }
      }
    }
  }
  if (identical(sysname, "Darwin")) {
    profiler <- suppressWarnings(system2("/usr/sbin/system_profiler",
                                         c("SPDisplaysDataType"), stdout = TRUE, stderr = FALSE))
    if (length(profiler)) {
      vram_line <- profiler[grepl("VRAM", profiler, ignore.case = TRUE)][1]
      if (!is.na(vram_line)) {
        value <- suppressWarnings(as.numeric(gsub("[^0-9\\.]", "", vram_line)))
        if (!is.na(value)) {
          multiplier <- if (grepl("TB", vram_line, ignore.case = TRUE)) 1024^4 else 1024^3
          info$name <- trimws(sub("VRAM.*:", "", vram_line))
          info$vram_bytes <- value * multiplier
          info$source <- "system_profiler"
          return(info)
        }
      }
    }
  }
  info
}

.safety_warnings_enabled <- function() {
  isTRUE(getOption("localllm.safety_warnings", TRUE))
}

.warn_if_model_exceeds_system <- function(model_path, use_mmap, n_gpu_layers) {
  if (!.safety_warnings_enabled()) {
    return(invisible(NULL))
  }
  profile <- .ensure_system_profile()
  info <- file.info(model_path)
  size_bytes <- info$size
  if (is.na(size_bytes)) {
    return(invisible(NULL))
  }

  mmap_factor <- if (isTRUE(use_mmap)) 0.25 else 1.5
  estimated_ram <- size_bytes * mmap_factor
  ram_total <- profile$ram_total

  if (!is.na(ram_total) && estimated_ram > ram_total) {
    warning(sprintf(
      "Safety check: model '%s' (~%.1f GB) may require %.1f GB RAM but only %.1f GB detected. Consider enabling mmap or using a smaller model.",
      basename(model_path), size_bytes / 2^30, estimated_ram / 2^30, ram_total / 2^30
    ), call. = FALSE)
  } else if (!is.na(ram_total) && estimated_ram > ram_total * 0.8 && !isTRUE(use_mmap)) {
    warning(sprintf(
      "Safety check: loading '%s' without mmap may consume ~%.1f GB RAM (%.0f%% of detected memory). Set use_mmap = TRUE to reduce risk.",
      basename(model_path), estimated_ram / 2^30, 100 * estimated_ram / ram_total
    ), call. = FALSE)
  }

  gpu_info <- profile$gpu
  if (n_gpu_layers > 0) {
    if (is.null(gpu_info) || is.na(gpu_info$vram_bytes)) {
      warning("Safety check: GPU memory could not be detected, but n_gpu_layers > 0. Monitor VRAM usage manually.", call. = FALSE)
    } else {
      approx_layers <- 100
      gpu_fraction <- min(1, n_gpu_layers / approx_layers)
      gpu_need <- size_bytes * gpu_fraction
      if (gpu_need > gpu_info$vram_bytes * 0.9) {
        warning(sprintf(
          "Safety check: offloading ~%.0f layers of '%s' may require %.1f GB VRAM (detected %.1f GB). Reduce n_gpu_layers or use CPU.",
          n_gpu_layers, basename(model_path), gpu_need / 2^30, gpu_info$vram_bytes / 2^30
        ), call. = FALSE)
      }
    }
  }
  invisible(NULL)
}

.warn_if_context_large <- function(n_ctx, n_seq_max) {
  if (!.safety_warnings_enabled()) {
    return(invisible(NULL))
  }
  profile <- .ensure_system_profile()
  ram <- profile$ram_total
  if (is.na(ram)) {
    return(invisible(NULL))
  }
  if (n_ctx >= 8192 && ram < 16 * 2^30) {
    warning(sprintf(
      "Safety check: requested n_ctx = %d on a system with %.1f GB RAM. Large context windows can exhaust memory.",
      n_ctx, ram / 2^30
    ), call. = FALSE)
  } else if (n_ctx >= 4096 && n_seq_max > 1 && ram < 16 * 2^30) {
    warning(sprintf(
      "Safety check: batch with n_seq_max = %d and n_ctx = %d may exceed memory on this system (%.1f GB detected).",
      n_seq_max, n_ctx, ram / 2^30
    ), call. = FALSE)
  }
  invisible(NULL)
}

.warn_if_prompt_near_limit <- function(tokens, max_tokens, n_ctx) {
  if (!.safety_warnings_enabled() || is.null(n_ctx) || is.na(n_ctx)) {
    return(invisible(NULL))
  }
  prompt_tokens <- length(tokens)
  projected <- prompt_tokens + max_tokens
  if (projected > n_ctx) {
    warning(sprintf(
      "Safety check: prompt (%d tokens) + max_tokens (%d) exceeds context size (%d). Generation may truncate or crash.",
      prompt_tokens, max_tokens, n_ctx
    ), call. = FALSE)
  } else if (prompt_tokens / n_ctx > 0.85) {
    warning(sprintf(
      "Safety check: prompt already uses %0.0f%% of context window (%d/%d tokens). Consider reducing prompt or increasing n_ctx.",
      100 * prompt_tokens / n_ctx, prompt_tokens, n_ctx
    ), call. = FALSE)
  }
  invisible(NULL)
}
