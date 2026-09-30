#include "llama.h"
#include "nlohmann/json.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <sys/resource.h>
#include <vector>

using json = nlohmann::json;
static volatile sig_atomic_t interrupted = 0;
static void cancel_signal(int) { interrupted = 1; }
static bool should_abort(void *) { return interrupted != 0; }
static void log_sink(ggml_log_level, const char * text, void *) { std::cerr << text; }

// Fixed output format only. There are no policy keywords or semantic classifiers here.
static const char * grammar = R"GBNF(
root ::= "{" ws "\"decision\"" ws ":" ws (quiet | alert) ws "}" ws
quiet ::= "\"no_alert\"" | "\"defer\"" | "\"inconclusive\""
alert ::= "\"alert\"" ws "," ws "\"quote\"" ws ":" ws string ws "," ws "\"suggestion\"" ws ":" ws string
string ::= "\"" char* "\""
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
ws ::= [ \t\n\r]*
)GBNF";

struct Engine {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    double prefill_seconds = 0;
    double decode_seconds = 0;
    ~Engine() {
        if (context) llama_free(context);
        if (model) llama_model_free(model);
    }
    void load(const std::string & weights) {
        auto mp = llama_model_default_params(); mp.n_gpu_layers = 99;
        model = llama_model_load_from_file(weights.c_str(), mp);
        if (!model) throw std::runtime_error("cannot load local model");
        auto cp = llama_context_default_params();
        cp.n_ctx = 8192; cp.n_batch = 512; cp.n_ubatch = 256;
        cp.n_threads = 4; cp.n_threads_batch = 4;
        cp.abort_callback = should_abort;
        context = llama_init_from_model(model, cp);
        if (!context) throw std::runtime_error("cannot create model context");
    }
    void warmup() {
        evaluate(json({{"system", "Return a JSON decision."}, {"user", "No speech. /no_think"}}));
    }
    std::string evaluate(const json & request, bool warmup_only = false) {
        interrupted = 0;
        struct ClearCache { llama_context * ctx; ~ClearCache() { llama_memory_clear(llama_get_memory(ctx), true); } } clear{context};
        llama_memory_clear(llama_get_memory(context), true);
        const std::string system = request.at("system").get<std::string>();
        const std::string user = request.at("user").get<std::string>();
        if (system.size() + user.size() > 48'000) throw std::runtime_error("prompt too long");
        const llama_chat_message messages[] = {{"system", system.c_str()}, {"user", user.c_str()}};
        const char * chat = llama_model_chat_template(model, nullptr);
        int size = llama_chat_apply_template(chat, messages, 2, true, nullptr, 0);
        if (size < 0) throw std::runtime_error("unsupported chat template");
        std::vector<char> formatted(size + 1);
        llama_chat_apply_template(chat, messages, 2, true, formatted.data(), formatted.size());
        // Qwen3 Instruct 2507 has no thinking prefix.
        std::string prompt(formatted.data(), size);

        const auto vocab = llama_model_get_vocab(model);
        int count = llama_tokenize(vocab, prompt.data(), prompt.size(), nullptr, 0, true, true);
        if (count >= 0) throw std::runtime_error("tokenization failed");
        std::vector<llama_token> tokens(-count);
        count = llama_tokenize(vocab, prompt.data(), prompt.size(), tokens.data(), tokens.size(), true, true);
        if (count <= 0 || count + 160 >= 8192) throw std::runtime_error("context capacity exceeded");
        llama_pos past = count;
        const auto prefill_start = std::chrono::steady_clock::now();
        for (int offset = 0; offset < count; offset += 512) {
            auto batch = llama_batch_get_one(tokens.data() + offset, std::min(512, count - offset));
            if (llama_decode(context, batch) != 0) throw std::runtime_error(interrupted ? "cancelled" : "text prefill failed");
        }
        prefill_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - prefill_start).count();
        if (warmup_only) return "";
        const auto decode_start = std::chrono::steady_clock::now();
        struct DecodeTimer { double & elapsed; std::chrono::steady_clock::time_point start;
            ~DecodeTimer() { elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count(); }
        } decode_timer{decode_seconds, decode_start};
        auto sampler = std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)>(llama_sampler_chain_init(llama_sampler_chain_default_params()), llama_sampler_free);
        auto constrained = llama_sampler_init_grammar(vocab, grammar, "root");
        if (!constrained) throw std::runtime_error("invalid output grammar");
        llama_sampler_chain_add(sampler.get(), constrained);
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_greedy());
        std::string output;
        for (int generated = 0; generated < 160; ++generated) {
            if (interrupted) throw std::runtime_error("cancelled");
            auto token = llama_sampler_sample(sampler.get(), context, -1);
            if (llama_vocab_is_eog(vocab, token)) return output;
            std::vector<char> piece(256);
            int length = llama_token_to_piece(vocab, token, piece.data(), piece.size(), 0, false);
            if (length < 0) { piece.resize(-length); length = llama_token_to_piece(vocab, token, piece.data(), piece.size(), 0, false); }
            if (length < 0) throw std::runtime_error("token decoding failed");
            output.append(piece.data(), length);
            if (output.size() > 32'768) throw std::runtime_error("output too long");
            // Finish as soon as a complete object is available; never salvage truncated JSON.
            if (!json::parse(output, nullptr, false).is_discarded()) return output;
            auto batch = llama_batch_get_one(&token, 1);
            if (llama_decode(context, batch) != 0) throw std::runtime_error(interrupted ? "cancelled" : "decode failed");
            ++past;
        }
        throw std::runtime_error("output token budget exceeded");
    }
};

int main(int argc, char ** argv) {
    if (argc != 2) { std::cerr << "Usage: text-worker MODEL.gguf\n"; return 2; }
    std::signal(SIGUSR1, cancel_signal);
    llama_log_set(log_sink, nullptr);
    llama_backend_init();
    try {
        Engine engine; engine.load(argv[1]); engine.warmup();
        std::cout << json({{"type", "ready"}}).dump() << std::endl;
        std::string line;
        while (std::getline(std::cin, line)) {
            std::string id;
            try {
                if (line.size() > 3'000'000) throw std::runtime_error("request too large");
                const auto request = json::parse(line);
                id = request.at("id").get<std::string>();
                if (request.at("type") == "shutdown") break;
                if (request.at("type") != "evaluate") throw std::runtime_error("unsupported request");
                const auto start = std::chrono::steady_clock::now();
                const auto result = engine.evaluate(request);
                double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
                struct rusage usage{}; getrusage(RUSAGE_SELF, &usage);
                std::cout << json({{"type", "result"}, {"id", id}, {"output", result}, {"elapsed_seconds", elapsed},
                    {"prefill_seconds", engine.prefill_seconds}, {"decode_seconds", engine.decode_seconds},
                    {"peak_rss_bytes", usage.ru_maxrss}}).dump() << std::endl;
            } catch (const std::exception & e) {
                std::cout << json({{"type", "error"}, {"id", id}, {"message", e.what()}}).dump() << std::endl;
            }
            line.clear();
        }
    } catch (const std::exception & e) {
        std::cout << json({{"type", "error"}, {"id", ""}, {"message", e.what()}}).dump() << std::endl;
        return 1;
    }
    llama_backend_free();
    return 0;
}
