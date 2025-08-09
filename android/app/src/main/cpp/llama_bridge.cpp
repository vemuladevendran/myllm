// llama_bridge.cpp (history + rolling window + overflow guard)
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
static llama_model*   g_model           = nullptr;
static llama_context* g_ctx             = nullptr;
static bool           g_backend_inited  = false;

static int32_t        g_seq_id          = 0;     // single chat thread
static int32_t        g_next_pos        = 0;     // next timestep to write
static int32_t        g_ctx_size        = 0;     // cached n_ctx

// Rolling token history (prompt + generations) for rebuilds
static std::vector<llama_token> g_history;

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

// KV clear compatible with your headers; switch to llama_memory_clear(ctx)
// if your llama.cpp version has it.
static inline void kv_clear(llama_context* ctx) {
    if (!ctx) return;
    // llama_memory_clear(ctx);   // <- newer llama.cpp
    llama_kv_self_clear(ctx);     // <- available in your headers
}

static std::string detokenize_to_string(const llama_vocab * vocab,
                                        const std::vector<llama_token> & toks,
                                        bool remove_special = true,
                                        bool unparse_special = false) {
    if (!vocab || toks.empty()) return std::string();

    int need = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                nullptr, 0, remove_special, unparse_special);
    if (need < 0) {
        int len = -need + 1;
        std::string out(len, '\0');
        int got = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                   out.data(), len, remove_special, unparse_special);
        if (got > 0 && got <= len) { out.resize(got); return out; }
        return std::string();
    } else if (need == 0) {
        return std::string();
    } else {
        std::string out(need, '\0');
        int got = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                   out.data(), need, remove_special, unparse_special);
        if (got > 0 && got <= need) { out.resize(got); return out; }
        return std::string();
    }
}

// Feed `toks` into the context at positions [start_pos, ...] for seq g_seq_id.
// We chunk to avoid creating enormous batches.
static bool feed_tokens(const llama_vocab* vocab,
                        const std::vector<llama_token>& toks,
                        int32_t start_pos,
                        int32_t chunk = 256,
                        bool request_logits_on_last = true) {
    if (toks.empty()) return true;

    int32_t pos = start_pos;
    for (size_t off = 0; off < toks.size(); off += (size_t)chunk) {
        const int32_t n = (int32_t)std::min<size_t>(chunk, toks.size() - off);
        llama_batch batch = llama_batch_init(n, /*embd*/0, /*n_seq_max*/1);

        for (int32_t i = 0; i < n; ++i) {
            const bool is_last_global = (off + i == toks.size() - 1);
            batch.token[i]     = toks[off + i];
            batch.pos[i]       = pos + i;
            batch.n_seq_id[i]  = 1;
            batch.seq_id[i][0] = g_seq_id;
            batch.logits[i]    = (is_last_global && request_logits_on_last) ? 1 : 0;
        }
        batch.n_tokens = n;

        const int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) return false;

        pos += n;
    }
    return true;
}

// Ensure we have space in KV to add `need_prompt` plus `need_gen` tokens.
// If not, we rebuild the KV with the **tail** of g_history (rolling window).
static bool ensure_capacity_for(const llama_vocab* vocab,
                                int32_t need_prompt,
                                int32_t need_gen) {
    if (g_ctx_size <= 0) {
        g_ctx_size = llama_n_ctx(g_ctx);
    }

    // A small safety margin so we never write exactly at end.
    const int32_t margin = 16;
    const int32_t needed_total = g_next_pos + need_prompt + std::max(need_gen, 0) + margin;

    if (needed_total < g_ctx_size) {
        return true; // we’re fine
    }

    // Need to rebuild: keep last window of history tokens that fits.
    // Keep ~70% of context to leave room for new turns.
    const int32_t target_keep = (int32_t)(g_ctx_size * 0.70);
    const int32_t keep = std::min<int32_t>((int32_t)g_history.size(), target_keep);

    std::vector<llama_token> tail;
    if (keep > 0) {
        tail.insert(tail.end(), g_history.end() - keep, g_history.end());
    }

    // Rebuild KV
    kv_clear(g_ctx);
    g_next_pos = 0;

    if (!tail.empty()) {
        if (!feed_tokens(vocab, tail, /*start_pos*/0, /*chunk*/256, /*request_logits_on_last*/false)) {
            LOGE("[ensure_capacity_for] rebuild feed failed");
            return false;
        }
        g_next_pos = keep;
        // Replace history with the kept tail
        g_history.swap(tail); // tail now holds old (to be discarded)
        tail.clear();
    } else {
        g_history.clear();
    }

    LOGI("[ensure_capacity_for] KV rebuilt, kept=%d, g_next_pos=%d, n_ctx=%d",
         keep, g_next_pos, g_ctx_size);

    // Re-check after rebuild
    const int32_t needed_total_after = g_next_pos + need_prompt + std::max(need_gen, 0) + margin;
    return needed_total_after < g_ctx_size;
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

    if (g_ctx)   { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }

    if (!g_backend_inited) {
        llama_backend_init();
        g_backend_inited = true;
        LOGI("[lb_load] llama_backend_init()");
    }

    llama_model_params mparams = llama_model_default_params();
    g_model = llama_model_load_from_file(model_path_cstr, mparams);
    if (!g_model) {
        LOGE("llama_model_load_from_file failed");
        return -2;
    }

    llama_context_params cparams = llama_context_default_params();
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed");
        llama_model_free(g_model); g_model = nullptr;
        return -3;
    }

    kv_clear(g_ctx);
    g_seq_id   = 0;
    g_next_pos = 0;
    g_ctx_size = llama_n_ctx(g_ctx);
    g_history.clear();

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    LOGI("model+context created OK (vocab=%d, n_ctx=%d)",
         vocab ? llama_vocab_n_tokens(vocab) : -1, g_ctx_size);
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
    g_seq_id   = 0;
    g_next_pos = 0;
    g_ctx_size = llama_n_ctx(g_ctx);
    g_history.clear();
    LOGI("[lb_reset] context recreated + KV cleared (history reset)");
    return 0;
}

// Clear history without recreating the context
extern "C" __attribute__((visibility("default")))
void lb_clear_history() {
    if (!g_ctx) return;
    kv_clear(g_ctx);
    g_seq_id   = 0;
    g_next_pos = 0;
    g_history.clear();
    LOGI("[lb_clear_history] KV cleared, positions reset");
}

// Greedy generation with persistent history + overflow guard
extern "C" __attribute__((visibility("default")))
const char* lb_eval(const char* prompt_cstr, int max_tokens) {
    static std::string result;
    result.clear();

    if (!g_ctx || !g_model) {
        result = "Model not loaded.";
        return result.c_str();
    }
    if (!prompt_cstr) prompt_cstr = "";
    if (max_tokens <= 0) max_tokens = 1;

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    if (!vocab) { result = "No vocab."; return result.c_str(); }
    if (g_ctx_size <= 0) g_ctx_size = llama_n_ctx(g_ctx);

    // --- Tokenize prompt ---
    const int prompt_len = (int) std::strlen(prompt_cstr);
    int32_t guess = std::max(32, prompt_len + 8);
    std::vector<llama_token> prompt_tokens(guess);

    int n_tok = llama_tokenize(vocab, prompt_cstr, prompt_len,
                               prompt_tokens.data(), guess,
                               /*add_special*/ 1, /*parse_special*/ 0);
    if (n_tok < 0) {
        int need = -n_tok;
        if (need <= 0) { result = "Tokenization failed."; return result.c_str(); }
        prompt_tokens.resize(need);
        n_tok = llama_tokenize(vocab, prompt_cstr, prompt_len,
                               prompt_tokens.data(), need, 1, 0);
        if (n_tok <= 0) { result = "Tokenization failed."; return result.c_str(); }
    } else {
        prompt_tokens.resize(n_tok);
    }

    // Make sure we have capacity (rolling window rebuild if needed)
    if (!ensure_capacity_for(vocab, /*need_prompt*/n_tok, /*need_gen*/max_tokens)) {
        result = "Context overflow.";
        return result.c_str();
    }

    // --- Feed prompt at current position ---
    if (!feed_tokens(vocab, prompt_tokens, /*start_pos*/g_next_pos, /*chunk*/256, /*request_logits_on_last*/true)) {
        result = "Decode failed on prompt.";
        return result.c_str();
    }

    // Store prompt into history
    g_history.insert(g_history.end(), prompt_tokens.begin(), prompt_tokens.end());

    // --- Generate ---
    std::vector<llama_token> gen;
    gen.reserve(std::max(1, max_tokens));

    int32_t cur_pos = g_next_pos + n_tok; // first generation position

    for (int t = 0; t < max_tokens; ++t) {
        float * logits = llama_get_logits_ith(g_ctx, -1);
        if (!logits) { result = "No logits."; return result.c_str(); }

        // greedy argmax
        int best_id = 0;
        float best_val = -std::numeric_limits<float>::infinity();
        const int32_t n_vocab = llama_vocab_n_tokens(vocab);
        for (int i = 0; i < n_vocab; ++i) {
            const float v = logits[i];
            if (v > best_val) { best_val = v; best_id = i; }
        }

        const llama_token next = (llama_token) best_id;
        if (llama_vocab_is_eog(vocab, next)) break;

        gen.push_back(next);

        // Feed back one-by-one (request logits each step)
        llama_batch batch = llama_batch_init(1, /*embd*/0, /*n_seq_max*/1);
        batch.token[0]     = next;
        batch.pos[0]       = cur_pos++;
        batch.n_seq_id[0]  = 1;
        batch.seq_id[0][0] = g_seq_id;
        batch.logits[0]    = 1;
        batch.n_tokens     = 1;

        const int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) break;

        // Guard: if generation is about to overflow ctx, stop early
        if (cur_pos + 16 >= g_ctx_size) {
            LOGI("[lb_eval] stopping early to avoid ctx overflow (cur_pos=%d, n_ctx=%d)", cur_pos, g_ctx_size);
            break;
        }
    }

    // Update rolling state
    g_history.insert(g_history.end(), gen.begin(), gen.end());
    g_next_pos = cur_pos;

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
    g_seq_id   = 0;
    g_next_pos = 0;
    g_ctx_size = 0;
    g_history.clear();
}
