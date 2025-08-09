// llama_bridge.cpp
#include <android/log.h>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <vector>
#include <algorithm>
#include <llama.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "llama_bridge", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "llama_bridge", __VA_ARGS__)

// -----------------------------------------------------------------------------
// Globals
// -----------------------------------------------------------------------------
static llama_model*   g_model          = nullptr;
static llama_context* g_ctx            = nullptr;
static bool           g_backend_inited = false;

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

// Version-compat KV clear: your headers expose llama_kv_self_clear (deprecated)
// If you later update to a llama.cpp that has llama_memory_clear(ctx), switch below.
static inline void kv_clear(llama_context* ctx) {
    if (!ctx) return;
    // Preferred on newer llama.cpp:
    // llama_memory_clear(ctx);
    // Compatible with your current headers:
    llama_kv_self_clear(ctx);
}

static std::string detokenize_to_string(const llama_vocab * vocab,
                                        const std::vector<llama_token> & toks,
                                        bool remove_special = true,
                                        bool unparse_special = false) {
    if (!vocab || toks.empty()) return std::string();

    // First pass: required size (negative means buffer size needed)
    int need = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                nullptr, 0,
                                remove_special, unparse_special);
    if (need < 0) {
        int len = -need + 1; // safety slack
        std::string out;
        out.resize(len);
        int got = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                   out.data(), len,
                                   remove_special, unparse_special);
        if (got > 0 && got <= len) {
            out.resize(got);
            return out;
        }
        return std::string();
    } else if (need == 0) {
        return std::string();
    } else {
        // very small outputs may return exact size
        std::string out;
        out.resize(need);
        int got = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                   out.data(), need,
                                   remove_special, unparse_special);
        if (got > 0 && got <= need) {
            out.resize(got);
            return out;
        }
        return std::string();
    }
}

// -----------------------------------------------------------------------------
// C API
// -----------------------------------------------------------------------------
extern "C" __attribute__((visibility("default")))
int lb_load(const char* model_path_cstr) {
    LOGI("[lb_load] path: %s", model_path_cstr ? model_path_cstr : "(null)");
    if (!model_path_cstr || model_path_cstr[0] == '\0') {
        LOGE("[lb_load] invalid model path");
        return -1;
    }

    // Dispose any existing
    if (g_ctx)   { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }

    // Initialize backend once per process
    if (!g_backend_inited) {
        llama_backend_init();
        g_backend_inited = true;
        LOGI("[lb_load] llama_backend_init()");
    }

    // Model params
    llama_model_params mparams = llama_model_default_params();
    // mparams.use_mmap  = true;   // enable if desired
    // mparams.use_mlock = false;  // enable to pin

    g_model = llama_model_load_from_file(model_path_cstr, mparams);
    if (!g_model) {
        LOGE("llama_model_load_from_file failed");
        return -2;
    }

    // Context params
    llama_context_params cparams = llama_context_default_params();
    // Optional tuning (uncomment if you want):
    // cparams.n_threads = std::max(1u, std::thread::hardware_concurrency());
    // cparams.n_batch   = 512;

    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed");
        llama_model_free(g_model); g_model = nullptr;
        return -3;
    }

    kv_clear(g_ctx);

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    LOGI("model+context created OK (vocab=%d)", vocab ? llama_vocab_n_tokens(vocab) : -1);
    return 0;
}

extern "C" __attribute__((visibility("default")))
int lb_is_loaded() {
    return (g_ctx && g_model) ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
int lb_reset() {
    LOGI("[lb_reset]");
    if (!g_model) {
        LOGE("[lb_reset] no model loaded");
        return -1;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    llama_context_params cparams = llama_context_default_params();
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("[lb_reset] llama_init_from_model failed");
        return -2;
    }
    kv_clear(g_ctx);
    LOGI("[lb_reset] context recreated + KV cleared");
    return 0;
}

// Greedy generation using logits -> argmax
extern "C" __attribute__((visibility("default")))
const char* lb_eval(const char* prompt_cstr, int max_tokens) {
    static std::string result;
    result.clear();

    if (!g_ctx || !g_model) {
        result = "Model not loaded.";
        return result.c_str();
    }
    kv_clear(g_ctx);
    if (!prompt_cstr) prompt_cstr = "";
    if (max_tokens <= 0) max_tokens = 1;

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    if (!vocab) {
        result = "No vocab.";
        return result.c_str();
    }
    const int32_t n_vocab = llama_vocab_n_tokens(vocab);

    // --- Tokenize prompt ---
    const int prompt_len = (int) std::strlen(prompt_cstr);
    int32_t guess = std::max(32, prompt_len + 8);
    std::vector<llama_token> prompt_tokens(guess);

    int n_tok = llama_tokenize(
        vocab,
        prompt_cstr,
        prompt_len,
        prompt_tokens.data(),
        guess,
        /*add_special*/ 1,
        /*parse_special*/ 0
    );
    if (n_tok < 0) {
        // need a bigger buffer
        int need = -n_tok;
        if (need <= 0) {
            result = "Tokenization failed.";
            return result.c_str();
        }
        prompt_tokens.resize(need);
        n_tok = llama_tokenize(
            vocab,
            prompt_cstr,
            prompt_len,
            prompt_tokens.data(),
            need,
            1, 0
        );
        if (n_tok <= 0) {
            result = "Tokenization failed.";
            return result.c_str();
        }
    } else {
        prompt_tokens.resize(n_tok);
    }

    // --- Feed prompt (REQUIRED: set pos[] and n_tokens) ---
    {
        llama_batch batch = llama_batch_init(n_tok, /*embd*/0, /*n_seq_max*/1);

        for (int i = 0; i < n_tok; ++i) {
            batch.token[i]     = prompt_tokens[i];
            batch.pos[i]       = i;           // position / timestep
            batch.n_seq_id[i]  = 1;
            batch.seq_id[i][0] = 0;           // single sequence id 0
            batch.logits[i]    = (i == n_tok - 1) ? 1 : 0; // logits only on last
        }
        batch.n_tokens = n_tok;               // how many entries are valid

        const int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) {
            result = "Decode failed on prompt.";
            return result.c_str();
        }
    }

    // --- Generate ---
    std::vector<llama_token> gen;
    gen.reserve(std::max(1, max_tokens));

    int32_t cur_pos = n_tok; // next position after the prompt

    for (int t = 0; t < max_tokens; ++t) {
        float * logits = llama_get_logits_ith(g_ctx, -1);
        if (!logits) {
            result = "No logits.";
            return result.c_str();
        }

        // greedy argmax
        int best_id = 0;
        float best_val = -std::numeric_limits<float>::infinity();
        for (int i = 0; i < n_vocab; ++i) {
            const float v = logits[i];
            if (v > best_val) { best_val = v; best_id = i; }
        }

        const llama_token next = (llama_token) best_id;
        if (llama_vocab_is_eog(vocab, next)) break;

        gen.push_back(next);

        // feed back sampled token (set pos + n_tokens)
        llama_batch batch = llama_batch_init(1, /*embd*/0, /*n_seq_max*/1);
        batch.token[0]     = next;
        batch.pos[0]       = cur_pos++;   // advance position
        batch.n_seq_id[0]  = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0]    = 1;           // request next-step logits
        batch.n_tokens     = 1;

        const int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) {
            // stop gracefully on decode error during gen
            break;
        }
    }

    // --- Detokenize generated tokens only ---
    result = detokenize_to_string(vocab, gen, /*remove_special*/true, /*unparse_special*/false);
    return result.c_str();
}

extern "C" __attribute__((visibility("default")))
void lb_free() {
    LOGI("[lb_free]");
    if (g_ctx)   { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
    if (g_backend_inited) {
        llama_backend_free();
        g_backend_inited = false;
    }
}
