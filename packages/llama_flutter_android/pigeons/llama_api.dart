import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  kotlinOut: 'android/src/main/kotlin/com/write4me/llama_flutter_android/LlamaHostApi.kt',
  kotlinOptions: KotlinOptions(
    package: 'com.write4me.llama_flutter_android',
  ),
  dartOut: 'lib/src/llama_api.dart',
  dartOptions: DartOptions(),
  swiftOut: 'ios/Classes/GeneratedMessages.g.swift',
))
  
/// Configuration for loading a GGUF model.
class ModelConfig {
  /// Absolute path to the `.gguf` model file on device storage.
  final String modelPath;

  /// Number of CPU threads to use for inference.
  final int nThreads;

  /// KV-cache context size in tokens. Larger values use more RAM.
  final int contextSize;

  /// Number of model layers to offload to GPU via Vulkan.
  /// Use [LlamaController.detectGpu] to get a device-appropriate value.
  /// Null or 0 = CPU only. 99 = full offload (clamped to model's layer count).
  final int? nGpuLayers;

  /// Creates a [ModelConfig].
  ModelConfig({
    required this.modelPath,
    this.nThreads = 4,
    this.contextSize = 2048,
    this.nGpuLayers,
  });
}

/// A single message in a chat conversation.
class ChatMessage {
  /// Role of the message sender: `'system'`, `'user'`, or `'assistant'`.
  final String role;

  /// Text content of the message.
  final String content;

  /// Creates a [ChatMessage] with the given [role] and [content].
  ChatMessage({
    required this.role,
    required this.content,
  });
}

/// Request for text generation
class GenerateRequest {
  final String prompt;
  final int maxTokens;
  
  // Sampling parameters
  final double temperature;
  final double topP;
  final int topK;
  final double minP;
  final double typicalP;
  
  // Penalties
  final double repeatPenalty;
  final double frequencyPenalty;
  final double presencePenalty;
  final int repeatLastN;
  
  // Mirostat sampling
  final int mirostat;
  final double mirostatTau;
  final double mirostatEta;
  
  // Other
  final int? seed;
  final bool penalizeNewline;
  
  GenerateRequest({
    required this.prompt,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.minP = 0.05,
    this.typicalP = 1.0,
    this.repeatPenalty = 1.1,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.repeatLastN = 64,
    this.mirostat = 0,
    this.mirostatTau = 5.0,
    this.mirostatEta = 0.1,
    this.seed,
    this.penalizeNewline = true,
  });
}

/// Request for chat generation with automatic template formatting.
class ChatRequest {
  /// Conversation history including system, user, and assistant messages.
  final List<ChatMessage> messages;

  /// Chat template name (e.g. `'chatml'`, `'llama3'`). Null = auto-detect from model filename.
  final String? template;

  /// Maximum number of tokens to generate.
  final int maxTokens;
  
  // Sampling parameters
  final double temperature;
  final double topP;
  final int topK;
  final double minP;
  final double typicalP;
  
  // Penalties
  final double repeatPenalty;
  final double frequencyPenalty;
  final double presencePenalty;
  final int repeatLastN;
  
  // Mirostat sampling
  final int mirostat;
  final double mirostatTau;
  final double mirostatEta;
  
  // Other
  final int? seed;
  final bool penalizeNewline;
  
  ChatRequest({
    required this.messages,
    this.template,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.minP = 0.05,
    this.typicalP = 1.0,
    this.repeatPenalty = 1.1,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.repeatLastN = 64,
    this.mirostat = 0,
    this.mirostatTau = 5.0,
    this.mirostatEta = 0.1,
    this.seed,
    this.penalizeNewline = true,
  });
}

/// Current KV-cache context usage for a loaded model.
class ContextInfo {
  /// Number of tokens currently occupying the KV cache.
  final int tokensUsed;

  /// Total KV-cache capacity in tokens (set at model load time).
  final int contextSize;

  /// Percentage of context used (0.0–100.0).
  final double usagePercentage;

  /// Creates a [ContextInfo].
  ContextInfo({
    required this.tokensUsed,
    required this.contextSize,
    required this.usagePercentage,
  });
}

/// GPU detection result
class GpuInfo {
  /// True only if Vulkan instance created AND compute queue confirmed
  final bool vulkanSupported;

  /// e.g. "Adreno (TM) 740" or "Mali-G715". "None" if unsupported.
  final String gpuName;

  /// Vulkan API version integer (e.g. 4206592 = 1.3.0). -1 if unsupported.
  final int vulkanApiVersion;

  /// Largest VK_MEMORY_HEAP_DEVICE_LOCAL_BIT heap in bytes.
  /// On Android UMA this equals total system RAM — NOT dedicated VRAM.
  /// -1 if unknown.
  final int deviceLocalMemoryBytes;

  /// System free RAM from ActivityManager in bytes (before safety factor). -1 if unknown.
  final int freeRamBytes;

  /// Non-binding suggestion: 0, 16, or 99.
  /// llama.cpp clamps 99 to the model's actual layer count.
  /// Caller always makes the final decision.
  final int recommendedGpuLayers;

  GpuInfo({
    required this.vulkanSupported,
    required this.gpuName,
    required this.vulkanApiVersion,
    required this.deviceLocalMemoryBytes,
    required this.freeRamBytes,
    required this.recommendedGpuLayers,
  });
}

/// Host API (Dart calls Kotlin)
@HostApi()
abstract class LlamaHostApi {
  /// Load a GGUF model
  @async
  void loadModel(ModelConfig config);
  
  /// Start text generation (tokens streamed via FlutterApi)
  @async
  void generate(GenerateRequest request);
  
  /// Start chat generation with automatic template formatting
  @async
  void generateChat(ChatRequest request);
  
  /// Get list of supported chat templates
  List<String> getSupportedTemplates();
  
  /// Stop current generation
  @async
  void stop();
  
  /// Unload model and free resources
  @async
  void dispose();
  
  /// Check if model is loaded
  bool isModelLoaded();
  
  /// Get current context usage information
  ContextInfo getContextInfo();
  
  /// Clear conversation context (keeps model loaded)
  @async
  void clearContext();
  
  /// Set the system prompt token length for smart context management
  void setSystemPromptLength(int length);
  
  /// Register a custom template
  void registerCustomTemplate(String name, String content);
  
  /// Unregister a custom template
  void unregisterCustomTemplate(String name);

  /// Detect GPU capabilities. Returns Vulkan device info and a non-binding
  /// recommendedGpuLayers value. Caller decides actual gpuLayers to use.
  @async
  GpuInfo detectGpu();
}

/// Flutter API (Kotlin calls Dart)
@FlutterApi()
abstract class LlamaFlutterApi {
  /// Stream token to Dart
  void onToken(String token);
  
  /// Generation completed
  void onDone();
  
  /// Error occurred
  void onError(String error);
  
  /// Loading progress (0.0 to 1.0)
  void onLoadProgress(double progress);
}