# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.15)

project(komodo_defi_framework_library VERSION 0.0.1 LANGUAGES C)

add_library(komodo_defi_framework SHARED
  "komodo_defi_framework.c"
)

set_target_properties(komodo_defi_framework PROPERTIES
  PUBLIC_HEADER komodo_defi_framework.h
  OUTPUT_NAME "komodo_defi_framework"
)

target_compile_definitions(komodo_defi_framework PUBLIC DART_SHARED_LIB)

if(ANDROID)
  set(KDFLIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../android/app/src/main/cpp/libs")
  set(KDFLIB_PATH "${KDFLIB_DIR}/${ANDROID_ABI}/libkdf.a")

  find_library(KDFLIB_PATH mm2 PATHS "${CMAKE_SOURCE_DIR}/path/to/library/directory" NO_DEFAULT_PATH )

  if(NOT EXISTS "${KDFLIB_PATH}")
    message(FATAL_ERROR "Static library '${KDFLIB_PATH}' not found. Please ensure it is present.")
  endif()
  
  # Force linking of all symbols to prevent them being optimised out 
  # due to the lack of direct usage in native code. Dart FFI is used to 
  # access the library functions.
  target_link_libraries(komodo_defi_framework PRIVATE
    "-Wl,--whole-archive"
    "${KDFLIB_PATH}"
    "-Wl,--no-whole-archive"
  )

  # Align LOAD segments to 16 KB so the library loads on Android 15+ devices
  # that use 16 KB memory pages (required by Google Play for apps targeting
  # Android 15+). Without this the prebuilt libkdf.a links a 4 KB-aligned .so
  # and Play reports the app as incompatible ("made for an older version").
  target_link_options(komodo_defi_framework PRIVATE
    "-Wl,-z,max-page-size=16384"
  )
endif()
