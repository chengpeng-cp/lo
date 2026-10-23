#include "ORTBridge.h"

#include <onnxruntime_cxx_api.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

char *copy_string(const std::string &text) {
    char *out = static_cast<char *>(std::malloc(text.size() + 1));
    if (out) std::memcpy(out, text.c_str(), text.size() + 1);
    return out;
}

void set_error(char **err, const std::string &message) {
    if (err) *err = copy_string(message);
}

std::vector<std::string> input_names(Ort::Session &session) {
    Ort::AllocatorWithDefaultOptions allocator;
    std::vector<std::string> names;
    const size_t count = session.GetInputCount();
    names.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        names.emplace_back(session.GetInputNameAllocated(i, allocator).get());
    }
    return names;
}

std::vector<std::string> output_names(Ort::Session &session) {
    Ort::AllocatorWithDefaultOptions allocator;
    std::vector<std::string> names;
    const size_t count = session.GetOutputCount();
    names.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        names.emplace_back(session.GetOutputNameAllocated(i, allocator).get());
    }
    return names;
}

}  // namespace

struct LOEngine {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "LOMTEngine"};
    Ort::SessionOptions options;
    std::unique_ptr<Ort::Session> encoder;
    std::unique_ptr<Ort::Session> decoder;

    std::vector<std::string> encoder_inputs;
    std::vector<std::string> decoder_inputs;
    std::string encoder_output;
    std::string decoder_output;

    int32_t hidden_dim = 0;
    std::mutex lock;

    void configure_options(int32_t threads) {
        int32_t count = threads;
        if (count <= 0) {
            const unsigned hw = std::thread::hardware_concurrency();
            count = static_cast<int32_t>(std::min<unsigned>(4, std::max<unsigned>(1, hw)));
        }
        options.SetIntraOpNumThreads(count);
        options.SetInterOpNumThreads(1);
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    }
};

LOEngine *lo_engine_create(const char *encoder_path, const char *decoder_path, char **err) {
    if (!encoder_path || !decoder_path) {
        set_error(err, "模型路径为空");
        return nullptr;
    }
    try {
        auto *engine = new LOEngine();
        engine->configure_options(0);
        engine->encoder = std::make_unique<Ort::Session>(engine->env, encoder_path, engine->options);
        engine->decoder = std::make_unique<Ort::Session>(engine->env, decoder_path, engine->options);
        engine->encoder_inputs = input_names(*engine->encoder);
        engine->decoder_inputs = input_names(*engine->decoder);

        auto encoder_outputs = output_names(*engine->encoder);
        auto decoder_outputs = output_names(*engine->decoder);
        if (encoder_outputs.empty() || decoder_outputs.empty()) {
            set_error(err, "模型缺少输出节点");
            delete engine;
            return nullptr;
        }
        engine->encoder_output = encoder_outputs.front();
        engine->decoder_output = decoder_outputs.front();
        return engine;
    } catch (const Ort::Exception &e) {
        set_error(err, std::string("加载模型失败：") + e.what());
        return nullptr;
    } catch (const std::exception &e) {
        set_error(err, std::string("加载模型失败：") + e.what());
        return nullptr;
    }
}

void lo_engine_destroy(LOEngine *engine) {
    if (!engine) return;
    delete engine;
}

void lo_engine_set_threads(LOEngine *engine, int32_t threads) {
    if (!engine) return;
    engine->configure_options(threads);
}

int32_t lo_engine_encode(LOEngine *engine,
                         const int64_t *ids,
                         int32_t n,
                         float **out,
                         int32_t *out_len,
                         int32_t *hidden_dim,
                         char **err) {
    if (!engine || !ids || n <= 0 || !out) {
        set_error(err, "编码参数无效");
        return -1;
    }
    std::lock_guard<std::mutex> guard(engine->lock);
    try {
        Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        const std::array<int64_t, 2> shape{1, n};
        std::vector<int64_t> mask(static_cast<size_t>(n), 1);

        std::vector<Ort::Value> feeds;
        for (const auto &name : engine->encoder_inputs) {
            if (name == "input_ids") {
                feeds.push_back(Ort::Value::CreateTensor<int64_t>(
                    memory, const_cast<int64_t *>(ids), static_cast<size_t>(n), shape.data(), shape.size()));
            } else if (name == "attention_mask") {
                feeds.push_back(Ort::Value::CreateTensor<int64_t>(
                    memory, mask.data(), mask.size(), shape.data(), shape.size()));
            } else {
                set_error(err, "编码器存在未知输入：" + name);
                return -1;
            }
        }

        std::vector<const char *> names;
        names.reserve(engine->encoder_inputs.size());
        for (const auto &name : engine->encoder_inputs) names.push_back(name.c_str());
        const char *output_name = engine->encoder_output.c_str();

        auto outputs = engine->encoder->Run(Ort::RunOptions{nullptr}, names.data(), feeds.data(),
                                            feeds.size(), &output_name, 1);
        auto info = outputs.front().GetTensorTypeAndShapeInfo();
        auto dims = info.GetShape();
        if (dims.size() != 3) {
            set_error(err, "编码器输出维度不是 3");
            return -1;
        }
        const size_t total = static_cast<size_t>(dims[0] * dims[1] * dims[2]);
        const float *data = outputs.front().GetTensorData<float>();
        auto *buffer = static_cast<float *>(std::malloc(total * sizeof(float)));
        if (!buffer) {
            set_error(err, "内存不足");
            return -1;
        }
        std::memcpy(buffer, data, total * sizeof(float));
        *out = buffer;
        *out_len = static_cast<int32_t>(dims[1]);
        *hidden_dim = static_cast<int32_t>(dims[2]);
        engine->hidden_dim = *hidden_dim;
        return 0;
    } catch (const Ort::Exception &e) {
        set_error(err, std::string("编码失败：") + e.what());
        return -1;
    } catch (const std::exception &e) {
        set_error(err, std::string("编码失败：") + e.what());
        return -1;
    }
}

int32_t lo_engine_decode(LOEngine *engine,
                         const int64_t *ids,
                         int32_t n,
                         const float *encoder,
                         int32_t enc_len,
                         float **logits,
                         int32_t *vocab_size,
                         char **err) {
    if (!engine || !ids || n <= 0 || !encoder || enc_len <= 0 || !logits) {
        set_error(err, "解码参数无效");
        return -1;
    }
    std::lock_guard<std::mutex> guard(engine->lock);
    try {
        Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        const std::array<int64_t, 2> token_shape{1, n};
        const std::array<int64_t, 2> mask_shape{1, enc_len};
        const std::array<int64_t, 3> hidden_shape{1, enc_len, engine->hidden_dim};
        std::vector<int64_t> mask(static_cast<size_t>(enc_len), 1);

        std::vector<Ort::Value> feeds;
        for (const auto &name : engine->decoder_inputs) {
            if (name == "input_ids") {
                feeds.push_back(Ort::Value::CreateTensor<int64_t>(
                    memory, const_cast<int64_t *>(ids), static_cast<size_t>(n), token_shape.data(), 2));
            } else if (name == "encoder_attention_mask") {
                feeds.push_back(Ort::Value::CreateTensor<int64_t>(
                    memory, mask.data(), mask.size(), mask_shape.data(), 2));
            } else if (name == "encoder_hidden_states") {
                feeds.push_back(Ort::Value::CreateTensor<float>(
                    memory, const_cast<float *>(encoder),
                    static_cast<size_t>(enc_len) * static_cast<size_t>(engine->hidden_dim),
                    hidden_shape.data(), 3));
            } else {
                set_error(err, "解码器存在未知输入：" + name);
                return -1;
            }
        }

        std::vector<const char *> names;
        names.reserve(engine->decoder_inputs.size());
        for (const auto &name : engine->decoder_inputs) names.push_back(name.c_str());
        const char *output_name = engine->decoder_output.c_str();

        auto outputs = engine->decoder->Run(Ort::RunOptions{nullptr}, names.data(), feeds.data(),
                                            feeds.size(), &output_name, 1);
        auto info = outputs.front().GetTensorTypeAndShapeInfo();
        auto dims = info.GetShape();
        if (dims.size() != 3) {
            set_error(err, "解码器输出维度不是 3");
            return -1;
        }
        const int64_t vocab = dims[2];
        const float *data = outputs.front().GetTensorData<float>();
        const float *last = data + (dims[1] - 1) * vocab;
        auto *buffer = static_cast<float *>(std::malloc(static_cast<size_t>(vocab) * sizeof(float)));
        if (!buffer) {
            set_error(err, "内存不足");
            return -1;
        }
        std::memcpy(buffer, last, static_cast<size_t>(vocab) * sizeof(float));
        *logits = buffer;
        *vocab_size = static_cast<int32_t>(vocab);
        return 0;
    } catch (const Ort::Exception &e) {
        set_error(err, std::string("解码失败：") + e.what());
        return -1;
    } catch (const std::exception &e) {
        set_error(err, std::string("解码失败：") + e.what());
        return -1;
    }
}

void lo_engine_free_buffer(void *buffer) {
    std::free(buffer);
}

void lo_engine_free_string(char *string) {
    std::free(string);
}
