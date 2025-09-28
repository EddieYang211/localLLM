#include "proxy.h"
#include <stdexcept>
#include "platform_dlopen.h"
#include <cstring>
#include <string>

// Define global function pointer instance
struct localllm_api_ptrs localllm_api;

// Macro definition to simplify symbol loading process
#define LOAD_SYMBOL(handle, F) \
    *(void**)(&localllm_api.F) = platform_dlsym(handle, "localllm_" #F); \
    if (localllm_api.F == NULL) { \
        /* Try with underscore prefix (macOS) */ \
        *(void**)(&localllm_api.F) = platform_dlsym(handle, "_localllm_" #F); \
    } \
    if (localllm_api.F == NULL) { \
        const char* error = platform_dlerror(); \
        throw std::runtime_error(std::string("Failed to load symbol: localllm_" #F) + \
                                (error ? std::string(" - ") + error : "")); \
    }

// Initialization function implementation
bool localllm_api_init(platform_dlhandle_t handle) {
    try {
        // Load core functions
        LOAD_SYMBOL(handle, backend_init);
        LOAD_SYMBOL(handle, backend_free);
        LOAD_SYMBOL(handle, model_load);
        LOAD_SYMBOL(handle, model_load_safe);
        LOAD_SYMBOL(handle, model_free);
        LOAD_SYMBOL(handle, context_create);
        LOAD_SYMBOL(handle, context_free);
        
        // Load text processing functions
        LOAD_SYMBOL(handle, tokenize);
        LOAD_SYMBOL(handle, detokenize);
        LOAD_SYMBOL(handle, apply_chat_template);
        LOAD_SYMBOL(handle, generate);
        LOAD_SYMBOL(handle, generate_parallel);
        
        // Load memory management functions
        LOAD_SYMBOL(handle, free_tokens);
        LOAD_SYMBOL(handle, free_string);
        LOAD_SYMBOL(handle, free_string_array);
        
        // Load token functions
        LOAD_SYMBOL(handle, token_get_text);
        LOAD_SYMBOL(handle, token_bos);
        LOAD_SYMBOL(handle, token_eos);
        LOAD_SYMBOL(handle, token_sep);
        LOAD_SYMBOL(handle, token_nl);
        LOAD_SYMBOL(handle, token_pad);
        LOAD_SYMBOL(handle, token_eot);
        LOAD_SYMBOL(handle, add_bos_token);
        LOAD_SYMBOL(handle, add_eos_token);
        LOAD_SYMBOL(handle, token_fim_pre);
        LOAD_SYMBOL(handle, token_fim_mid);
        LOAD_SYMBOL(handle, token_fim_suf);
        LOAD_SYMBOL(handle, token_get_attr);
        LOAD_SYMBOL(handle, token_get_score);
        LOAD_SYMBOL(handle, token_is_eog);
        LOAD_SYMBOL(handle, token_is_control);
        
        // Load model download functions
        LOAD_SYMBOL(handle, download_model);
        LOAD_SYMBOL(handle, resolve_model);
        
        // Load memory checking functions
        LOAD_SYMBOL(handle, estimate_model_memory);
        LOAD_SYMBOL(handle, check_memory_available);
        
        return true;
        
    } catch (const std::exception& e) {
        return false;
    }
}

// Check if symbols are loaded
bool localllm_api_is_loaded() {
    // Check if several key functions are loaded
    return (localllm_api.backend_init != nullptr && 
            localllm_api.model_load != nullptr && 
            localllm_api.context_create != nullptr);
}

// Reset all function pointers (for cleanup during unloading)
void localllm_api_reset() {
    memset(&localllm_api, 0, sizeof(localllm_api));
} 
