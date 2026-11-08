# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.15)

# Project-level configuration.
set(PROJECT_NAME "komodo_defi_framework")
project(${PROJECT_NAME} LANGUAGES CXX)

# Production startup uses the bundled DLL. An executable-only or stale archive
# must fail during packaging rather than strand generated-password wallets.
set(KDF_FRAMEWORK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
include("${CMAKE_CURRENT_SOURCE_DIR}/validate_native_library.cmake")

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "mm2_plugin.cpp"
)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Find all .exe and .dll files in the bin directory
file(GLOB BIN_FILES "${CMAKE_CURRENT_SOURCE_DIR}/bin/*.exe" "${CMAKE_CURRENT_SOURCE_DIR}/bin/*.dll")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(komodo_defi_framework_bundled_libraries

  # Defined in ../src/CMakeLists.txt.
  # This can be changed to accommodate different builds.
  $<TARGET_FILE:komodo_defi_framework>
  ${BIN_FILES}
  PARENT_SCOPE
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(mm2_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/bin/kdf.exe"
  PARENT_SCOPE
)
