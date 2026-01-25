# 升级到 b7785 的关键修改清单

**文件**: `custom_files/localllm_capi.cpp`
**当前 llama.cpp 版本**: b5421
**目标版本**: b7785

---

## 🚨 必须修改的代码（破坏性变化）

### 1. **KV Cache API → Memory API** ⚠️ **高优先级**

你的代码中有 **5 处** 使用了已弃用的 `llama_kv_self_*` 函数，这些在 b7785 中**已重命名**为 `llama_memory_*`。

#### 发现的使用位置：

| 行号 | 当前代码 (b5421) | 必须改为 (b7785) |
|------|-----------------|-----------------|
| **372** | `llama_kv_self_clear(ctx);` | `llama_memory_clear(llama_get_memory(ctx), false);` |
| **538** | `llama_kv_self_clear(ctx);` | `llama_memory_clear(llama_get_memory(ctx), false);` |
| **577** | `llama_kv_self_clear(ctx);` | `llama_memory_clear(llama_get_memory(ctx), false);` |
| **749** | `llama_kv_self_seq_rm(ctx, slot.seq_id, 0, -1);` | `llama_memory_seq_rm(llama_get_memory(ctx), slot.seq_id, 0, -1);` |
| **837** | `llama_kv_self_seq_cp(ctx, 0, slot.seq_id, -1, -1);` | `llama_memory_seq_cp(llama_get_memory(ctx), 0, slot.seq_id, -1, -1);` |
| **842** | `llama_kv_self_seq_rm(ctx, slot.seq_id, 0, -1);` | `llama_memory_seq_rm(llama_get_memory(ctx), slot.seq_id, 0, -1);` |
| **1078** | `llama_kv_self_seq_rm(ctx, 0, 0, -1);` | `llama_memory_seq_rm(llama_get_memory(ctx), 0, 0, -1);` |
| **1106** | `llama_kv_self_clear(ctx);` | `llama_memory_clear(llama_get_memory(ctx), false);` |

#### 详细修改方案：

**位置 1: localllm_generate() 第 372 行**
```cpp
// b5421 (旧)
llama_kv_self_clear(ctx);

// b7785 (新)
llama_memory_t mem = llama_get_memory(ctx);
llama_memory_clear(mem, false);
```

**位置 2-4: localllm_generate_parallel() 多处**
```cpp
// 在函数开始处添加 memory 句柄
llama_memory_t mem = llama_get_memory(ctx);

// 然后替换所有调用：
// 第 538 行
llama_memory_clear(mem, false);

// 第 577 行（错误处理中）
llama_memory_clear(mem, false);

// 第 749 行
llama_memory_seq_rm(mem, slot.seq_id, 0, -1);

// 第 837 行
llama_memory_seq_cp(mem, 0, slot.seq_id, -1, -1);

// 第 842 行
llama_memory_seq_rm(mem, slot.seq_id, 0, -1);

// 第 1078 行
llama_memory_seq_rm(mem, 0, 0, -1);

// 第 1106 行（异常处理）
llama_memory_clear(mem, false);
```

---

### 2. **参数结构体已默认初始化** ✅ **已正确实现**

**好消息**: 你的代码已经正确使用了默认参数初始化！

#### 第 166 行 - localllm_model_load()
```cpp
llama_model_params model_params = llama_model_default_params();  // ✅ 正确
model_params.n_gpu_layers = n_gpu_layers;
model_params.use_mmap = use_mmap;
model_params.use_mlock = use_mlock;
```

#### 第 224 行 - localllm_model_load_safe()
```cpp
llama_model_params model_params = llama_model_default_params();  // ✅ 正确
model_params.n_gpu_layers = n_gpu_layers;
model_params.use_mmap = use_mmap;
model_params.use_mlock = use_mlock;
```

#### 第 264 行 - localllm_context_create()
```cpp
llama_context_params ctx_params = llama_context_default_params();  // ✅ 正确
ctx_params.n_ctx = n_ctx;
ctx_params.n_threads = n_threads;
ctx_params.n_seq_max = n_seq_max;
```

**这些都不需要修改！** 🎉

---

### 3. **llama_decode() 错误处理** 🔧 **建议改进（可选）**

你的代码当前只检查 `!= 0`，这在 b7785 仍然有效，但可以改进以提供更详细的错误信息。

#### 当前实现（第 378, 477, 562, 712, 927 行）:
```cpp
if (llama_decode(ctx, batch) != 0) {
    set_error(error_message, "Failed to decode input tokens.");
    return LOCALLLM_ERROR;
}
```

#### 建议的改进（可选）:
```cpp
int ret = llama_decode(ctx, batch);
if (ret != 0) {
    std::string error_detail;
    switch (ret) {
        case 1:
            error_detail = "No KV slot available - try reducing batch size or increasing n_ctx";
            break;
        case 2:
            error_detail = "Decoding aborted - partial results may be available";
            break;
        case -1:
            error_detail = "Invalid input batch";
            break;
        default:
            error_detail = ret < -1 ? "Fatal error during decoding" : "Unknown decode error";
    }
    set_error(error_message, "Failed to decode: " + error_detail);
    return LOCALLLM_ERROR;
}
```

**这个改进不是必须的**，但会提供更好的错误信息。

---

## 📋 完整修改清单

### 必须修改 (Breaking Changes)

- [x] **第 372 行**: `llama_kv_self_clear(ctx)` → Memory API
- [x] **第 538 行**: `llama_kv_self_clear(ctx)` → Memory API
- [x] **第 577 行**: `llama_kv_self_clear(ctx)` → Memory API
- [x] **第 749 行**: `llama_kv_self_seq_rm()` → Memory API
- [x] **第 837 行**: `llama_kv_self_seq_cp()` → Memory API
- [x] **第 842 行**: `llama_kv_self_seq_rm()` → Memory API
- [x] **第 1078 行**: `llama_kv_self_seq_rm()` → Memory API
- [x] **第 1106 行**: `llama_kv_self_clear(ctx)` → Memory API

### 可选改进

- [ ] 改进 `llama_decode()` 错误处理（5 处）
- [ ] 添加 Flash Attention 支持（在 `localllm_context_create` 中）
- [ ] 使用新的模型信息查询函数

---

## 🔧 具体修改代码

### 修改 1: localllm_generate() 函数

**位置**: 第 365-485 行

```cpp
LOCALLLM_API localllm_error_code localllm_generate(...) {
    if (!ctx) {
        set_error(error_message, "Context handle is null.");
        return LOCALLLM_ERROR;
    }

    // 修改这里 ⬇️
    llama_memory_t mem = llama_get_memory(ctx);
    llama_memory_clear(mem, false);  // 替代旧的 llama_kv_self_clear(ctx)

    const llama_model* model = llama_get_model(ctx);
    // ... 其余代码保持不变
}
```

### 修改 2: localllm_generate_parallel() 函数

**位置**: 第 488-1110 行

```cpp
LOCALLLM_API localllm_error_code localllm_generate_parallel(...) {
    if (!ctx || !prompts || !params || !results_out || n_prompts <= 0) {
        set_error(error_message, "Invalid parameters...");
        return LOCALLLM_ERROR;
    }

    // 添加这一行 ⬇️
    llama_memory_t mem = llama_get_memory(ctx);

    const llama_model* model = llama_get_model(ctx);
    // ...

    // 第 538 行附近：替换
    llama_memory_clear(mem, false);  // 替代 llama_kv_self_clear(ctx)

    // 第 577 行附近：替换
    if (!prefix_ok) {
        llama_memory_clear(mem, false);  // 替代 llama_kv_self_clear(ctx)
    }

    // 第 749 行附近：finalize_slot 函数中
    if (slot.seq_id > 0) {
        llama_memory_seq_rm(mem, slot.seq_id, 0, -1);  // 替代 llama_kv_self_seq_rm
    }

    // 第 837 行附近：assign_next_prompt 函数中
    if (prefix_ready && slot.prefix_len > 0) {
        llama_memory_seq_cp(mem, 0, slot.seq_id, -1, -1);  // 替代 llama_kv_self_seq_cp
    }

    // 第 842 行附近：
    if (slot.seq_id > 0) {
        llama_memory_seq_rm(mem, slot.seq_id, 0, -1);  // 替代 llama_kv_self_seq_rm
    }

    // 第 1078 行附近：
    if (prefix_ready) {
        llama_memory_seq_rm(mem, 0, 0, -1);  // 替代 llama_kv_self_seq_rm
    }

    // ... 其余代码

    } catch (const std::exception& e) {
        if (show_progress_bar) { /* ... */ }
        llama_memory_clear(mem, false);  // 替代 llama_kv_self_clear(ctx)
        set_error(error_message, std::string("Parallel generation failed: ") + e.what());
        return LOCALLLM_ERROR;
    }
}
```

---

## 🎯 可选的性能优化

### 1. Flash Attention 支持

在 `localllm_context_create()` 中添加：

```cpp
LOCALLLM_API localllm_error_code localllm_context_create(...) {
    // ...
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx;
    ctx_params.n_threads = n_threads;
    ctx_params.n_seq_max = n_seq_max;

    // 新增：启用 Flash Attention（可选，提升性能）
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;  // 自动检测

    llama_context* ctx = llama_init_from_model(model, ctx_params);
    // ...
}
```

### 2. 统一 KV Buffer（多序列场景优化）

```cpp
// 如果用户使用 n_seq_max > 1
if (n_seq_max > 1) {
    ctx_params.kv_unified = true;  // 共享前缀缓存
}
```

---

## ✅ 测试验证清单

完成修改后，测试以下功能：

### 基础功能测试
- [ ] `localllm_backend_init()` 成功
- [ ] `localllm_model_load()` 加载模型
- [ ] `localllm_context_create()` 创建上下文
- [ ] `localllm_tokenize()` / `localllm_detokenize()` 正常工作

### 生成测试
- [ ] `localllm_generate()` 单次生成正常
- [ ] `localllm_generate_parallel()` 并行生成正常
- [ ] 多次调用 `generate()` 结果一致（KV cache 清空生效）

### KV Cache/Memory 测试
- [ ] 单序列生成后 memory 被正确清空
- [ ] 多序列并行生成互不干扰
- [ ] 共享前缀优化生效（如果使用）

### 错误处理测试
- [ ] 超出上下文长度时返回正确错误
- [ ] 无效输入时返回正确错误
- [ ] 内存不足时返回正确错误

---

## 📊 风险评估

| 修改项 | 复杂度 | 破坏风险 | 测试难度 |
|-------|--------|---------|---------|
| KV Cache → Memory API | 🟡 中 | 🔴 高 | 🟢 低 |
| 参数结构体初始化 | 🟢 低 | 🟢 低 | 🟢 低 |
| 错误处理改进 | 🟢 低 | 🟢 低 | 🟢 低 |
| Flash Attention | 🟢 低 | 🟢 低 | 🟡 中 |

**总体风险**: 🟡 **中等**（主要来自 KV Cache API 重构）

---

## 🚀 推荐的实施步骤

1. **备份当前文件**
   ```bash
   cp custom_files/localllm_capi.cpp custom_files/localllm_capi.cpp.b5421.backup
   ```

2. **切换到 b7785**
   ```bash
   cd backend/llama.cpp
   git checkout b7785
   ```

3. **修改 localllm_capi.cpp**
   - 使用查找替换功能快速修改所有 `llama_kv_self_*` 调用
   - 在函数开始添加 `llama_memory_t mem = llama_get_memory(ctx);`

4. **编译后端库**
   ```bash
   cd backend/llama.cpp
   mkdir -p build && cd build
   cmake .. -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DBUILD_SHARED_LIBS=ON
   cmake --build . --config Release -j $(sysctl -n hw.ncpu)
   ```

5. **在 R 中测试**
   ```r
   library(localLLM)
   install_localLLM()  # 安装新编译的库

   # 测试基础功能
   model <- model_load("path/to/model.gguf")
   ctx <- context_create(model, n_ctx = 512)
   result <- generate(ctx, "Test", max_tokens = 10)
   print(result)
   ```

6. **运行完整测试套件**
   ```bash
   cd localLLM
   R CMD check .
   ```

---

## 📞 需要帮助？

如果在修改过程中遇到问题，请检查：
- ✅ 所有 `llama_kv_self_*` 调用都已替换
- ✅ 每个使用 Memory API 的函数都有 `llama_memory_t mem = llama_get_memory(ctx)`
- ✅ `llama_memory_clear()` 的第二个参数是 `false`
- ✅ 编译时没有 undefined symbol 错误

---

**预计工作时间**: 1-2 小时（代码修改 + 编译测试）

**成功指标**:
- ✅ 编译无错误
- ✅ 所有 R 测试通过
- ✅ `generate()` 和 `generate_parallel()` 结果正确
- ✅ 多次运行结果一致（确认 memory 清空生效）
