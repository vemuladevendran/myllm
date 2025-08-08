#include <jni.h>
#include <dlfcn.h>
#include <string>
#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "llama_bridge", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "llama_bridge", __VA_ARGS__)

// ---- llama.cpp symbol typedefs (we'll resolve them via dlsym) ----
typedef void*  (*llama_model_load_from_file_t)(const char* path, void* params);
typedef void*  (*llama_init_from_model_t)(void* model, void* ctx_params);
typedef void   (*llama_free_t)(void* ctx);
typedef void   (*llama_model_free_t)(void* model);
typedef int32_t(*llama_model_meta_val_str_t)(const void*, const char*, char*, size_t);
typedef int32_t(*llama_n_threads_t)(void* ctx);
typedef void   (*llama_backend_init_t)(void);
typedef void   (*llama_backend_free_t)(void);

// Some builds of llama.cpp still export llama_init_from_file(ctx_path, params).
// If your libllama.so has that symbol, we'll prefer it; otherwise, we'll do model+context path.
typedef void*  (*llama_init_from_file_t)(const char* path, void* params);

// ---- Global handles ----
static void* g_llama_handle = nullptr;
static void* g_ctx          = nullptr;
static void* g_model        = nullptr;

// ---- Resolved function pointers ----
static llama_backend_init_t           p_llama_backend_init = nullptr;
static llama_backend_free_t           p_llama_backend_free = nullptr;
static llama_init_from_file_t         p_llama_init_from_file = nullptr; // optional
static llama_model_load_from_file_t   p_llama_model_load_from_file = nullptr;
static llama_init_from_model_t        p_llama_init_from_model = nullptr;
static llama_free_t                   p_llama_free = nullptr;
static llama_model_free_t             p_llama_model_free = nullptr;

// Resolve one symbol and log on failure
static void* must_resolve(void* handle, const char* name, bool optional = false) {
    void* sym = dlsym(handle, name);
    if (!sym && !optional) {
        const char* err = dlerror();
        LOGE("dlsym(%s) failed: %s", name, err ? err : "unknown");
    }
    return sym;
}

extern "C" __attribute__((visibility("default")))
int lb_load(const char* model_path_cstr) {
    LOGI("[lb_load] requested model: %s", model_path_cstr ? model_path_cstr : "(null)");

    if (!model_path_cstr || model_path_cstr[0] == '\0') {
        LOGE("[lb_load] invalid path");
        return -1;
    }

    // If already loaded, free old
    if (g_ctx && p_llama_free) {
        LOGI("[lb_load] freeing previous context");
        p_llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model && p_llama_model_free) {
        LOGI("[lb_load] freeing previous model");
        p_llama_model_free(g_model);
        g_model = nullptr;
    }

    if (!g_llama_handle) {
        g_llama_handle = dlopen("libllama.so", RTLD_NOW);
        if (!g_llama_handle) {
            LOGE("dlopen(libllama.so) failed: %s", dlerror());
            return -2;
        }
        LOGI("dlopen(libllama.so) OK");

        // Resolve commonly used symbols
        p_llama_backend_init         = (llama_backend_init_t)         must_resolve(g_llama_handle, "llama_backend_init", true);
        p_llama_backend_free         = (llama_backend_free_t)         must_resolve(g_llama_handle, "llama_backend_free", true);
        p_llama_init_from_file       = (llama_init_from_file_t)       must_resolve(g_llama_handle, "llama_init_from_file", true);
        p_llama_model_load_from_file = (llama_model_load_from_file_t) must_resolve(g_llama_handle, "llama_model_load_from_file", true);
        p_llama_init_from_model      = (llama_init_from_model_t)      must_resolve(g_llama_handle, "llama_init_from_model", true);
        p_llama_free                 = (llama_free_t)                 must_resolve(g_llama_handle, "llama_free");
        p_llama_model_free           = (llama_model_free_t)           must_resolve(g_llama_handle, "llama_model_free", true);

        if (!p_llama_free) {
            LOGE("Required symbol llama_free not found");
            return -3;
        }
    }

    if (p_llama_backend_init) {
        LOGI("calling llama_backend_init()");
        p_llama_backend_init();
    }

    // Prefer the direct initializer if available:
    if (p_llama_init_from_file) {
        LOGI("using llama_init_from_file()");
        g_ctx = p_llama_init_from_file(model_path_cstr, nullptr);
        if (!g_ctx) {
            LOGE("llama_init_from_file returned null");
            return -4;
        }
        LOGI("llama_init_from_file OK");
        return 0;
    }

    // Fallback: load model then create context
    if (!p_llama_model_load_from_file || !p_llama_init_from_model) {
        LOGE("Your libllama.so lacks required symbols: llama_model_load_from_file or llama_init_from_model");
        return -5;
    }

    LOGI("using model->context fallback: llama_model_load_from_file + llama_init_from_model");
    g_model = p_llama_model_load_from_file(model_path_cstr, nullptr);
    if (!g_model) {
        LOGE("llama_model_load_from_file returned null");
        return -6;
    }
    g_ctx = p_llama_init_from_model(g_model, nullptr);
    if (!g_ctx) {
        LOGE("llama_init_from_model returned null");
        return -7;
    }

    LOGI("model+context created OK");
    return 0;
}

extern "C" __attribute__((visibility("default")))
int lb_is_loaded() {
    return g_ctx ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
void lb_free() {
    LOGI("[lb_free] called");
    if (g_ctx && p_llama_free) {
        p_llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model && p_llama_model_free) {
        p_llama_model_free(g_model);
        g_model = nullptr;
    }
    if (p_llama_backend_free) {
        p_llama_backend_free();
    }
}
