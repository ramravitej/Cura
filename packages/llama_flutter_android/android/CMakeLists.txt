cmake_minimum_required(VERSION 3.22.1)

project(llama_jni)

# Set C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android 15 16KB page size compliance
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

# ARM64 optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -march=armv8-a+crc")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=armv8-a+crc")
endif()

# llama.cpp options
set(GGML_CPU_AARCH64 ON CACHE BOOL "Enable ARM64 support")
set(GGML_DOTPROD ON CACHE BOOL "Enable ARM NEON dot product")
set(GGML_VULKAN OFF CACHE BOOL "Enable Vulkan GPU backend")
set(GGML_STATIC OFF CACHE BOOL "Build as shared library")
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries")

# Disable unused features
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Disable tests")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Disable examples")
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Disable server")

# Add llama.cpp
add_subdirectory(src/main/cpp/llama.cpp)

# Multimodal (mtmd / clip) library for Vision & Audio models
add_library(mtmd STATIC
    src/main/cpp/llama.cpp/tools/mtmd/mtmd.cpp
    src/main/cpp/llama.cpp/tools/mtmd/mtmd-audio.cpp
    src/main/cpp/llama.cpp/tools/mtmd/mtmd-image.cpp
    src/main/cpp/llama.cpp/tools/mtmd/mtmd-helper.cpp
    src/main/cpp/llama.cpp/tools/mtmd/clip.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/cogvlm.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/conformer.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/dotsocr.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/gemma4v.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/glm4v.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/hunyuanocr.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/internvl.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/kimivl.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/kimik25.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/nemotron-v2-vl.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/llama4.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/llava.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/minicpmv.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/paddleocr.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/pixtral.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/qwen2vl.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/qwen3vl.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/step3vl.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/siglip.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/whisper-enc.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/deepseekocr.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/mobilenetv5.cpp
    src/main/cpp/llama.cpp/tools/mtmd/models/youtuvl.cpp
)

set_target_properties(mtmd PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(mtmd PUBLIC ggml llama)
target_include_directories(mtmd PUBLIC
    src/main/cpp/llama.cpp/tools/mtmd
)
target_include_directories(mtmd PRIVATE
    src/main/cpp/llama.cpp
    src/main/cpp/llama.cpp/include
    src/main/cpp/llama.cpp/ggml/include
    src/main/cpp/llama.cpp/vendor
)
target_compile_options(mtmd PRIVATE -Wno-cast-qual)

# JNI wrapper library
add_library(llama_jni SHARED
    src/main/cpp/jni_wrapper.cpp
)

find_library(VULKAN_LIB vulkan)

target_link_libraries(llama_jni
    mtmd
    llama
    android
    log
    ${VULKAN_LIB}
)

target_include_directories(llama_jni PRIVATE
    src/main/cpp/llama.cpp/include
    src/main/cpp/llama.cpp/ggml/include
    src/main/cpp/llama.cpp/tools/mtmd
)
