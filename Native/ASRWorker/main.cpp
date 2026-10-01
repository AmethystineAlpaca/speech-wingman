#include "c-api.h"
#include "nlohmann/json.hpp"
#include "base64.hpp"
#include <iostream>
#include <string>
#include <vector>
#include <cstring>
#include <cmath>
#include <memory>
#include <stdexcept>
using json = nlohmann::json;

struct Recognizer {
    const SherpaOnnxOfflineRecognizer *recognizer = nullptr;
    const SherpaOnnxVoiceActivityDetector *vad = nullptr;
    std::vector<float> audio;
    std::string previous;
    int segment = 0;
    int64_t samples_seen = 0;
    int64_t last_decode = 0;
    bool speaking = false;
    ~Recognizer() {
        if (vad) SherpaOnnxDestroyVoiceActivityDetector(vad);
        if (recognizer) SherpaOnnxDestroyOfflineRecognizer(recognizer);
    }
    void load(const std::string &dir) {
        const std::string model = dir + "/model.int8.onnx", tokens = dir + "/tokens.txt";
        SherpaOnnxOfflineRecognizerConfig c{};
        c.feat_config.sample_rate = 16000; c.feat_config.feature_dim = 80;
        c.model_config.sense_voice.model = model.c_str();
        c.model_config.sense_voice.language = "auto"; c.model_config.sense_voice.use_itn = 1;
        c.model_config.tokens = tokens.c_str();
        c.model_config.num_threads = 2; c.model_config.provider = "cpu";
        c.decoding_method = "greedy_search";
        recognizer = SherpaOnnxCreateOfflineRecognizer(&c);
        if (!recognizer) throw std::runtime_error("cannot load multilingual ASR");
        const std::string vad_path = dir + "/silero_vad.onnx";
        SherpaOnnxVadModelConfig v{};
        v.silero_vad.model = vad_path.c_str(); v.silero_vad.threshold = 0.5f;
        v.silero_vad.min_silence_duration = 0.55f; v.silero_vad.min_speech_duration = 0.1f;
        v.silero_vad.max_speech_duration = 12.0f; v.silero_vad.window_size = 512;
        v.sample_rate = 16000; v.num_threads = 1; v.provider = "cpu";
        vad = SherpaOnnxCreateVoiceActivityDetector(&v, 30);
        if (!vad) throw std::runtime_error("cannot load local VAD");
    }
    void decode(bool final = false) {
        if (!speaking || audio.size() < 1600) return;
        auto stream = std::unique_ptr<const SherpaOnnxOfflineStream, decltype(&SherpaOnnxDestroyOfflineStream)>(
            SherpaOnnxCreateOfflineStream(recognizer), SherpaOnnxDestroyOfflineStream);
        if (!stream) throw std::runtime_error("cannot create ASR stream");
        SherpaOnnxAcceptWaveformOffline(stream.get(), 16000, audio.data(), audio.size());
        SherpaOnnxDecodeOfflineStream(recognizer, stream.get());
        auto result = std::unique_ptr<const SherpaOnnxOfflineRecognizerResult, decltype(&SherpaOnnxDestroyOfflineRecognizerResult)>(
            SherpaOnnxGetOfflineStreamResult(stream.get()), SherpaOnnxDestroyOfflineRecognizerResult);
        if (!result) throw std::runtime_error("ASR result unavailable");
        std::string text = result->text;
        if ((text != previous || final) && !text.empty()) {
            std::cout << json({{"type", "transcript"}, {"text", text}, {"final", final},
                {"segment", segment}, {"audio_seconds", samples_seen / 16000.0}}).dump() << std::endl;
        }
        previous = text; last_decode = samples_seen;
    }
    void close_segment() {
        decode(true);
        audio.clear(); previous.clear(); speaking = false; ++segment;
    }
    void accept(const json &request) {
        auto encoded = request.at("pcm_f32_base64").get<std::string>();
        if (encoded.size() > 90000) throw std::runtime_error("audio packet too large");
        std::vector<unsigned char> bytes;
        base64::decode(encoded.begin(), encoded.end(), std::back_inserter(bytes));
        if (bytes.empty() || bytes.size() % 4 || bytes.size() > 16000 * 4) throw std::runtime_error("invalid PCM packet");
        std::vector<float> samples(bytes.size() / 4);
        std::memcpy(samples.data(), bytes.data(), bytes.size());
        for (float v: samples) if (!std::isfinite(v) || std::abs(v) > 1.001f) throw std::runtime_error("invalid PCM samples");
        for (size_t offset = 0; offset < samples.size(); offset += 512) {
            auto count = std::min(size_t(512), samples.size() - offset);
            audio.insert(audio.end(), samples.begin() + offset, samples.begin() + offset + count);
            samples_seen += count;
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, samples.data() + offset, count);
            if (SherpaOnnxVoiceActivityDetectorDetected(vad)) speaking = true;
            if (!SherpaOnnxVoiceActivityDetectorEmpty(vad)) {
                close_segment(); SherpaOnnxVoiceActivityDetectorClear(vad);
            } else if (speaking && audio.size() >= 16000 * 15) {
                close_segment(); // bound continuous speech; each finalized window is evaluated independently
            } else if (speaking && samples_seen - last_decode >= 16000) {
                decode(); // replace the live preview approximately once per second
            } else if (!speaking && audio.size() > 6400) {
                audio.erase(audio.begin(), audio.end() - 6400); // 400 ms pre-roll preserves initial consonants
            }
        }
    }
};
int main(int argc, char **argv) {
    if (argc != 2) { std::cerr << "Usage: asr-worker MODEL_DIRECTORY\n"; return 2; }
    try {
        Recognizer r; r.load(argv[1]);
        std::cout << json({{"type", "ready"}}).dump() << std::endl;
        std::string line;
        while (std::getline(std::cin, line)) {
            if (line.size() > 100000) throw std::runtime_error("packet too large");
            auto request = json::parse(line);
            if (request.at("type") == "finish") {
                r.close_segment();
                std::cout << json({{"type", "finished"}}).dump() << std::endl;
                break;
            }
            if (request.at("type") != "audio") throw std::runtime_error("unsupported request");
            r.accept(request);
            std::cout << json({{"type", "ack"}}).dump() << std::endl;
        }
    } catch (const std::exception &e) {
        std::cout << json({{"type", "error"}, {"message", e.what()}}).dump() << std::endl;
        return 1;
    }
}
