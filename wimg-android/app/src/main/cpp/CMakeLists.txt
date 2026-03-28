cmake_minimum_required(VERSION 3.22)
project(wimg-jni)

# JNI shim that bridges Kotlin ↔ libwimg C ABI
add_library(wimg-jni SHARED wimg_jni.c)

# Link against prebuilt libwimg.so from jniLibs
add_library(wimg SHARED IMPORTED)
set_target_properties(wimg PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libwimg.so
)

target_link_libraries(wimg-jni wimg log)
