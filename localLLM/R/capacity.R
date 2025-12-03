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
    cores = NA_integer_,
    source = "undetected"
  )
  if (identical(sysname, "Linux") || .Platform$OS.type == "windows") {
    # Try NVIDIA first
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

    # Try AMD GPU via rocm-smi (Linux)
    if (identical(sysname, "Linux")) {
      rocm_output <- suppressWarnings(system2("rocm-smi",
                                              c("--showmeminfo", "vram", "--csv"),
                                              stdout = TRUE, stderr = FALSE))
      if (length(rocm_output) > 1 && !grepl("not found", rocm_output[1], ignore.case = TRUE)) {
        # Parse rocm-smi output for VRAM
        vram_line <- rocm_output[grepl("GPU\\[", rocm_output)][1]
        if (!is.na(vram_line)) {
          mem_match <- regmatches(vram_line, regexpr("[0-9]+", vram_line))
          if (length(mem_match) > 0) {
            mem_mb <- suppressWarnings(as.numeric(mem_match[1]))
            if (!is.na(mem_mb)) {
              info$name <- "AMD GPU"
              info$vram_bytes <- mem_mb * 1024 * 1024
              info$source <- "rocm-smi"
              return(info)
            }
          }
        }
      }

      # Try lspci for AMD GPU name
      lspci_output <- suppressWarnings(system2("lspci", stdout = TRUE, stderr = FALSE))
      if (length(lspci_output)) {
        amd_line <- lspci_output[grepl("VGA.*AMD|VGA.*ATI|VGA.*Radeon", lspci_output, ignore.case = TRUE)][1]
        if (!is.na(amd_line)) {
          gpu_name <- trimws(sub(".*VGA[^:]*:\\s*", "", amd_line))
          info$name <- gpu_name
          info$source <- "lspci (AMD, VRAM unknown)"
          return(info)
        }
      }
    }

    # Try AMD GPU via Windows registry or wmic
    if (.Platform$OS.type == "windows") {
      wmic_output <- suppressWarnings(system2("wmic",
                                              c("path", "win32_VideoController", "get", "name,AdapterRAM"),
                                              stdout = TRUE, stderr = FALSE))
      if (length(wmic_output) > 1) {
        # Parse wmic output for AMD GPU
        amd_lines <- wmic_output[grepl("AMD|ATI|Radeon", wmic_output, ignore.case = TRUE)]
        if (length(amd_lines) > 0) {
          line <- amd_lines[1]
          parts <- strsplit(trimws(line), "\\s{2,}")[[1]]
          if (length(parts) >= 2) {
            name <- trimws(parts[1])
            mem_bytes <- suppressWarnings(as.numeric(parts[2]))
            if (!is.na(mem_bytes) && mem_bytes > 0) {
              info$name <- name
              info$vram_bytes <- mem_bytes
              info$source <- "wmic"
              return(info)
            }
          }
        }
      }
    }

    # Try Intel integrated GPU detection
    if (identical(sysname, "Linux")) {
      lspci_output <- suppressWarnings(system2("lspci", stdout = TRUE, stderr = FALSE))
      if (length(lspci_output)) {
        intel_line <- lspci_output[grepl("VGA.*Intel", lspci_output, ignore.case = TRUE)][1]
        if (!is.na(intel_line)) {
          gpu_name <- trimws(sub(".*VGA[^:]*:\\s*", "", intel_line))
          info$name <- gpu_name
          info$source <- "lspci (Intel integrated, shared memory)"
          return(info)
        }
      }
    }

    if (.Platform$OS.type == "windows") {
      wmic_output <- suppressWarnings(system2("wmic",
                                              c("path", "win32_VideoController", "get", "name"),
                                              stdout = TRUE, stderr = FALSE))
      if (length(wmic_output) > 1) {
        intel_lines <- wmic_output[grepl("Intel.*Graphics|Intel.*UHD|Intel.*Iris", wmic_output, ignore.case = TRUE)]
        if (length(intel_lines) > 0) {
          name <- trimws(intel_lines[1])
          info$name <- name
          info$source <- "wmic (Intel integrated, shared memory)"
          return(info)
        }
      }
    }
  }
  if (identical(sysname, "Darwin")) {
    profiler <- suppressWarnings(system2("/usr/sbin/system_profiler",
                                         c("SPDisplaysDataType"), stdout = TRUE, stderr = FALSE))
    if (length(profiler)) {
      # Try to detect Apple Silicon GPU
      chipset_line <- profiler[grepl("Chipset Model:", profiler, ignore.case = TRUE)][1]
      cores_line <- profiler[grepl("Total Number of Cores:", profiler, ignore.case = TRUE)][1]

      if (!is.na(chipset_line)) {
        chipset <- trimws(sub(".*Chipset Model:\\s*", "", chipset_line))
        if (grepl("Apple M[0-9]", chipset, ignore.case = TRUE)) {
          # Apple Silicon detected - uses unified memory
          info$name <- chipset
          info$source <- "system_profiler (unified memory)"
          if (!is.na(cores_line)) {
            cores <- suppressWarnings(as.integer(gsub("[^0-9]", "", cores_line)))
            if (!is.na(cores)) {
              info$cores <- cores
            }
          }
          # For Apple Silicon, VRAM = RAM (unified memory architecture)
          # We'll leave vram_bytes as NA to indicate unified memory
          return(info)
        }
      }

      # Traditional discrete GPU with VRAM (NVIDIA, AMD, etc.)
      vram_line <- profiler[grepl("VRAM", profiler, ignore.case = TRUE)][1]
      if (!is.na(vram_line)) {
        value <- suppressWarnings(as.numeric(gsub("[^0-9\\.]", "", vram_line)))
        if (!is.na(value)) {
          multiplier <- if (grepl("TB", vram_line, ignore.case = TRUE)) 1024^4 else 1024^3
          # Try to get GPU name from Chipset Model line
          gpu_name <- NA_character_
          if (!is.na(chipset_line)) {
            gpu_name <- trimws(sub(".*Chipset Model:\\s*", "", chipset_line))
          }
          if (is.na(gpu_name) || !nzchar(gpu_name)) {
            gpu_name <- "Discrete GPU"
          }
          info$name <- gpu_name
          info$vram_bytes <- value * multiplier
          info$source <- "system_profiler"
          return(info)
        }
      }

      # GPU detected but no VRAM info (could be older Mac with AMD/NVIDIA)
      if (!is.na(chipset_line)) {
        chipset <- trimws(sub(".*Chipset Model:\\s*", "", chipset_line))
        if (nzchar(chipset) && !grepl("Intel", chipset, ignore.case = TRUE)) {
          info$name <- chipset
          info$source <- "system_profiler (VRAM unknown)"
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

  # Track if we should prompt user
  has_critical_issue <- FALSE
  issues <- character(0)

  # Check RAM requirements
  if (!is.na(ram_total) && estimated_ram > ram_total) {
    has_critical_issue <- TRUE
    issues <- c(issues, sprintf(
      "   RAM: Model (~%.1f GB) may require %.1f GB but only %.1f GB detected",
      size_bytes / 2^30, estimated_ram / 2^30, ram_total / 2^30
    ))
  } else if (!is.na(ram_total) && estimated_ram > ram_total * 0.8 && !isTRUE(use_mmap)) {
    has_critical_issue <- TRUE
    issues <- c(issues, sprintf(
      "   RAM: Loading without mmap may consume ~%.1f GB (%.0f%% of detected memory)",
      estimated_ram / 2^30, 100 * estimated_ram / ram_total
    ))
  }

  # Check GPU/VRAM requirements
  gpu_info <- profile$gpu
  if (n_gpu_layers > 0) {
    if (is.null(gpu_info) || is.na(gpu_info$name)) {
      has_critical_issue <- TRUE
      issues <- c(issues, "   GPU: Could not be detected, but n_gpu_layers > 0")
    } else if (grepl("unified memory", gpu_info$source, ignore.case = TRUE)) {
      # Apple Silicon with unified memory - informational only
      message(sprintf(
        "Info: GPU '%s' (%d cores) uses unified memory architecture. GPU layers will share system RAM (%.1f GB total).",
        gpu_info$name, gpu_info$cores %||% NA_integer_, ram_total / 2^30
      ))
    } else if (grepl("shared memory", gpu_info$source, ignore.case = TRUE)) {
      # Intel integrated GPU - informational only
      message(sprintf(
        "Info: GPU '%s' uses shared memory architecture. GPU layers will share system RAM (%.1f GB total).",
        gpu_info$name, ram_total / 2^30
      ))
    } else if (is.na(gpu_info$vram_bytes)) {
      has_critical_issue <- TRUE
      issues <- c(issues, "   VRAM: Could not be detected, but n_gpu_layers > 0")
    } else {
      approx_layers <- 100
      gpu_fraction <- min(1, n_gpu_layers / approx_layers)
      gpu_need <- size_bytes * gpu_fraction
      if (gpu_need > gpu_info$vram_bytes * 0.9) {
        has_critical_issue <- TRUE
        issues <- c(issues, sprintf(
          "   VRAM: Offloading ~%d layers may require %.1f GB but only %.1f GB detected",
          n_gpu_layers, gpu_need / 2^30, gpu_info$vram_bytes / 2^30
        ))
      }
    }
  }

  # If critical issues detected, prompt user
  if (has_critical_issue) {
    cat("\nWARNING: Hardware Capacity Warning\n")
    cat(paste(issues, collapse = "\n"))
    cat("\n\nSuggestions:\n")
    if (!isTRUE(use_mmap) && !is.na(ram_total) && estimated_ram > ram_total * 0.8) {
      cat("  - Set use_mmap = TRUE to reduce RAM requirements\n")
    }
    if (n_gpu_layers > 0 && length(grep("VRAM", issues)) > 0) {
      cat("  - Reduce n_gpu_layers or set to 0 for CPU-only mode\n")
    }
    if (!is.na(ram_total) && estimated_ram > ram_total) {
      cat("  - Use a smaller model or more quantized version\n")
    }
    cat("\n")

    # Interactive confirmation
    if (interactive()) {
      cat("Continue loading? Model may fail to load or cause system instability.\n")
      response <- readline("Enter 1 to continue, 0 to stop: ")

      if (!identical(trimws(response), "1")) {
        stop("Model loading cancelled by user.", call. = FALSE)
      }
      cat("\nWARNING: proceeding at user request...\n\n")
    } else {
      # Non-interactive mode: stop immediately
      stop(sprintf(
        "Hardware capacity exceeded. Model '%s' requires more resources than available. Use interactive mode to override.",
        basename(model_path)
      ), call. = FALSE)
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

  issues <- character(0)
  if (n_ctx >= 8192 && ram < 16 * 2^30) {
    issues <- c(issues, sprintf(
      "Safety check: requested n_ctx = %d on a system with %.1f GB RAM. Large context windows can exhaust memory.",
      n_ctx, ram / 2^30
    ))
  } else if (n_ctx >= 4096 && n_seq_max > 1 && ram < 16 * 2^30) {
    issues <- c(issues, sprintf(
      "Safety check: batch with n_seq_max = %d and n_ctx = %d may exceed memory on this system (%.1f GB detected).",
      n_seq_max, n_ctx, ram / 2^30
    ))
  }

  if (length(issues)) {
    for (msg in issues) {
      warning(msg, call. = FALSE)
    }

    if (interactive()) {
      cat("\nWARNING: Context Window Warning\n")
      cat(paste0("   - ", issues, collapse = "\n"), "\n\n")
      cat("Suggestions:\n")
      cat("  - Reduce n_ctx or n_seq_max\n")
      cat("  - Ensure the system has enough RAM for the requested context size\n\n")
      cat("Continue with these settings? Generation may fail or slow down.\n")
      response <- readline("Enter 1 to continue, 0 to stop: ")
      if (!identical(trimws(response), "1")) {
        stop("Context creation cancelled by user due to large n_ctx settings.", call. = FALSE)
      }
      cat("\nWARNING: proceeding at user request...\n\n")
    }
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

.validate_generation_params <- function(tokens, max_tokens, n_ctx) {
  if (is.null(n_ctx) || is.na(n_ctx)) {
    return(invisible(NULL))
  }

  prompt_tokens <- length(tokens)
  projected <- prompt_tokens + max_tokens

  # Hard limit: must not exceed context
  if (projected > n_ctx) {
    cat(sprintf(
      "\nWARNING: Parameter Conflict Detected\n",
      "   Prompt: %d tokens\n",
      "   max_tokens: %d\n",
      "   Total needed: %d tokens\n",
      "   Context size: %d tokens\n",
      "   -> Exceeds by %d tokens!\n\n",
      prompt_tokens, max_tokens, projected, n_ctx, projected - n_ctx
    ))
    cat("Suggestions:\n")
    cat(sprintf("  - Reduce max_tokens to %d or less\n", max(1L, n_ctx - prompt_tokens - 10L)))
    cat("  - Reduce prompt length\n")
    cat("  - Increase n_ctx when creating context\n\n")

    # Interactive confirmation
    if (interactive()) {
      cat("Continue anyway? Generation may crash or produce truncated output.\n")
      response <- readline("Enter 1 to continue, 0 to stop: ")

      if (!identical(trimws(response), "1")) {
        stop("Generation cancelled by user.", call. = FALSE)
      }
      cat("\nWARNING: proceeding at user request...\n\n")
    } else {
      # Non-interactive mode: stop immediately
      stop(sprintf(
        "Parameter conflict: prompt (%d tokens) + max_tokens (%d) = %d tokens exceeds context size (%d).",
        prompt_tokens, max_tokens, projected, n_ctx
      ), call. = FALSE)
    }
  }

  # Soft warning: prompt uses > 85% of context
  if (prompt_tokens / n_ctx > 0.85 && projected <= n_ctx) {
    if (.safety_warnings_enabled()) {
      warning(sprintf(
        "Safety check: prompt uses %.0f%% of context window (%d/%d tokens). Only %d tokens available for generation.",
        100 * prompt_tokens / n_ctx, prompt_tokens, n_ctx, n_ctx - prompt_tokens
      ), call. = FALSE)
    }
  }

  invisible(NULL)
}
