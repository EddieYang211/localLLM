// --- FILE: localLLM/src/proxy.h ---
#pragma once
#include "localllm_capi.h"
#include "platform_dlopen.h"

// Define a structure to store all C-API function pointers
struct localllm_api_ptrs {
    // Core functions
    decltype(&localllm_backend_init) backend_init;
    decltype(&localllm_backend_free) backend_free;
    decltype(&localllm_model_load) model_load;
    decltype(&localllm_model_load_safe) model_load_safe;
    decltype(&localllm_model_free) model_free;
    decltype(&localllm_context_create) context_create;
    decltype(&localllm_context_free) context_free;
    
    // Text processing functions
    decltype(&localllm_tokenize) tokenize;
    decltype(&localllm_detokenize) detokenize;
    decltype(&localllm_apply_chat_template) apply_chat_template;
    decltype(&localllm_generate) generate;
    decltype(&localllm_generate_parallel) generate_parallel;
    
    // Memory management functions
    decltype(&localllm_free_tokens) free_tokens;
    decltype(&localllm_free_string) free_string;
    decltype(&localllm_free_string_array) free_string_array;
    
    // Token functions
    decltype(&localllm_token_get_text) token_get_text;
    decltype(&localllm_token_bos) token_bos;
    decltype(&localllm_token_eos) token_eos;
    decltype(&localllm_token_sep) token_sep;
    decltype(&localllm_token_nl) token_nl;
    decltype(&localllm_token_pad) token_pad;
    decltype(&localllm_token_eot) token_eot;
    decltype(&localllm_add_bos_token) add_bos_token;
    decltype(&localllm_add_eos_token) add_eos_token;
    decltype(&localllm_token_fim_pre) token_fim_pre;
    decltype(&localllm_token_fim_mid) token_fim_mid;
    decltype(&localllm_token_fim_suf) token_fim_suf;
    decltype(&localllm_token_get_attr) token_get_attr;
    decltype(&localllm_token_get_score) token_get_score;
    decltype(&localllm_token_is_eog) token_is_eog;
    decltype(&localllm_token_is_control) token_is_control;
    
    // Model download functions
    decltype(&localllm_download_model) download_model;
    decltype(&localllm_resolve_model) resolve_model;
    
    // Memory checking functions
    decltype(&localllm_estimate_model_memory) estimate_model_memory;
    decltype(&localllm_check_memory_available) check_memory_available;
};

// Declare a global function pointer structure instance
extern struct localllm_api_ptrs localllm_api;

// Declare an initialization function for loading symbols in R
bool localllm_api_init(platform_dlhandle_t handle);

// Declare a check function to ensure symbols are loaded
bool localllm_api_is_loaded();

// Declare a reset function for cleaning up function pointers
void localllm_api_reset(); 
