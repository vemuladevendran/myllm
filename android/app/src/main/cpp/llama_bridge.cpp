#include <android/log.h>
#include <string>
#include <llama.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "llama_bridge", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "llama_bridge", __VA_ARGS__)

static llama_model*   g_model = nullptr;
static llama_context* g_ctx   = nullptr;

extern "C" __attribute__((visibility("default")))
int lb_load(const char* model_path_cstr) {
    LOGI("[lb_load] path: %s", model_path_cstr ? model_path_cstr : "(null)");
    if (!model_path_cstr || model_path_cstr[0] == '\0') return -1;

    if (g_ctx)  { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model){ llama_model_free(g_model); g_model = nullptr; }

    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();
    // mparams.use_mmap = true; // optional
    g_model = llama_model_load_from_file(model_path_cstr, mparams);
    if (!g_model) { LOGE("llama_model_load_from_file failed"); return -2; }

    llama_context_params cparams = llama_context_default_params();
    // cparams.n_threads = 4; // optional
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed");
        llama_model_free(g_model);
        g_model = nullptr;
        return -3;
    }
    LOGI("model+context created OK");
    return 0;
}

extern "C" __attribute__((visibility("default")))
int lb_is_loaded() { return g_ctx ? 1 : 0; }

extern "C" __attribute__((visibility("default")))
void lb_free() {
    LOGI("[lb_free]");
    if (g_ctx)  { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model){ llama_model_free(g_model); g_model = nullptr; }
    llama_backend_free();
}

extern "C" __attribute__((visibility("default")))
const char* lb_eval(const char* prompt, int max_tokens) {
    static std::string out;
    out = std::string("[bridge echo] ") + (prompt ? prompt : "<null>") +
          " | max=" + std::to_string(max_tokens);
    return out.c_str();
}
