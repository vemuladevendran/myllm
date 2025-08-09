// android/app/src/main/cpp/llama_bridge.cpp
#include <android/log.h>
#include <dlfcn.h>
#include <string>
#include <vector>
#include <cstring>

// We can include the header for types, but we will *call* via dlsym:
#include <llama.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "llama_bridge", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "llama_bridge", __VA_ARGS__)

// ---- Global state ----
static void*           g_llama_handle = nullptr;
static llama_model*    g_model        = nullptr;
static llama_context*  g_ctx          = nullptr;

// ---- dlsym helpers ----
template<typename T>
static T must_sym(void* h, const char* name, bool optional = false) {
    void* p = dlsym(h, name);
    if (!p && !optional) {
        LOGE("dlsym(%s) failed: %s", name, dlerror());
    }
    return reinterpret_cast<T>(p);
}

// ---- llama symbols we’ll use ----
static void  (*p_llama_backend_init)(void) = nullptr;
static void  (*p_llama_backend_free)(void) = nullptr;

static llama_model*   (*p_llama_model_load_from_file)(const char*, llama_model_params) = nullptr;
static void           (*p_llama_model_free)(llama_model*) = nullptr;

static llama_model_params   (*p_llama_model_default_params)(void) = nullptr;
static llama_context_params (*p_llama_context_default_params)(void) = nullptr;

static llama_context* (*p_llama_init_from_model)(llama_model*, llama_context_params) = nullptr;
static void           (*p_llama_free)(llama_context*) = nullptr;

static const llama_model* (*p_llama_get_model)(const llama_context*) = nullptr;
static const llama_vocab* (*p_llama_model_get_vocab)(const llama_model*) = nullptr;

static int32_t (*p_llama_vocab_n_tokens)(const llama_vocab*) = nullptr;
static bool    (*p_llama_vocab_is_eog)(const llama_vocab*, llama_token) = nullptr;

static int32_t (*p_llama_tokenize)(const llama_vocab*, const char*, int32_t, llama_token*, int32_t, bool, bool) = nullptr;
static int32_t (*p_llama_detokenize)(const llama_vocab*, const llama_token*, int32_t, char*, int32_t, bool, bool) = nullptr;

static int32_t (*p_llama_decode)(llama_context*, struct llama_batch) = nullptr;
static float*  (*p_llama_get_logits_ith)(llama_context*, int32_t) = nullptr;

extern "C" __attribute__((visibility("default")))
int lb_is_loaded() {
    return g_ctx ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
int lb_load(const char* model_path_cstr) {
    LOGI("[lb_load] path: %s", model_path_cstr ? model_path_cstr : "(null)");

    if (!model_path_cstr || model_path_cstr[0] == '\0') {
        LOGE("invalid model path");
        return -1;
    }

    // Preload ggml CPU backend in case your llama build expects it:
    dlopen("libggml-cpu.so", RTLD_NOW);

    // Free previous
    if (g_ctx)  { if (p_llama_free) p_llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model){ if (p_llama_model_free) p_llama_model_free(g_model); g_model = nullptr; }

    if (!g_llama_handle) {
        g_llama_handle = dlopen("libllama.so", RTLD_NOW);
        if (!g_llama_handle) {
            LOGE("dlopen(libllama.so) failed: %s", dlerror());
            return -2;
        }
        LOGI("dlopen(libllama.so) OK");

        // resolve needed symbols
        p_llama_backend_init            = must_sym<decltype(p_llama_backend_init)>(g_llama_handle, "llama_backend_init");
        p_llama_backend_free            = must_sym<decltype(p_llama_backend_free)>(g_llama_handle, "llama_backend_free", true);

        p_llama_model_default_params    = must_sym<decltype(p_llama_model_default_params)>(g_llama_handle, "llama_model_default_params");
        p_llama_context_default_params  = must_sym<decltype(p_llama_context_default_params)>(g_llama_handle, "llama_context_default_params");

        p_llama_model_load_from_file    = must_sym<decltype(p_llama_model_load_from_file)>(g_llama_handle, "llama_model_load_from_file");
        p_llama_model_free              = must_sym<decltype(p_llama_model_free)>(g_llama_handle, "llama_model_free");

        p_llama_init_from_model         = must_sym<decltype(p_llama_init_from_model)>(g_llama_handle, "llama_init_from_model");
        p_llama_free                    = must_sym<decltype(p_llama_free)>(g_llama_handle, "llama_free");

        p_llama_get_model               = must_sym<decltype(p_llama_get_model)>(g_llama_handle, "llama_get_model");
        p_llama_model_get_vocab         = must_sym<decltype(p_llama_model_get_vocab)>(g_llama_handle, "llama_model_get_vocab");

        p_llama_vocab_n_tokens          = must_sym<decltype(p_llama_vocab_n_tokens)>(g_llama_handle, "llama_vocab_n_tokens");
        p_llama_vocab_is_eog            = must_sym<decltype(p_llama_vocab_is_eog)>(g_llama_handle, "llama_vocab_is_eog");

        p_llama_tokenize                = must_sym<decltype(p_llama_tokenize)>(g_llama_handle, "llama_tokenize");
        p_llama_detokenize              = must_sym<decltype(p_llama_detokenize)>(g_llama_handle, "llama_detokenize");

        p_llama_decode                  = must_sym<decltype(p_llama_decode)>(g_llama_handle, "llama_decode");
        p_llama_get_logits_ith          = must_sym<decltype(p_llama_get_logits_ith)>(g_llama_handle, "llama_get_logits_ith");

        if (!p_llama_backend_init || !p_llama_model_default_params || !p_llama_context_default_params ||
            !p_llama_model_load_from_file || !p_llama_model_free || !p_llama_init_from_model || !p_llama_free ||
            !p_llama_get_model || !p_llama_model_get_vocab || !p_llama_vocab_n_tokens || !p_llama_vocab_is_eog ||
            !p_llama_tokenize || !p_llama_detokenize || !p_llama_decode || !p_llama_get_logits_ith) {
            LOGE("required llama symbols not found — check your libllama.so version");
            return -3;
        }
    }

    p_llama_backend_init();

    llama_model_params mparams = p_llama_model_default_params();
    // mparams.use_mmap = true; // optional
    g_model = p_llama_model_load_from_file(model_path_cstr, mparams);
    if (!g_model) {
        LOGE("llama_model_load_from_file failed");
        return -4;
    }

    llama_context_params cparams = p_llama_context_default_params();
    cparams.n_threads = 4;            // tune for device
    cparams.n_batch   = 256;          // reasonable default
    g_ctx = p_llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed");
        p_llama_model_free(g_model);
        g_model = nullptr;
        return -5;
    }

    LOGI("model+context created OK");
    return 0;
}

extern "C" __attribute__((visibility("default")))
void lb_free() {
    LOGI("[lb_free]");
    if (g_ctx)   { p_llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { p_llama_model_free(g_model); g_model = nullptr; }
    if (p_llama_backend_free) p_llama_backend_free();
}

// Greedy sampling helper (argmax)
static llama_token argmax_token(const float* logits, int32_t n_vocab) {
    int best_i = 0;
    float best_v = logits[0];
    for (int i = 1; i < n_vocab; ++i) {
        if (logits[i] > best_v) {
            best_v = logits[i];
            best_i = i;
        }
    }
    return best_i;
}

extern "C" __attribute__((visibility("default")))
const char* lb_eval(const char* prompt_cstr, int max_tokens) {
    static std::string out;
    out.clear();

    if (!g_ctx || !g_model) {
        out = "❌ model not loaded";
        return out.c_str();
    }

    const llama_model* model = p_llama_get_model(g_ctx);
    const llama_vocab* vocab = p_llama_model_get_vocab(model);
    const int32_t n_vocab    = p_llama_vocab_n_tokens(vocab);

    // 1) Tokenize prompt
    const char* prompt = prompt_cstr ? prompt_cstr : "";
    const int   plen   = (int)strlen(prompt);

    std::vector<llama_token> tokens(plen + 8);
    int32_t n_tokens = p_llama_tokenize(vocab, prompt, plen, tokens.data(), (int)tokens.size(), /*add_special=*/true, /*special=*/false);
    if (n_tokens < 0) { // need bigger buffer
        tokens.resize(-n_tokens);
        n_tokens = p_llama_tokenize(vocab, prompt, plen, tokens.data(), (int)tokens.size(), true, false);
    }
    if (n_tokens <= 0) {
        out = "❌ tokenization failed";
        return out.c_str();
    }
    tokens.resize(n_tokens);

    // 2) Feed prompt tokens into context
    // Build a llama_batch for the whole prompt
    std::vector<llama_pos>      pos(n_tokens);
    std::vector<int32_t>        n_seq_id(n_tokens, 1);
    std::vector<llama_seq_id*>  seq_id(n_tokens);
    std::vector<llama_seq_id>   seq_buf(n_tokens, 0);
    std::vector<int8_t>         logits_mask(n_tokens, 0);

    for (int i = 0; i < n_tokens; ++i) {
        pos[i] = i;
        seq_id[i] = &seq_buf[i];
        logits_mask[i] = (i == n_tokens - 1) ? 1 : 0; // only last token will generate logits
    }

    llama_batch batch;
    batch.n_tokens = n_tokens;
    batch.token    = tokens.data();
    batch.embd     = nullptr;
    batch.pos      = pos.data();
    batch.n_seq_id = n_seq_id.data();
    batch.seq_id   = seq_id.data();
    batch.logits   = logits_mask.data();

    int32_t dec = p_llama_decode(g_ctx, batch);
    if (dec != 0) {
        out = "❌ decode failed on prompt";
        return out.c_str();
    }

    // 3) Generate up to max_tokens
    std::vector<llama_token> generated;
    generated.reserve(max_tokens);

    llama_pos cur_pos = n_tokens;
    llama_seq_id sid  = 0;

    for (int t = 0; t < max_tokens; ++t) {
        // logits for last token
        float* last_logits = p_llama_get_logits_ith(g_ctx, -1);
        if (!last_logits) {
            out = "❌ logits missing";
            return out.c_str();
        }
        llama_token next = argmax_token(last_logits, n_vocab);

        // stop on EOG
        if (p_llama_vocab_is_eog(vocab, next)) {
            break;
        }

        // prepare single-token batch
        llama_token tok_arr[1] = { next };
        llama_pos   pos_arr[1] = { cur_pos };
        int32_t     nsi_arr[1] = { 1 };
        llama_seq_id* sid_arr[1] = { &sid };
        int8_t      log_arr[1] = { 1 };

        llama_batch b2;
        b2.n_tokens = 1;
        b2.token    = tok_arr;
        b2.embd     = nullptr;
        b2.pos      = pos_arr;
        b2.n_seq_id = nsi_arr;
        b2.seq_id   = sid_arr;
        b2.logits   = log_arr;

        if (p_llama_decode(g_ctx, b2) != 0) {
            out = "❌ decode failed during gen";
            return out.c_str();
        }

        generated.push_back(next);
        cur_pos += 1;
    }

    // 4) Detokenize generated tokens only
    if (generated.empty()) {
        out = "";
        return out.c_str();
    }

    // conservative buffer (chars)
    int buf_sz = (int)generated.size() * 8 + 64;
    std::string text(buf_sz, '\0');

    int32_t got = p_llama_detokenize(vocab,
                                     generated.data(),
                                     (int32_t)generated.size(),
                                     text.data(),
                                     buf_sz,
                                     /*remove_special=*/true,
                                     /*unparse_special=*/true);
    if (got < 0) {
        out = "❌ detokenize failed";
        return out.c_str();
    }
    text.resize(got);
    out = text;
    return out.c_str();
}
