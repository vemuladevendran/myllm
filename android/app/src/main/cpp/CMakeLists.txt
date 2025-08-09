cmake_minimum_required(VERSION 3.10)
project(llama_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# llama.cpp headers (must match the commit used to build libllama.so)
set(LLAMA_DIR "/Users/deva/Desktop/dev/llama.cpp")
include_directories(
    ${LLAMA_DIR}/include
    ${LLAMA_DIR}/ggml/include
)

add_library(llama_bridge SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/llama_bridge.cpp
)

# --- Import the prebuilt libllama.so shipped in jniLibs ---


# Expecting: android/app/src/main/jniLibs/<ABI>/libllama.so
add_library(llama_prebuilt SHARED IMPORTED)
set_target_properties(llama_prebuilt PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libllama.so"
)

find_library(log_lib log)

target_link_libraries(llama_bridge
    ${log_lib}
    llama_prebuilt
)

# Hide non-exported symbols (we export via `visibility("default")`)
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(llama_bridge PRIVATE -fvisibility=hidden)
endif()
