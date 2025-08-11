// android/app/src/main/cpp/llama_bridge.cpp
#include <android/log.h>
#include <string>
#include <vector>
#include <cstring>
#include <limits>
#include <llama.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "llama_bridge", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "llama_bridge", __VA_ARGS__)

// -----------------------------------------------------------------------------
// Globals
// -----------------------------------------------------------------------------
static llama_model*   g_model = nullptr;
static llama_context* g_ctx   = nullptr;

// streaming state
static bool g_stream_running = false;
static int  g_stream_remaining = 0;
static std::vector<llama_token> g_stream_prompt;
static std::vector<llama_token> g_stream_gen;
static int  g_stream_pos = 0;                   // absolute position in sequence
static size_t g_stream_emitted_chars = 0;       // how many chars already sent to client

// ------------------------------ Tunables ---------------------------------
static const int   EARLY_MIN_CHARS      = 16;   // don’t stop too early
static const int   EARLY_MIN_TOKENS     = 8;
static const bool  STOP_ON_DOUBLE_NL    = true;
static const bool  STOP_ON_SENTENCE_END = true; // stop after .!? if enough text

// ------------------------------ Utils -----------------------------------
static std::string detok(const llama_vocab * vocab,
                         const std::vector<llama_token> & toks,
                         bool remove_special = true,
                         bool unparse_special = false) {
    if (toks.empty()) return {};
    int need = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                nullptr, 0, remove_special, unparse_special);
    if (need < 0) {
        int len = -need + 1;
        std::string out(len, '\0');
        int got = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                   out.data(), len, remove_special, unparse_special);
        if (got > 0 && got <= len) { out.resize(got); return out; }
        return {};
    } else if (need == 0) {
        return {};
    } else {
        std::string out(need, '\0');
        int got = llama_detokenize(vocab, toks.data(), (int32_t)toks.size(),
                                   out.data(), need, remove_special, unparse_special);
        if (got > 0 && got <= need) { out.resize(got); return out; }
        return {};
    }
}

static inline void kv_clear() {
    // If your headers have llama_memory_clear(g_ctx), prefer that.
    // This call exists across many versions (deprecated on newest).
    llama_kv_self_clear(g_ctx);
}

static void stream_reset() {
    g_stream_running = false;
    g_stream_remaining = 0;
    g_stream_prompt.clear();
    g_stream_gen.clear();
    g_stream_pos = 0;
    g_stream_emitted_chars = 0;
}

static bool should_stop_early(const std::string &full_text, int n_gen_tokens) {
    if ((int)full_text.size() < EARLY_MIN_CHARS || n_gen_tokens < EARLY_MIN_TOKENS) return false;
    if (STOP_ON_DOUBLE_NL) {
        if (full_text.find("\n\n") != std::string::npos) return true;
    }
    if (STOP_ON_SENTENCE_END) {
        char c = full_text.empty() ? '\0' : full_text.back();
        if (c == '.' || c == '!' || c == '?') return true;
    }
    return false;
}

// ----------------------------- Lifecycle --------------------------------
extern "C" __attribute__((visibility("default")))
int lb_load(const char* model_path_cstr) {
    LOGI("[lb_load] path: %s", model_path_cstr ? model_path_cstr : "(null)");
    if (!model_path_cstr || model_path_cstr[0] == '\0') return -1;

    if (g_ctx)   { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }

    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();
    g_model = llama_model_load_from_file(model_path_cstr, mparams);
    if (!g_model) {
        LOGE("llama_model_load_from_file failed");
        llama_backend_free();
        return -2;
    }

    llama_context_params cparams = llama_context_default_params();
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed");
        llama_model_free(g_model); g_model = nullptr;
        llama_backend_free();
        return -3;
    }

    stream_reset();
    LOGI("model+context created OK");
    return 0;
}

extern "C" __attribute__((visibility("default")))
int lb_is_loaded() { return (g_ctx && g_model) ? 1 : 0; }

extern "C" __attribute__((visibility("default")))
int lb_reset() {
    if (!g_model) return -1;
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    llama_context_params cparams = llama_context_default_params();
    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) return -2;
    stream_reset();
    return 0;
}

extern "C" __attribute__((visibility("default")))
void lb_free() {
    stream_reset();
    if (g_ctx)   { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
    llama_backend_free();
}

extern "C" __attribute__((visibility("default")))
void lb_clear_history() {
    if (!g_ctx) return;
    kv_clear();
    stream_reset();
}

// --------------------------- Non-streaming -------------------------------
extern "C" __attribute__((visibility("default")))
const char* lb_eval(const char* prompt_cstr, int max_tokens) {
    static std::string result; result.clear();
    if (!g_ctx || !g_model) { result = "Model not loaded."; return result.c_str(); }
    if (!prompt_cstr) prompt_cstr = "";

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    const int32_t n_vocab = llama_vocab_n_tokens(vocab);

    // tokenize prompt
    const int prompt_len = (int) std::strlen(prompt_cstr);
    int32_t guess = std::max(32, prompt_len + 8);
    std::vector<llama_token> prompt_tokens(guess);
    int n_tok = llama_tokenize(vocab, prompt_cstr, prompt_len,
                               prompt_tokens.data(), guess, 1, 0);
    if (n_tok < 0) {
        int need = -n_tok;
        prompt_tokens.resize(need);
        n_tok = llama_tokenize(vocab, prompt_cstr, prompt_len,
                               prompt_tokens.data(), need, 1, 0);
        if (n_tok <= 0) { result = "Tokenization failed."; return result.c_str(); }
    } else {
        prompt_tokens.resize(n_tok);
    }

    // feed prompt (set pos[] and n_tokens)
    {
        kv_clear();
        const int n = (int)prompt_tokens.size();
        llama_batch batch = llama_batch_init(n, 0, 1);
        for (int i = 0; i < n; ++i) {
            batch.token[i]    = prompt_tokens[i];
            batch.pos[i]      = i;
            batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0;
            batch.logits[i]   = (i == n - 1) ? 1 : 0;
        }
        batch.n_tokens = n;
        int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) { result = "Decode failed on prompt."; return result.c_str(); }
    }

    std::vector<llama_token> gen; gen.reserve(std::max(1, max_tokens));
    size_t emitted_chars = 0; // for incremental detok

    for (int t = 0; t < max_tokens; ++t) {
        float * logits = llama_get_logits_ith(g_ctx, -1);
        if (!logits) { result = "No logits."; return result.c_str(); }

        // greedy argmax
        int best_id = 0;
        float best_val = -std::numeric_limits<float>::infinity();
        for (int i = 0; i < n_vocab; ++i) {
            const float v = logits[i];
            if (v > best_val) { best_val = v; best_id = i; }
        }
        const llama_token next = (llama_token)best_id;
        if (llama_vocab_is_eog(vocab, next)) break;

        gen.push_back(next);

        // feed back next token (set pos[] and n_tokens)
        {
            llama_batch batch = llama_batch_init(1, 0, 1);
            batch.token[0]    = next;
            batch.pos[0]      = (int)prompt_tokens.size() + (int)gen.size() - 1;
            batch.n_seq_id[0] = 1; batch.seq_id[0][0] = 0;
            batch.logits[0]   = 1;
            batch.n_tokens    = 1;
            int32_t rc = llama_decode(g_ctx, batch);
            llama_batch_free(batch);
            if (rc != 0) break;
        }

        // Incremental detok by diff (keeps spaces/punctuation correct)
        std::string full = detok(vocab, gen, true, false);
        if (full.size() > emitted_chars) {
            result += full.substr(emitted_chars);
            emitted_chars = full.size();
        }

        // Early stop heuristic
        if (should_stop_early(result, (int)gen.size())) break;
    }

    return result.c_str();
}

// ------------------------------ Streaming --------------------------------
extern "C" __attribute__((visibility("default")))
int lb_stream_begin(const char* prompt_cstr, int max_tokens) {
    if (!g_ctx || !g_model) return -1;
    if (!prompt_cstr) prompt_cstr = "";

    stream_reset();

    const llama_vocab * vocab = llama_model_get_vocab(g_model);

    // tokenize prompt
    const int prompt_len = (int) std::strlen(prompt_cstr);
    int32_t guess = std::max(32, prompt_len + 8);
    g_stream_prompt.resize(guess);
    int n_tok = llama_tokenize(vocab, prompt_cstr, prompt_len,
                               g_stream_prompt.data(), guess, 1, 0);
    if (n_tok < 0) {
        int need = -n_tok;
        g_stream_prompt.resize(need);
        n_tok = llama_tokenize(vocab, prompt_cstr, prompt_len,
                               g_stream_prompt.data(), need, 1, 0);
        if (n_tok <= 0) return -2;
    } else {
        g_stream_prompt.resize(n_tok);
    }

    // fresh KV + reset counters
    kv_clear();
    g_stream_pos = 0;
    g_stream_emitted_chars = 0;

    // feed prompt (set pos[] and n_tokens)
    {
        const int n = (int)g_stream_prompt.size();
        llama_batch batch = llama_batch_init(n, 0, 1);
        for (int i = 0; i < n; ++i) {
            batch.token[i]    = g_stream_prompt[i];
            batch.pos[i]      = g_stream_pos + i;
            batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0;
            batch.logits[i]   = (i == n - 1) ? 1 : 0;
        }
        batch.n_tokens = n;
        int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) return -3;
        g_stream_pos += n;
    }

    g_stream_running   = true;
    g_stream_remaining = std::max(1, max_tokens);
    g_stream_gen.clear();
    return 0;
}

// returns: nullptr=hard error; ""=no new chars yet / finished; else text delta to append
extern "C" __attribute__((visibility("default")))
const char* lb_stream_next() {
    static std::string delta; delta.clear();

    if (!g_ctx || !g_model) return nullptr;
    if (!g_stream_running)  { return ""; }
    if (g_stream_remaining <= 0) {
        g_stream_running = false; return "";
    }

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    const int32_t n_vocab = llama_vocab_n_tokens(vocab);

    float * logits = llama_get_logits_ith(g_ctx, -1);
    if (!logits) { g_stream_running = false; return nullptr; }

    // greedy argmax
    int best_id = 0;
    float best_val = -std::numeric_limits<float>::infinity();
    for (int i = 0; i < n_vocab; ++i) {
        const float v = logits[i];
        if (v > best_val) { best_val = v; best_id = i; }
    }
    const llama_token next = (llama_token)best_id;
    if (llama_vocab_is_eog(vocab, next)) {
        g_stream_running = false;
        return "";
    }

    g_stream_gen.push_back(next);

    // feed it back (set pos[] and n_tokens)
    {
        llama_batch batch = llama_batch_init(1, 0, 1);
        batch.token[0]    = next;
        batch.pos[0]      = g_stream_pos;
        batch.n_seq_id[0] = 1; batch.seq_id[0][0] = 0;
        batch.logits[0]   = 1;
        batch.n_tokens    = 1;
        int32_t rc = llama_decode(g_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) { g_stream_running = false; return nullptr; }
        g_stream_pos += 1;
    }

    g_stream_remaining -= 1;

    // Incremental detok: detok full gen then emit only the new chars
    std::string full = detok(vocab, g_stream_gen, true, false);
    if (full.size() > g_stream_emitted_chars) {
        delta = full.substr(g_stream_emitted_chars);
        g_stream_emitted_chars = full.size();
    } else {
        delta.clear();
    }

    // Early stop
    if (should_stop_early(full, (int)g_stream_gen.size())) {
        g_stream_running = false;
    }

    return delta.c_str();
}

extern "C" __attribute__((visibility("default")))
int lb_stream_is_running() { return g_stream_running ? 1 : 0; }

extern "C" __attribute__((visibility("default")))
void lb_stream_cancel() {
    stream_reset();
}
