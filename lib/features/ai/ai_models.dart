/// A downloadable on-device model the user can pick. Kept as plain data so new
/// models drop in without code changes (the swappable catalog).
class AiModel {
  const AiModel({
    required this.id,
    required this.displayName,
    required this.url,
    required this.fileName,
    required this.sizeLabel,
    required this.template,
    required this.contextSize,
    this.maxOutputTokens = 768,
    this.canThink = false,
    this.thinkingMaxTokens = 1024,
    this.mmprojUrl,
    this.mmprojFileName,
  });

  /// Stable id used in the catalog and persisted as the active selection.
  final String id;

  /// Human label for the download UI.
  final String displayName;

  /// Direct, ungated download URL (HuggingFace, no login/token).
  final String url;

  /// File name the model is stored under / checked for installation by.
  final String fileName;

  /// e.g. "986 MB" — shown in the download sheet.
  final String sizeLabel;

  /// llama.cpp chat template id (e.g. `chatml` for Qwen). Drives how the
  /// system/user turns are wrapped before the GGUF sees them.
  final String template;

  /// Context window (tokens) to open the model with. Kept modest to stay light
  /// on phone RAM; the model files support far more.
  final int contextSize;

  /// Ceiling on generated tokens per answer; short replies still stop at the
  /// model's end-of-turn token. The service clamps it further to the context
  /// window's remaining room.
  final int maxOutputTokens;

  /// Whether this model has a hidden `<think>…</think>` mode. When true, Ask
  /// shows the "Think harder" toggle; the on/off choice itself is the user
  /// preference in `AiModelManager.thinkHarder()`.
  final bool canThink;

  /// Token budget with "Think harder" on: larger than [maxOutputTokens] because
  /// the reasoning chain and the answer must both fit.
  final int thinkingMaxTokens;

  /// Optional multimodal vision projector (mmproj) download URL.
  final String? mmprojUrl;

  /// Optional multimodal vision projector (mmproj) local file name.
  final String? mmprojFileName;

  /// Whether this model supports direct on-device Vision (Image + Text).
  bool get supportsVision => mmprojUrl != null && mmprojFileName != null;
}

/// Available models: open (no login, no token) GGUFs including Multimodal Vision
/// models (with `mmproj` vision encoders) for Food Scan and Medical Image Q&A.
const List<AiModel> kAiModelCatalog = [
  // SmolVLM2 500M Vision model — fast, lightweight multimodal VLM (545 MB total).
  AiModel(
    id: 'smolvlm2_500m_vision_gguf',
    displayName: 'SmolVLM2 (500M · Vision & Food)',
    url:
        'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    fileName: 'SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    mmprojUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    mmprojFileName: 'mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    sizeLabel: '545 MB · Vision',
    template: 'smolvlm',
    contextSize: 2048,
  ),
  // Compact Qwen 3.5 Vision model (0.8B) — ideal for tablets/phones with ~1.5GB free RAM.
  AiModel(
    id: 'qwen3_5_0_8b_vision_gguf',
    displayName: 'Qwen 3.5 Vision (0.8B · Food & Image)',
    url:
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf',
    fileName: 'Qwen3.5-0.8B-Q4_K_M.gguf',
    mmprojUrl:
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf',
    mmprojFileName: 'mmproj-Qwen3.5-0.8B-F16.gguf',
    sizeLabel: '703 MB · Vision',
    template: 'chatml',
    contextSize: 2048,
    canThink: true,
  ),
  // Google Gemma 4 E2B IT Multimodal Vision model (QAT quantized + Q8_0 vision encoder).
  AiModel(
    id: 'gemma_4_e2b_it_gguf',
    displayName: 'Gemma 4 E2B IT (Vision · LiteRT/GGUF)',
    url:
        'https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF/resolve/main/gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf',
    fileName: 'gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf',
    mmprojUrl:
        'https://huggingface.co/mradermacher/Huihui-gemma-4-E2B-it-abliterated-GGUF/resolve/main/Huihui-gemma-4-E2B-it-abliterated.mmproj-Q8_0.gguf',
    mmprojFileName: 'mmproj-gemma-4-E2B-it-Q8_0.gguf',
    sizeLabel: '2.7 GB · Vision',
    template: 'gemma4',
    contextSize: 2048,
  ),
  // Ultra-lightweight SmolVLM 500M Vision model for fast image extraction.
  AiModel(
    id: 'smolvlm_500m_vision_gguf',
    displayName: 'SmolVLM (0.5B · Fast Vision Extract)',
    url:
        'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf',
    fileName: 'SmolVLM-500M-Instruct-Q8_0.gguf',
    mmprojUrl:
        'https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-Q8_0.gguf',
    mmprojFileName: 'mmproj-SmolVLM-500M-Instruct-Q8_0.gguf',
    sizeLabel: '520 MB · Vision',
    template: 'smolvlm',
    contextSize: 2048,
  ),
  // Qwen 3.5 2B Vision model (larger, for devices with more free RAM).
  AiModel(
    id: 'qwen3_5_2b_gguf',
    displayName: 'Qwen 3.5 Vision (2B)',
    url:
        'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
    fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
    mmprojUrl:
        'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-F16.gguf',
    mmprojFileName: 'mmproj-Qwen3.5-2B-F16.gguf',
    sizeLabel: '1.85 GB · Vision',
    template: 'chatml',
    contextSize: 2048,
    canThink: true,
  ),
  // LFM2.5 (Liquid AI): small, fast, strong text instruction-following.
  AiModel(
    id: 'lfm2_5_1_2b_gguf',
    displayName: 'LFM2.5 (1.2B)',
    url:
        'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
    fileName: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
    sizeLabel: '731 MB',
    template: 'chatml',
    contextSize: 2048,
  ),
  // Qwen3 1.7B: text reasoning model.
  AiModel(
    id: 'qwen3_1_7b_gguf',
    displayName: 'Qwen3 (1.7B)',
    url:
        'https://huggingface.co/bartowski/Qwen_Qwen3-1.7B-GGUF/resolve/main/Qwen_Qwen3-1.7B-Q4_K_M.gguf',
    fileName: 'Qwen_Qwen3-1.7B-Q4_K_M.gguf',
    sizeLabel: '1.28 GB',
    template: 'chatml',
    contextSize: 2048,
    canThink: true,
  ),
  AiModel(
    id: 'qwen3_0_6b_gguf',
    displayName: 'Qwen3 (0.6B, Extract)',
    url:
        'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    fileName: 'Qwen3-0.6B-Q4_K_M.gguf',
    sizeLabel: '378 MB',
    template: 'chatml',
    contextSize: 2048,
    canThink: true,
  ),
  AiModel(
    id: 'qwen2_5_0_5b_gguf',
    displayName: 'Qwen 2.5 (0.5B, lighter)',
    url:
        'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
    fileName: 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
    sizeLabel: '398 MB',
    template: 'chatml',
    contextSize: 2048,
  ),
];

/// Default model — Qwen 3.5 Vision (0.8B), supporting both text and images on-device.
final AiModel kDefaultModel = kAiModelCatalog.first;

/// Looks up a catalog entry by id (used to restore the active selection).
AiModel? aiModelById(String? id) {
  for (final m in kAiModelCatalog) {
    if (m.id == id) return m;
  }
  return null;
}

/// Looks up a catalog entry by file name (either main GGUF or mmproj GGUF).
AiModel? aiModelByFileName(String? fileName) {
  if (fileName == null) return null;
  for (final m in kAiModelCatalog) {
    if (m.fileName == fileName || m.mmprojFileName == fileName) return m;
  }
  return null;
}
