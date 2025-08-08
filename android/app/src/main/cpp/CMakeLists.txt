cmake_minimum_required(VERSION 3.22.1)
project(llama_bridge)

add_library(llama_bridge SHARED
    llama_bridge.cpp
)

find_library(log-lib log)
target_link_libraries(llama_bridge ${log-lib})
