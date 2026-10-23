// ONNX Runtime 桥接：只暴露 C ABI，供 Swift 调用。
// 输入输出缓冲由本模块 malloc，调用方用 lo_engine_free_buffer / lo_engine_free_string 释放。
#ifndef LO_ORT_BRIDGE_H
#define LO_ORT_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LOEngine LOEngine;

/// 创建引擎：encoder / decoder 为 ONNX 模型路径。
/// 失败返回 NULL，并在 err 中写入 UTF-8 错误信息。
LOEngine *lo_engine_create(const char *encoder_path, const char *decoder_path, char **err);

/// 释放引擎（会等待进行中的调用结束）。
void lo_engine_destroy(LOEngine *engine);

/// 编码：ids 为 token id 序列（长度 n）。输出 [1, n, hidden] 的 float 缓冲。
int32_t lo_engine_encode(LOEngine *engine,
                         const int64_t *ids,
                         int32_t n,
                         float **out,
                         int32_t *out_len,
                         int32_t *hidden_dim,
                         char **err);

/// 解码：把完整前缀 ids（长度 n）送入 decoder，返回最后一个位置的 logits。
/// encoder 为 lo_engine_encode 的输出，enc_len 为编码长度。
int32_t lo_engine_decode(LOEngine *engine,
                         const int64_t *ids,
                         int32_t n,
                         const float *encoder,
                         int32_t enc_len,
                         float **logits,
                         int32_t *vocab_size,
                         char **err);

void lo_engine_free_buffer(void *buffer);
void lo_engine_free_string(char *string);

/// 引擎内部配置：推理线程数（0 表示自动）
void lo_engine_set_threads(LOEngine *engine, int32_t threads);

#ifdef __cplusplus
}
#endif

#endif
