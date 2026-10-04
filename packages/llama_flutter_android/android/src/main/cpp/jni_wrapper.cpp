#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <ctime>
#include <cstring>
#include <fstream>
#include <sys/stat.h>
#include <android/log.h>
#include "llama.cpp/include/llama.h"
#include "llama.cpp/tools/mtmd/mtmd.h"
#include "llama.cpp/tools/mtmd/mtmd-helper.h"
#include <vulkan/vulkan.h>


#define LOG_TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static mtmd_context* g_mtmd_ctx = nullptr;
static std::atomic<bool> g_stop_flag{false};
static int g_n_past = 0;  // Track the number of tokens already in KV cache

static bool fileExists(const std::string& path) {
    struct stat st{};
    return !path.empty() && stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

static std::string resolveMmprojPath(const std::string& model_path) {
    // 1. Check sidecar pointer file "<model_path>.mmproj_path"
    std::string ptr_file = model_path + ".mmproj_path";
    if (fileExists(ptr_file)) {
        std::ifstream ifs(ptr_file);
        std::string target;
        if (std::getline(ifs, target)) {
            while (!target.empty() && (target.back() == '\n' || target.back() == '\r' || target.back() == ' ')) {
                target.pop_back();
            }
            if (fileExists(target)) {
                return target;
            }
        }
    }
    // 2. Check "<model_path>.mmproj"
    std::string direct = model_path + ".mmproj";
    if (fileExists(direct)) {
        return direct;
    }
    return "";
}

// Extracts [IMG:/path/to/image.jpg] tags from prompt and replaces them with marker (or strips if marker is null)
static std::string extractImageTags(
    const std::string& input,
    const char* marker,
    std::vector<std::string>& out_paths
) {
    out_paths.clear();
    std::string out;
    out.reserve(input.size());
    size_t pos = 0;
    const std::string prefix = "[IMG:";
    while (pos < input.size()) {
        size_t start = input.find(prefix, pos);
        if (start == std::string::npos) {
            out.append(input, pos, std::string::npos);
            break;
        }
        out.append(input, pos, start - pos);
        size_t path_start = start + prefix.size();
        size_t end = input.find(']', path_start);
        if (end == std::string::npos) {
            out.append(input, start, std::string::npos);
            break;
        }
        std::string img_path = input.substr(path_start, end - path_start);
        if (!img_path.empty() && fileExists(img_path)) {
            out_paths.push_back(img_path);
            if (marker != nullptr) {
                out.append(marker);
            }
        }
        pos = end + 1;
    }
    return out;
}

// Helper function to validate UTF-8 strings
static bool isValidUTF8(const char* str, size_t len) {
    if (!str) return false;
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            i++;
            continue;
        }
        
        // Multi-byte sequence start (110xxxxx, 1110xxxx, or 11110xxx)
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2; // 110xxxxx
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3; // 1110xxxx
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4; // 11110xxx
        } else {
            // Invalid first byte
            return false;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            return false;
        }
        
        // Check continuation bytes (10xxxxxx)
        for (int j = 1; j < num_bytes; j++) {
            if ((bytes[i + j] & 0xC0) != 0x80) {
                return false;
            }
        }
        
        // Check for overlong encodings and invalid code points
        if (num_bytes == 2) {
            // Overlong encoding of ASCII character
            if ((c & 0x1E) == 0) return false;
        } else if (num_bytes == 3) {
            // Invalid surrogate halves (U+D800-U+DFFF)
            if (c == 0xED && (bytes[i + 1] & 0x20) == 0x20) return false;
            // Overlong encoding
            if (c == 0xE0 && (bytes[i + 1] & 0x20) == 0) return false;
        } else if (num_bytes == 4) {
            // Out of Unicode range (> U+10FFFF)
            if (c > 0xF4) return false;
            // Overlong encoding
            if (c == 0xF0 && (bytes[i + 1] & 0x30) == 0) return false;
            // Invalid code points (> U+10FFFF)
            if (c == 0xF4 && bytes[i + 1] > 0x8F) return false;
        }
        
        i += num_bytes;
    }
    
    return true;
}

// Helper function to sanitize UTF-8 strings
static std::string sanitizeUTF8(const char* str, size_t len) {
    if (!str || len == 0) return "";
    
    // First try to validate as-is
    if (isValidUTF8(str, len)) {
        return std::string(str, len);
    }
    
    // If invalid, create a sanitized version
    std::string result;
    result.reserve(len);
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            result += c;
            i++;
            continue;
        }
        
        // Multi-byte sequence start
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2;
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3;
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4;
        } else {
            // Invalid first byte, replace with replacement character
            result += "\xEF\xBF\xBD";
            i++;
            continue;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            result += "\xEF\xBF\xBD";
            break;
        }
        
        // Extract the sequence
        std::string seq(reinterpret_cast<const char*>(bytes + i), num_bytes);
        
        // Validate the sequence
        if (isValidUTF8(seq.c_str(), num_bytes)) {
            result += seq;
        } else {
            // Invalid sequence, replace with replacement character
            result += "\xEF\xBF\xBD";
        }
        
        i += num_bytes;
    }
    
    return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeDetectGpu(
        JNIEnv* env, jobject /* this */, jlongArray outStats) {

    // Zero out output array as safe default (-1 = unknown)
    jlong defaults[2] = {-1L, -1L};
    env->SetLongArrayRegion(outStats, 0, 2, defaults);

    // Minimal instance — no extensions, no validation layers (crash risk on some devices)
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = 0;
    createInfo.ppEnabledExtensionNames = nullptr;
    createInfo.enabledLayerCount = 0;
    createInfo.ppEnabledLayerNames = nullptr;

    VkInstance instance = VK_NULL_HANDLE;
    if (vkCreateInstance(&createInfo, nullptr, &instance) != VK_SUCCESS) {
        LOGI("nativeDetectGpu: vkCreateInstance failed — no Vulkan");
        return nullptr;
    }

    // Enumerate physical devices
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        LOGI("nativeDetectGpu: no physical devices found");
        vkDestroyInstance(instance, nullptr);
        return nullptr;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());

    // Select device with the largest device-local memory heap
    VkPhysicalDevice bestDevice = VK_NULL_HANDLE;
    VkDeviceSize bestHeapSize = 0;

    for (auto& dev : devices) {
        VkPhysicalDeviceMemoryProperties memProps{};
        vkGetPhysicalDeviceMemoryProperties(dev, &memProps);
        for (uint32_t i = 0; i < memProps.memoryHeapCount; i++) {
            if ((memProps.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) &&
                memProps.memoryHeaps[i].size > bestHeapSize) {
                bestHeapSize = memProps.memoryHeaps[i].size;
                bestDevice = dev;
            }
        }
    }

    if (bestDevice == VK_NULL_HANDLE) {
        LOGI("nativeDetectGpu: no device-local memory found");
        vkDestroyInstance(instance, nullptr);
        return nullptr;
    }

    // Check for compute queue support
    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(bestDevice, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(bestDevice, &queueFamilyCount, queueFamilies.data());

    bool hasComputeQueue = false;
    for (auto& qf : queueFamilies) {
        if (qf.queueFlags & VK_QUEUE_COMPUTE_BIT) {
            hasComputeQueue = true;
            break;
        }
    }

    if (!hasComputeQueue) {
        LOGI("nativeDetectGpu: no compute queue — GPU not usable for inference");
        vkDestroyInstance(instance, nullptr);
        return nullptr;
    }

    // Read device properties
    VkPhysicalDeviceProperties props{};
    vkGetPhysicalDeviceProperties(bestDevice, &props);

    // Populate outStats
    jlong stats[2];
    stats[0] = static_cast<jlong>(props.apiVersion);
    stats[1] = static_cast<jlong>(bestHeapSize);
    env->SetLongArrayRegion(outStats, 0, 2, stats);

    LOGI("nativeDetectGpu: GPU='%s' apiVersion=%u heapSize=%llu hasCompute=%d",
         props.deviceName,
         props.apiVersion,
         (unsigned long long)bestHeapSize,
         hasComputeQueue ? 1 : 0);

    vkDestroyInstance(instance, nullptr);
    return env->NewStringUTF(props.deviceName);
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring path, jlong n_threads, jlong ctx_size, jlong n_gpu_layers,
    jobject progress_callback) {
    
    // Free any previously loaded model/context first
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_mtmd_ctx) {
        mtmd_free(g_mtmd_ctx);
        g_mtmd_ctx = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_vocab = nullptr;
    g_n_past = 0;

    const char* model_path_cstr = env->GetStringUTFChars(path, nullptr);
    std::string model_path_str(model_path_cstr ? model_path_cstr : "");
    LOGI("Loading model: %s", model_path_str.c_str());

    // Model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers;
    
    // Load model
    g_model = llama_model_load_from_file(model_path_str.c_str(), model_params);
    env->ReleaseStringUTFChars(path, model_path_cstr);
    
    if (!g_model) {
        LOGE("Failed to load model");
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to load model");
        return;
    }

    // Context parameters with memory optimizations for low-end devices
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    
    // Memory optimization: reduce memory usage by limiting batch processing
    ctx_params.n_batch = 512;  // Process smaller batches to reduce memory spikes

    // Create context (using new API)
    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (!g_ctx) {
        llama_model_free(g_model);
        g_model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to create context");
        return;
    }

    // Get vocab for tokenization
    g_vocab = llama_model_get_vocab(g_model);
    LOGI("Vocab initialized: %p", (void*)g_vocab);
    
    if (!g_vocab) {
        llama_free(g_ctx);
        llama_model_free(g_model);
        g_ctx = nullptr;
        g_model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to get vocab from model");
        return;
    }

    // Check if a multimodal vision projector (mmproj) exists for this model
    std::string mmproj_path = resolveMmprojPath(model_path_str);
    if (!mmproj_path.empty()) {
        mtmd_context_params mparams = mtmd_context_params_default();
        mparams.use_gpu = (n_gpu_layers > 0);
        mparams.n_threads = static_cast<int>(n_threads);
        mparams.warmup = false;
        // Keep image tokens compact on mobile devices to fit within 2048 context and RAM
        mparams.image_min_tokens = 64;
        mparams.image_max_tokens = 256;
        LOGI("Initializing multimodal vision projector: %s", mmproj_path.c_str());
        g_mtmd_ctx = mtmd_init_from_file(mmproj_path.c_str(), g_model, mparams);
        if (g_mtmd_ctx) {
            LOGI("✅ Vision projector loaded! support_vision=%d", mtmd_support_vision(g_mtmd_ctx) ? 1 : 0);
        } else {
            LOGE("⚠️ Failed to initialize vision projector from %s", mmproj_path.c_str());
        }
    }
    
    // Reset KV cache position counter for new model
    g_n_past = 0;

    // Report progress completion
    if (progress_callback) {
        jclass callbackClass = env->GetObjectClass(progress_callback);
        jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");
        
        // Create Double object for 1.0
        jclass doubleClass = env->FindClass("java/lang/Double");
        jmethodID doubleConstructor = env->GetMethodID(doubleClass, "<init>", "(D)V");
        jobject doubleObj = env->NewObject(doubleClass, doubleConstructor, 1.0);
        
        env->CallObjectMethod(progress_callback, invokeMethod, doubleObj);
        env->DeleteLocalRef(doubleObj);
        env->DeleteLocalRef(callbackClass);
    }

    LOGI("Model loaded successfully");
}

static jobject g_token_callback = nullptr;

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGenerate(
    JNIEnv* env, jobject thiz,
    jstring prompt, jlong max_tokens, 
    jdouble temperature, jdouble top_p, jlong top_k, jdouble min_p, jdouble typical_p,
    jdouble repeat_penalty, jdouble frequency_penalty, jdouble presence_penalty, jlong repeat_last_n,
    jlong mirostat, jdouble mirostat_tau, jdouble mirostat_eta,
    jlong seed, jboolean penalize_newline,
    jobject token_callback) {
    
    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }
    g_token_callback = env->NewGlobalRef(token_callback);
    
    if (!g_model || !g_ctx || !g_vocab) {
        jclass exception = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(exception, "Model not loaded");
        return;
    }

    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    g_stop_flag = false;
    
    const int prompt_len = strlen(prompt_str);
    std::string sanitized_prompt = sanitizeUTF8(prompt_str, prompt_len);
    env->ReleaseStringUTFChars(prompt, prompt_str);

    // Check for [IMG:/path/to/image] markers in prompt
    const bool vision_ready = (g_mtmd_ctx != nullptr && mtmd_support_vision(g_mtmd_ctx));
    std::vector<std::string> image_paths;
    std::string processed_prompt = extractImageTags(
        sanitized_prompt,
        vision_ready ? mtmd_default_marker() : nullptr,
        image_paths
    );

    const int max_batch_size = 512;
    llama_batch batch = llama_batch_init(max_batch_size, 0, 1);

    if (vision_ready && !image_paths.empty()) {
        LOGI("🖼️ Running multimodal Vision inference with %zu image(s)", image_paths.size());
        // Reset KV cache before multimodal evaluation so M-RoPE / image chunks start cleanly at pos 0
        llama_memory_t mem = llama_get_memory(g_ctx);
        if (mem) {
            llama_memory_seq_rm(mem, 0, 0, -1);
            g_n_past = 0;
        }

        mtmd::bitmaps bitmaps;
        for (const auto& img_path : image_paths) {
            LOGI("Loading bitmap: %s", img_path.c_str());
            mtmd::bitmap bmp(mtmd_helper_bitmap_init_from_file(g_mtmd_ctx, img_path.c_str()));
            if (!bmp.ptr) {
                LOGE("Failed to load bitmap: %s", img_path.c_str());
                llama_batch_free(batch);
                jclass exception = env->FindClass("java/lang/RuntimeException");
                env->ThrowNew(exception, "Failed to decode image for vision model");
                return;
            }
            bitmaps.entries.push_back(std::move(bmp));
        }

        mtmd::input_chunks chunks(mtmd_input_chunks_init());
        mtmd_input_text text_inp = {
            processed_prompt.c_str(),
            /* add_special */ true,
            /* parse_special */ true,
        };
        auto bitmaps_c = bitmaps.c_ptr();
        int32_t tok_res = mtmd_tokenize(
            g_mtmd_ctx,
            chunks.ptr.get(),
            &text_inp,
            bitmaps_c.data(),
            bitmaps_c.size()
        );
        if (tok_res != 0) {
            LOGE("❌ mtmd_tokenize failed with code %d", tok_res);
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to tokenize multimodal prompt");
            return;
        }

        llama_pos new_n_past = 0;
        LOGI("Evaluating %zu multimodal chunks (total tokens: %zu)...",
             chunks.size(),
             mtmd_helper_get_n_tokens(chunks.ptr.get()));
        int32_t eval_res = mtmd_helper_eval_chunks(
            g_mtmd_ctx,
            g_ctx,
            chunks.ptr.get(),
            g_n_past,
            /* seq_id */ 0,
            max_batch_size,
            /* logits_last */ true,
            &new_n_past
        );
        if (eval_res != 0) {
            LOGE("❌ mtmd_helper_eval_chunks failed with code %d", eval_res);
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to evaluate image + prompt chunks");
            return;
        }
        g_n_past = new_n_past;
        LOGI("✅ Vision evaluation succeeded! g_n_past=%d", g_n_past);
    } else {
        const char* sanitized_cstr = processed_prompt.c_str();
        const int sanitized_len = processed_prompt.length();
        
        // Tokenize prompt - when tokens is NULL, llama_tokenize returns NEGATIVE count
        const int n_prompt_tokens = -llama_tokenize(g_vocab, sanitized_cstr, sanitized_len, nullptr, 0, true, true);
        LOGI("Token count: %d", n_prompt_tokens);
        
        if (n_prompt_tokens <= 0) {
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "Failed to tokenize prompt (got %d tokens)", n_prompt_tokens);
            env->ThrowNew(exception, error_msg);
            return;
        }
        std::vector<llama_token> tokens(n_prompt_tokens);
        const int actual_tokens = llama_tokenize(g_vocab, sanitized_cstr, sanitized_len, tokens.data(), tokens.size(), true, true);
        if (actual_tokens < 0) {
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to tokenize prompt");
            return;
        }
        tokens.resize(actual_tokens);

        const int n_ctx = llama_n_ctx(g_ctx);

        // Check if the context will be exceeded and apply a sliding window for the KV cache
        if (g_n_past + (int)tokens.size() > n_ctx) {
            const int n_discard = n_ctx / 4; // Discard the oldest 25% of the context
            LOGI("Context is full, shifting KV cache by %d tokens", n_discard);

            // Remove the oldest tokens from the sequence
            llama_memory_seq_rm(llama_get_memory(g_ctx), 0, 0, n_discard);
            
            // Shift the remaining tokens
            llama_memory_seq_add(llama_get_memory(g_ctx), 0, n_discard, g_n_past, -n_discard);

            // Update the past tokens count
            g_n_past -= n_discard;
        }

        // Process prompt in batches to handle long inputs
        int tokens_processed = 0;
        LOGI("Context size: %d", llama_n_ctx(g_ctx));

        while (tokens_processed < (int)tokens.size()) {
            batch.n_tokens = 0;
            int batch_size = std::min((int)tokens.size() - tokens_processed, max_batch_size);

            for (int i = 0; i < batch_size; i++) {
                batch.token[batch.n_tokens] = tokens[tokens_processed + i];
                batch.pos[batch.n_tokens] = g_n_past + tokens_processed + i;
                batch.n_seq_id[batch.n_tokens] = 1;
                batch.seq_id[batch.n_tokens][0] = 0;
                batch.logits[batch.n_tokens] = (tokens_processed + i == (int)tokens.size() - 1);
                batch.n_tokens++;
            }

            LOGI("Decoding batch: g_n_past=%d, batch_size=%d", g_n_past + tokens_processed, batch.n_tokens);
            int decode_result = llama_decode(g_ctx, batch);
            if (decode_result != 0) {
                LOGE("❌ DECODE FAILED! Result code: %d", decode_result);
                llama_batch_free(batch);
                jclass exception = env->FindClass("java/lang/RuntimeException");
                env->ThrowNew(exception, "Failed to decode prompt");
                return;
            }
            tokens_processed += batch_size;
        }

        LOGI("✅ Decode successful! Processed %d total tokens", tokens_processed);

        // Update position counter after decoding the whole prompt
        g_n_past += tokens.size();
    }

    // Create sampler chain with all parameters
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }
    
    // Use seed or current time
    uint32_t sampler_seed = (seed >= 0) ? static_cast<uint32_t>(seed) : static_cast<uint32_t>(time(nullptr));
    
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    
    // Add penalties first (applied to logits before sampling)
    if (repeat_penalty != 1.0f || frequency_penalty != 0.0f || presence_penalty != 0.0f) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(
            repeat_last_n,              // penalty_last_n
            repeat_penalty,             // penalty_repeat
            frequency_penalty,          // penalty_freq
            presence_penalty            // penalty_present
        ));
    }
    
    // Temperature sampling
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    
    // Add advanced samplers if enabled
    if (mirostat == 1) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_mirostat(
            llama_vocab_n_tokens(g_vocab),  // Use the vocab to get n_vocab
            sampler_seed,
            mirostat_tau,
            mirostat_eta,
            100  // m parameter
        ));
    } else if (mirostat == 2) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_mirostat_v2(
            sampler_seed,
            mirostat_tau,
            mirostat_eta
        ));
    } else {
        // Standard sampling chain (only if mirostat is disabled)
        if (min_p > 0.0f && min_p < 1.0f) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_min_p(min_p, 1));
        }
        
        if (typical_p < 1.0f) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_typical(typical_p, 1));
        }
        
        if (top_k > 0) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
        }
        
        if (top_p < 1.0f) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
        }
    }
    
    // Final distribution sampler
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(sampler_seed));

    // Get callback method
    jclass callbackClass = env->GetObjectClass(token_callback);
    jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");

    // Generation loop
    LOGI("Starting generation loop: max_tokens=%lld", max_tokens);
    for (int i = 0; i < max_tokens && !g_stop_flag; i++) {
        // Sample next token
        llama_token new_token_id = llama_sampler_sample(g_sampler, g_ctx, -1);
        llama_sampler_accept(g_sampler, new_token_id);

        // Check for end of generation (EOS/EOD tokens)
        if (llama_vocab_is_eog(g_vocab, new_token_id)) {
            LOGI("EOS token detected, ending generation.");
            break;
        }

        // Decode token to string
        char buffer[256];
        int32_t length = llama_token_to_piece(g_vocab, new_token_id, buffer, sizeof(buffer), 0, true);
        std::string piece;
        
        if (length > 0) {
            piece = sanitizeUTF8(buffer, length);
        } else {
            piece = "";
        }
        
        // Call Kotlin callback
        jstring token_str = env->NewStringUTF(piece.c_str());
        env->CallObjectMethod(g_token_callback, invokeMethod, token_str);
        env->DeleteLocalRef(token_str);

        // Prepare next batch
        batch.n_tokens = 0;
        batch.token[batch.n_tokens] = new_token_id;
        batch.pos[batch.n_tokens] = g_n_past;  // Use the tracked position
        batch.n_seq_id[batch.n_tokens] = 1;
        batch.seq_id[batch.n_tokens][0] = 0;
        batch.logits[batch.n_tokens] = true;
        batch.n_tokens++;

        if (llama_decode(g_ctx, batch) != 0) {
            LOGE("Failed to decode after sampling token %d", i + 1);
            break;
        }
        
        // Update position counter after each generated token
        g_n_past++;
    }
    LOGI("Generation loop finished.");

    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }

    llama_batch_free(batch);
    env->DeleteLocalRef(callbackClass);
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeStop(
    JNIEnv* env, jobject thiz) {
    g_stop_flag = true;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeFreeModel(
    JNIEnv* env, jobject thiz) {
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_mtmd_ctx) {
        mtmd_free(g_mtmd_ctx);
        g_mtmd_ctx = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_vocab = nullptr;
    g_n_past = 0;  // Reset position counter
    
    LOGI("Model freed");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetTokensUsed(
    JNIEnv* env, jobject thiz) {
    return g_n_past;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetContextSize(
    JNIEnv* env, jobject thiz) {
    return g_ctx ? llama_n_ctx(g_ctx) : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeClearContext(
    JNIEnv* env, jobject thiz) {
    if (!g_ctx) {
        LOGE("Cannot clear context: context is null");
        return;
    }
    
    llama_memory_t mem = llama_get_memory(g_ctx);
    if (mem) {
        llama_memory_seq_rm(mem, 0, 0, -1);
        g_n_past = 0;
        LOGI("Context cleared, g_n_past reset to 0");
    } else {
        LOGE("Failed to get memory object from context");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSetSystemPromptLength(
    JNIEnv* env, jobject thiz, jint length) {
    LOGI("System prompt length set to: %d tokens (currently unused)", length);
}