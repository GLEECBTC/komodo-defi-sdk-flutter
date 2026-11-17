# Keep compatible with the minimum CMake version supported by this plugin.
cmake_minimum_required(VERSION 3.15)

# Project-level configuration.
set(PROJECT_NAME "komodo_defi_framework")
project(${PROJECT_NAME} LANGUAGES CXX)

# Production uses only a verified shared library. Fail before packaging when
# the pinned release is executable-only or its extracted bytes are stale.
set(KDF_FRAMEWORK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
include("${CMAKE_CURRENT_SOURCE_DIR}/validate_native_library.cmake")

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
    "mm2_plugin.cc"
)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# List of absolute paths to libraries that should be bundled with the plugin.
# Flutter installs these under the relocatable application's lib/ directory.
# No executable is installed, either into the app or the user's home directory.
set(komodo_defi_framework_bundled_libraries

  # Defined in ../src/CMakeLists.txt.
  # This can be changed to accommodate different builds.
  $<TARGET_FILE:komodo_defi_framework>
  ${KDF_LINUX_LIBRARIES}
  PARENT_SCOPE
)
