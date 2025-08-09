cmake_minimum_required(VERSION 3.10)
project(llama_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Path to llama.cpp (only for headers)
set(LLAMA_DIR "/Users/deva/Desktop/dev/llama.cpp")

# Headers: llama.h is in include/, ggml.h is in ggml/include/
include_directories(
    ${LLAMA_DIR}/include
    ${LLAMA_DIR}/ggml/include
)

# Build our bridge
add_library(llama_bridge SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/llama_bridge.cpp
)

# --- Import the prebuilt libllama.so shipped in jniLibs ---
# This path resolves to: android/app/src/main/jniLibs/<ABI>/libllama.so
add_library(llama_prebuilt SHARED IMPORTED)
set_target_properties(llama_prebuilt PROPERTIES
    IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libllama.so"
)

# Android log library
find_library(log_lib log)

# Link the bridge against libllama.so (and log)
target_link_libraries(llama_bridge
    ${log_lib}
    llama_prebuilt
)

# Hide all symbols except those explicitly exported
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(llama_bridge PRIVATE -fvisibility=hidden)
endif()
