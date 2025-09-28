#include <Rcpp.h>
#include "proxy.h"
#include "platform_dlopen.h"

using namespace Rcpp;

// --- Helper for error checking ---
void check_error(localllm_error_code code, const char* error_message) {
    if (code != LOCALLLM_SUCCESS) {
        stop(error_message ? error_message : "An unknown error occurred in the backend C-API.");
    }
}

// --- Finalizers for External Pointers ---
extern "C" void model_finalizer(SEXP ptr) {
    localllm_model_handle handle = static_cast<localllm_model_handle>(R_ExternalPtrAddr(ptr));
    if (handle && localllm_api.model_free) {
        localllm_api.model_free(handle);
    }
    R_ClearExternalPtr(ptr);
}

extern "C" void context_finalizer(SEXP ptr) {
    localllm_context_handle handle = static_cast<localllm_context_handle>(R_ExternalPtrAddr(ptr));
    if (handle && localllm_api.context_free) {
        localllm_api.context_free(handle);
    }
    R_ClearExternalPtr(ptr);
}

// ------------------------------------
// --- R-Exported Wrapper Functions ---
// ------------------------------------

extern "C" {

void r_localllm_api_init(SEXP path_sexp) {
    if (TYPEOF(path_sexp) != STRSXP || LENGTH(path_sexp) != 1) {
        stop("Expected character string for library path");
    }
    
    const char* lib_path = CHAR(STRING_ELT(path_sexp, 0));
    if (!lib_path || strlen(lib_path) == 0) {
        stop("Invalid library path");
    }
    
    platform_dlhandle_t handle = PLATFORM_RTLD_DEFAULT;
    bool success = localllm_api_init(handle);
    
    if (!success) {
        handle = platform_dlopen(lib_path, PLATFORM_RTLD_LAZY | PLATFORM_RTLD_GLOBAL);
        if (!handle) {
            const char* error = platform_dlerror();
            stop(std::string("Failed to open library: ") + (error ? error : "unknown error"));
        }
        
        success = localllm_api_init(handle);
        if (!success) {
            platform_dlclose(handle);
            stop("Failed to initialize localllm API: unable to load required symbols");
        }
    }
}

SEXP r_backend_init() {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    const char* error_message = nullptr;
    check_error(localllm_api.backend_init(&error_message), error_message);
    return R_NilValue;
}

SEXP r_backend_free() {
    if (localllm_api.backend_free) {
        localllm_api.backend_free();
    }
    return R_NilValue;
}

SEXP r_model_load(SEXP model_path, SEXP n_gpu_layers, SEXP use_mmap, SEXP use_mlock) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    std::string model_path_str = as<std::string>(model_path);
    int n_gpu_layers_int = as<int>(n_gpu_layers);
    bool use_mmap_bool = as<bool>(use_mmap);
    bool use_mlock_bool = as<bool>(use_mlock);
    
    const char* error_message = nullptr;
    localllm_model_handle handle = nullptr;
    check_error(localllm_api.model_load(model_path_str.c_str(), n_gpu_layers_int, use_mmap_bool, use_mlock_bool, &handle, &error_message), error_message);

    SEXP p = R_MakeExternalPtr(handle, R_NilValue, R_NilValue);
    PROTECT(p);
    Rf_setAttrib(p, R_ClassSymbol, Rf_mkString("localllm_model"));
    R_RegisterCFinalizerEx(p, (R_CFinalizer_t)model_finalizer, TRUE);
    UNPROTECT(1);
    return p;
}

SEXP r_model_load_safe(SEXP model_path, SEXP n_gpu_layers, SEXP use_mmap, SEXP use_mlock, SEXP check_memory, SEXP verbosity) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    std::string model_path_str = as<std::string>(model_path);
    int n_gpu_layers_int = as<int>(n_gpu_layers);
    bool use_mmap_bool = as<bool>(use_mmap);
    bool use_mlock_bool = as<bool>(use_mlock);
    bool check_memory_bool = as<bool>(check_memory);
    int verbosity_int = as<int>(verbosity);
    
    const char* error_message = nullptr;
    localllm_model_handle handle = nullptr;
    check_error(localllm_api.model_load_safe(model_path_str.c_str(), n_gpu_layers_int, use_mmap_bool, use_mlock_bool, check_memory_bool, verbosity_int, &handle, &error_message), error_message);

    SEXP p = R_MakeExternalPtr(handle, R_NilValue, R_NilValue);
    PROTECT(p);
    Rf_setAttrib(p, R_ClassSymbol, Rf_mkString("localllm_model"));
    R_RegisterCFinalizerEx(p, (R_CFinalizer_t)model_finalizer, TRUE);
    UNPROTECT(1);
    return p;
}

SEXP r_estimate_model_memory(SEXP model_path) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    
    std::string model_path_str = as<std::string>(model_path);
    const char* error_message = nullptr;
    size_t estimated_memory = localllm_api.estimate_model_memory(model_path_str.c_str(), &error_message);
    
    if (estimated_memory == 0 && error_message) {
        stop(error_message);
    }
    
    return NumericVector::create(static_cast<double>(estimated_memory));
}

SEXP r_check_memory_available(SEXP required_bytes) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    
    double required_bytes_double = as<double>(required_bytes);
    size_t required_bytes_size = static_cast<size_t>(required_bytes_double);
    
    const char* error_message = nullptr;
    bool available = localllm_api.check_memory_available(required_bytes_size, &error_message);
    
    return LogicalVector::create(available);
}

SEXP r_context_create(SEXP model_ptr, SEXP n_ctx, SEXP n_threads, SEXP n_seq_max, SEXP verbosity) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    int n_ctx_int = as<int>(n_ctx);
    int n_threads_int = as<int>(n_threads);
    int n_seq_max_int = as<int>(n_seq_max);
    int verbosity_int = as<int>(verbosity);
    const char* error_message = nullptr;
    localllm_context_handle handle = nullptr;
    check_error(localllm_api.context_create(model, n_ctx_int, n_threads_int, n_seq_max_int, verbosity_int, &handle, &error_message), error_message);
    
    SEXP p = R_MakeExternalPtr(handle, R_NilValue, R_NilValue);
    PROTECT(p);
    Rf_setAttrib(p, R_ClassSymbol, Rf_mkString("localllm_context"));
    R_RegisterCFinalizerEx(p, (R_CFinalizer_t)context_finalizer, TRUE);
    UNPROTECT(1);
    return p;
}

SEXP r_tokenize(SEXP model_ptr, SEXP text, SEXP add_special) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    std::string text_str = as<std::string>(text);
    bool add_special_bool = as<bool>(add_special);
    
    alignas(8) const char* error_message = nullptr;
    alignas(8) int32_t* tokens_c = nullptr;
    alignas(8) size_t n_tokens_c = 0;
    
    localllm_error_code result = localllm_api.tokenize(model, text_str.c_str(), add_special_bool, &tokens_c, &n_tokens_c, &error_message);
    check_error(result, error_message);
    
    IntegerVector tokens_r(n_tokens_c);
    for (size_t i = 0; i < n_tokens_c; ++i) {
        tokens_r[i] = tokens_c[i];
    }
    
    if (localllm_api.free_tokens) {
        localllm_api.free_tokens(tokens_c);
    }
    return tokens_r;
}

SEXP r_detokenize(SEXP model_ptr, SEXP tokens) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    IntegerVector tokens_vec = as<IntegerVector>(tokens);
    const char* error_message = nullptr;
    char* text_c = nullptr;
    std::vector<int32_t> tokens_cpp = as<std::vector<int32_t>>(tokens_vec);
    check_error(localllm_api.detokenize(model, tokens_cpp.data(), tokens_cpp.size(), &text_c, &error_message), error_message);
    std::string result(text_c);
    if (localllm_api.free_string) {
        localllm_api.free_string(text_c);
    }
    return CharacterVector::create(result);
}

SEXP r_apply_chat_template(SEXP model_ptr, SEXP tmpl, SEXP chat_messages, SEXP add_ass) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    List chat_messages_list = as<List>(chat_messages);
    bool add_ass_bool = as<bool>(add_ass);
    
    std::vector<localllm_chat_message> messages_c(chat_messages_list.size());
    std::vector<std::string> roles, contents;
    roles.reserve(chat_messages_list.size());
    contents.reserve(chat_messages_list.size());
    for(size_t i = 0; i < chat_messages_list.size(); ++i) {
        List msg = chat_messages_list[i];
        roles.push_back(as<std::string>(msg["role"]));
        contents.push_back(as<std::string>(msg["content"]));
        messages_c[i] = {roles.back().c_str(), contents.back().c_str()};
    }
    std::string tmpl_str;
    const char* tmpl_c = nullptr;
    if (!Rf_isNull(tmpl)) {
        tmpl_str = as<std::string>(tmpl);
        tmpl_c = tmpl_str.c_str();
    }
    char* result_c = nullptr;
    const char* error_message = nullptr;
    check_error(localllm_api.apply_chat_template(model, tmpl_c, messages_c.data(), messages_c.size(), add_ass_bool, &result_c, &error_message), error_message);
    std::string result(result_c);
    if (localllm_api.free_string) {
        localllm_api.free_string(result_c);
    }
    return CharacterVector::create(result);
}

SEXP r_generate(SEXP ctx_ptr, SEXP tokens, SEXP max_tokens, SEXP top_k, SEXP top_p, SEXP temperature, SEXP repeat_last_n, SEXP penalty_repeat, SEXP seed) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    localllm_context_handle ctx = static_cast<localllm_context_handle>(R_ExternalPtrAddr(ctx_ptr));
    IntegerVector tokens_vec = as<IntegerVector>(tokens);
    std::vector<int32_t> tokens_cpp = as<std::vector<int32_t>>(tokens_vec);
    int max_tokens_int = as<int>(max_tokens);
    int top_k_int = as<int>(top_k);
    float top_p_float = as<float>(top_p);
    float temperature_float = as<float>(temperature);
    int repeat_last_n_int = as<int>(repeat_last_n);
    float penalty_repeat_float = as<float>(penalty_repeat);
    int32_t seed_int = as<int32_t>(seed);
    char* result_c = nullptr;
    const char* error_message = nullptr;
    check_error(localllm_api.generate(ctx, tokens_cpp.data(), tokens_cpp.size(), max_tokens_int, top_k_int, top_p_float, temperature_float, repeat_last_n_int, penalty_repeat_float, seed_int, &result_c, &error_message), error_message);
    std::string result(result_c);
    if (localllm_api.free_string) {
        localllm_api.free_string(result_c);
    }
    return CharacterVector::create(result);
}

SEXP r_generate_parallel(SEXP ctx_ptr, SEXP prompts, SEXP max_tokens, SEXP top_k, SEXP top_p, SEXP temperature, SEXP repeat_last_n, SEXP penalty_repeat, SEXP seed, SEXP progress) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    localllm_context_handle ctx = static_cast<localllm_context_handle>(R_ExternalPtrAddr(ctx_ptr));
    CharacterVector prompts_vec = as<CharacterVector>(prompts);
    int max_tokens_int = as<int>(max_tokens);
    int top_k_int = as<int>(top_k);
    float top_p_float = as<float>(top_p);
    float temperature_float = as<float>(temperature);
    int repeat_last_n_int = as<int>(repeat_last_n);
    float penalty_repeat_float = as<float>(penalty_repeat);
    int32_t seed_int = as<int32_t>(seed);
    bool progress_bool = as<bool>(progress);
    
    std::vector<const char*> prompts_c;
    for(int i = 0; i < prompts_vec.size(); ++i) {
        prompts_c.push_back(CHAR(STRING_ELT(prompts_vec, i)));
    }
    
    struct localllm_parallel_params params = {max_tokens_int, top_k_int, top_p_float, temperature_float, repeat_last_n_int, penalty_repeat_float, seed_int, progress_bool};
    char** results_c = nullptr;
    const char* error_message = nullptr;
    check_error(localllm_api.generate_parallel(ctx, prompts_c.data(), prompts_c.size(), &params, &results_c, &error_message), error_message);
    
    CharacterVector results_r(prompts_c.size());
    for(size_t i = 0; i < prompts_c.size(); ++i) {
        results_r[i] = std::string(results_c[i]);
    }
    if (localllm_api.free_string_array) {
        localllm_api.free_string_array(results_c, prompts_c.size());
    }
    return results_r;
}

SEXP r_token_get_text(SEXP model_ptr, SEXP token_sexp) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    int32_t token = as<int32_t>(token_sexp);
    char* text_c = nullptr;
    const char* error_message = nullptr;
    check_error(localllm_api.token_get_text(model, token, &text_c, &error_message), error_message);
    std::string text(text_c);
    if (localllm_api.free_string) {
        localllm_api.free_string(text_c);
    }
    return CharacterVector::create(text);
}

// Simplified token functions
SEXP r_token_bos(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_bos(model));
}

SEXP r_token_eos(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_eos(model));
}

SEXP r_token_sep(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_sep(model));
}

SEXP r_token_nl(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_nl(model));
}

SEXP r_token_pad(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_pad(model));
}

SEXP r_token_eot(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_eot(model));
}

SEXP r_add_bos_token(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return LogicalVector::create(localllm_api.add_bos_token(model));
}

SEXP r_add_eos_token(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return LogicalVector::create(localllm_api.add_eos_token(model));
}

SEXP r_token_fim_pre(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_fim_pre(model));
}

SEXP r_token_fim_mid(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_fim_mid(model));
}

SEXP r_token_fim_suf(SEXP model_ptr) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    return IntegerVector::create(localllm_api.token_fim_suf(model));
}

SEXP r_token_get_attr(SEXP model_ptr, SEXP token_sexp) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    int32_t token = as<int32_t>(token_sexp);
    return IntegerVector::create(localllm_api.token_get_attr(model, token));
}

SEXP r_token_get_score(SEXP model_ptr, SEXP token_sexp) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    int32_t token = as<int32_t>(token_sexp);
    return NumericVector::create(localllm_api.token_get_score(model, token));
}

SEXP r_token_is_eog(SEXP model_ptr, SEXP token_sexp) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    int32_t token = as<int32_t>(token_sexp);
    return LogicalVector::create(localllm_api.token_is_eog(model, token));
}

SEXP r_token_is_control(SEXP model_ptr, SEXP token_sexp) {
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    int32_t token = as<int32_t>(token_sexp);
    return LogicalVector::create(localllm_api.token_is_control(model, token));
}

void r_localllm_api_reset() {
    localllm_api_reset();
}

SEXP r_tokenize_test(SEXP model_ptr) {
    if (!localllm_api_is_loaded()) {
        stop("Backend library is not loaded. Please run install_localLLM() first.");
    }
    
    localllm_model_handle model = static_cast<localllm_model_handle>(R_ExternalPtrAddr(model_ptr));
    const char* test_text = "H";
    bool add_special = true;
    
    alignas(8) const char* error_message = nullptr;
    alignas(8) int32_t* tokens_c = nullptr;
    alignas(8) size_t n_tokens_c = 0;
    
    localllm_error_code result = localllm_api.tokenize(model, test_text, add_special, &tokens_c, &n_tokens_c, &error_message);
    
    if (result != LOCALLLM_SUCCESS) {
        std::string error_msg = "Tokenization failed";
        if (error_message) {
            error_msg += ": ";
            error_msg += error_message;
        }
        stop(error_msg);
    }
    
    IntegerVector tokens_r(n_tokens_c);
    for (size_t i = 0; i < n_tokens_c; ++i) {
        tokens_r[i] = tokens_c[i];
    }
    
    if (localllm_api.free_tokens) {
        localllm_api.free_tokens(tokens_c);
    }
    
    return tokens_r;
}

// --- Model Download Functions ---

extern "C" SEXP c_r_download_model(SEXP model_url_sexp, SEXP output_path_sexp, SEXP show_progress_sexp) {
    if (TYPEOF(model_url_sexp) != STRSXP || LENGTH(model_url_sexp) != 1) {
        stop("Expected character string for model_url");
    }
    if (TYPEOF(output_path_sexp) != STRSXP || LENGTH(output_path_sexp) != 1) {
        stop("Expected character string for output_path");
    }
    if (TYPEOF(show_progress_sexp) != LGLSXP || LENGTH(show_progress_sexp) != 1) {
        stop("Expected logical value for show_progress");
    }
    
    const char* model_url = CHAR(STRING_ELT(model_url_sexp, 0));
    const char* output_path = CHAR(STRING_ELT(output_path_sexp, 0));
    bool show_progress = LOGICAL(show_progress_sexp)[0];
    
    const char* error_message = nullptr;
    localllm_error_code code = localllm_api.download_model(model_url, output_path, show_progress, &error_message);
    
    check_error(code, error_message);
    return R_NilValue;
}

extern "C" SEXP c_r_resolve_model(SEXP model_url_sexp) {
    if (TYPEOF(model_url_sexp) != STRSXP || LENGTH(model_url_sexp) != 1) {
        stop("Expected character string for model_url");
    }
    
    const char* model_url = CHAR(STRING_ELT(model_url_sexp, 0));
    char* resolved_path = nullptr;
    const char* error_message = nullptr;
    
    localllm_error_code code = localllm_api.resolve_model(model_url, &resolved_path, &error_message);
    check_error(code, error_message);
    
    if (!resolved_path) {
        stop("Failed to resolve model path");
    }
    
    SEXP result = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(result, 0, Rf_mkChar(resolved_path));
    
    // Free the allocated string
    localllm_api.free_string(resolved_path);
    
    UNPROTECT(1);
    return result;
}

} 
