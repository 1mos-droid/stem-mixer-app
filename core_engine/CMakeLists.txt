cmake_minimum_required(VERSION 3.15)
project(StemEngine)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 1. Dependency Discovery
if(ANDROID)
    set(JNI_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../stem_ui/android/app/src/main/jniLibs/${ANDROID_ABI}")
    message(STATUS "ANDROID_ABI: ${ANDROID_ABI}")
    message(STATUS "JNI_LIBS_DIR: ${JNI_LIBS_DIR}")
    
    set(AVFORMAT_LIBRARIES "${JNI_LIBS_DIR}/libavformat.so")
    set(AVCODEC_LIBRARIES "${JNI_LIBS_DIR}/libavcodec.so")
    set(AVUTIL_LIBRARIES "${JNI_LIBS_DIR}/libavutil.so")
    set(SWRESAMPLE_LIBRARIES "${JNI_LIBS_DIR}/libswresample.so")
    set(ONNXRUNTIME_LIBRARY "${JNI_LIBS_DIR}/libonnxruntime.so")
    
    # Use local external headers for Android
    set(AV_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/include_external")
    set(ONNXRUNTIME_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include_external/onnxruntime")
else()
    # Desktop/Linux Linking via pkg-config
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(AVFORMAT REQUIRED libavformat)
    pkg_check_modules(AVCODEC REQUIRED libavcodec)
    pkg_check_modules(AVUTIL REQUIRED libavutil)
    pkg_check_modules(SWRESAMPLE REQUIRED libswresample)
    
    set(AV_INCLUDE_DIRS 
        ${AVFORMAT_INCLUDE_DIRS} 
        ${AVCODEC_INCLUDE_DIRS} 
        ${AVUTIL_INCLUDE_DIRS} 
        ${SWRESAMPLE_INCLUDE_DIRS}
    )

    find_path(ONNXRUNTIME_INCLUDE_DIR
        NAMES onnxruntime_cxx_api.h
        PATHS /usr/include/onnxruntime
    )

    find_library(ONNXRUNTIME_LIBRARY
        NAMES onnxruntime
        PATHS /usr/lib
    )
endif()

# 2. Include Directories
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${AV_INCLUDE_DIRS}
    ${ONNXRUNTIME_INCLUDE_DIR}
)

# 3. Targets
if(NOT ANDROID)
    add_executable(stem_engine 
        src/main.cpp 
        src/AudioDecoder.cpp 
        src/AudioEncoder.cpp 
        src/DemucsInference.cpp
    )

    target_link_libraries(stem_engine
        ${AVFORMAT_LIBRARIES}
        ${AVCODEC_LIBRARIES}
        ${AVUTIL_LIBRARIES}
        ${SWRESAMPLE_LIBRARIES}
        ${ONNXRUNTIME_LIBRARY}
    )
endif()

# Shared Library for FFI
add_library(stem_engine_ffi SHARED 
    src/bridge.cpp 
    src/AudioDecoder.cpp 
    src/AudioEncoder.cpp 
    src/DemucsInference.cpp
)

# Strip debug symbols in Release builds
set_target_properties(stem_engine_ffi PROPERTIES LINK_FLAGS_RELEASE -s)

target_link_libraries(stem_engine_ffi
    ${AVFORMAT_LIBRARIES}
    ${AVCODEC_LIBRARIES}
    ${AVUTIL_LIBRARIES}
    ${SWRESAMPLE_LIBRARIES}
    ${ONNXRUNTIME_LIBRARY}
    log # Android log library
)

