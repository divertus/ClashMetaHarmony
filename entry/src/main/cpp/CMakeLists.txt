# The native side of the VPN experiment.
#
# `napi_init.cpp` is deliberately tiny: it exists to answer one question --
# can native code take the file descriptor that `vpnExtension.create()`
# returns? That is the boundary a mihomo core would have to sit behind, so it
# is the boundary worth proving before porting anything.
#
# Built by hvigor through `entry/build-profile.json5`'s `externalNativeOptions`
# with the OHOS NDK toolchain (`aarch64-unknown-linux-ohos-clang`).

cmake_minimum_required(VERSION 3.5.0)
project(clashcore)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(clashcore SHARED napi_init.cpp)

add_library(clash SHARED IMPORTED)
set_target_properties(clash PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/arm64-v8a/libclash.so"
    IMPORTED_SONAME "libclash.so")

add_library(logstub SHARED IMPORTED)
set_target_properties(logstub PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/arm64-v8a/liblog.so"
    IMPORTED_SONAME "liblog.so")

target_link_libraries(clashcore PUBLIC libace_napi.z.so clash logstub)
