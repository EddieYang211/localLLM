#ifndef LOCALLLM_CAPI_H
#define LOCALLLM_CAPI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
  #ifdef LOCALLLM_BUILD_DLL
    #define LOCALLLM_API __declspec(dllexport)
  #else
    #define LOCALLLM_API __declspec(dllimport)
  #endif
#else
  #define LOCALLLM_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct llama_model*  localllm_model_handle;
typedef struct llama_context* localllm_context_handle;
typedef enum { LOCALLLM_SUCCESS = 0, LOCALLLM_ERROR = 1 } localllm_error_code;
struct localllm_chat_message { const char* role; const char* content; };
struct localllm_parallel_params {
    int max_tokens;
    int top_k;
    float top_p;
    float temperature;
    int repeat_last_n;
    float penalty_repeat;
    int32_t seed;
    bool show_progress;
};

LOCALLLM_API localllm_error_code localllm_backend_init(const char** error_message);
LOCALLLM_API void localllm_backend_free();
LOCALLLM_API localllm_error_code localllm_model_load(const char* model_path, int n_gpu_layers, bool use_mmap, bool use_mlock, localllm_model_handle* model_handle_out, const char** error_message);
LOCALLLM_API localllm_error_code localllm_model_load_safe(const char* model_path, int n_gpu_layers, bool use_mmap, bool use_mlock, bool check_memory, int verbosity, localllm_model_handle* model_handle_out, const char** error_message);
LOCALLLM_API void localllm_model_free(localllm_model_handle model);
LOCALLLM_API localllm_error_code localllm_context_create(localllm_model_handle model, int n_ctx, int n_threads, int n_seq_max, int verbosity, localllm_context_handle* context_handle_out, const char** error_message);
LOCALLLM_API void localllm_context_free(localllm_context_handle ctx);
LOCALLLM_API localllm_error_code localllm_tokenize(localllm_model_handle model, const char* text, bool add_special, int32_t** tokens_out, size_t* n_tokens_out, const char** error_message);
LOCALLLM_API localllm_error_code localllm_detokenize(localllm_model_handle model, const int32_t* tokens, size_t n_tokens, char** text_out, const char** error_message);
LOCALLLM_API void localllm_free_string(char* str);
LOCALLLM_API void localllm_free_tokens(int32_t* tokens);
LOCALLLM_API localllm_error_code localllm_apply_chat_template(localllm_model_handle model, const char* tmpl, const struct localllm_chat_message* messages, size_t n_messages, bool add_ass, char** result_out, const char** error_message);
LOCALLLM_API localllm_error_code localllm_generate(localllm_context_handle ctx, const int32_t* tokens_in, size_t n_tokens_in, int max_tokens, int top_k, float top_p, float temperature, int repeat_last_n, float penalty_repeat, int32_t seed, char** result_out, const char** error_message);
LOCALLLM_API localllm_error_code localllm_generate_parallel(localllm_context_handle ctx, const char** prompts, int n_prompts, const struct localllm_parallel_params* params, char*** results_out, const char** error_message);
LOCALLLM_API void localllm_free_string_array(char** arr, int count);
LOCALLLM_API localllm_error_code localllm_token_get_text(localllm_model_handle model, int32_t token, char** text_out, const char** error_message);
LOCALLLM_API float localllm_token_get_score(localllm_model_handle model, int32_t token);
LOCALLLM_API int localllm_token_get_attr(localllm_model_handle model, int32_t token);
LOCALLLM_API bool localllm_token_is_eog(localllm_model_handle model, int32_t token);
LOCALLLM_API bool localllm_token_is_control(localllm_model_handle model, int32_t token);
LOCALLLM_API int32_t localllm_token_bos(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_eos(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_sep(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_nl(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_pad(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_eot(localllm_model_handle model);
LOCALLLM_API bool localllm_add_bos_token(localllm_model_handle model);
LOCALLLM_API bool localllm_add_eos_token(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_fim_pre(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_fim_mid(localllm_model_handle model);
LOCALLLM_API int32_t localllm_token_fim_suf(localllm_model_handle model);

// Model download and resolution functions
LOCALLLM_API localllm_error_code localllm_download_model(const char* model_url, const char* output_path, bool show_progress, const char** error_message);
LOCALLLM_API localllm_error_code localllm_resolve_model(const char* model_url, char** resolved_path, const char** error_message);

// Memory checking functions
LOCALLLM_API size_t localllm_estimate_model_memory(const char* model_path, const char** error_message);
LOCALLLM_API bool localllm_check_memory_available(size_t required_bytes, const char** error_message);

#ifdef __cplusplus
}
#endif
#endif 
