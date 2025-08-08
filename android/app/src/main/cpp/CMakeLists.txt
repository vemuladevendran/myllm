cmake_minimum_required(VERSION 3.22)
project(llama_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build our bridge .so
add_library(llama_bridge SHARED
    llama_bridge.cpp
)

# NDK log + dlopen
find_library(log-lib log)
target_link_libraries(llama_bridge ${log-lib} dl)

# (Optional) be strict
if (CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_options(llama_bridge PRIVATE -O3)
endif()
