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

  if(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(KDF_PLATFORM "android-armv7")
    set(KDF_MANIFEST_ARTIFACT_PATH
      "android/app/src/main/cpp/libs/armeabi-v7a")
  elseif(ANDROID_ABI STREQUAL "arm64-v8a")
    set(KDF_PLATFORM "android-aarch64")
    set(KDF_MANIFEST_ARTIFACT_PATH
      "android/app/src/main/cpp/libs/arm64-v8a")
  else()
    message(FATAL_ERROR "Unsupported KDF Android ABI '${ANDROID_ABI}'.")
  endif()

  set(KDF_BUILD_CONFIG
    "${CMAKE_CURRENT_SOURCE_DIR}/../app_build/build_config.json")
  set(KDF_PROVENANCE_MARKER
    "${KDFLIB_DIR}/${ANDROID_ABI}/.api_last_updated_${KDF_PLATFORM}")

  if(NOT EXISTS "${KDF_BUILD_CONFIG}")
    message(FATAL_ERROR "KDF build manifest '${KDF_BUILD_CONFIG}' not found.")
  endif()
  if(NOT EXISTS "${KDF_PROVENANCE_MARKER}")
    message(FATAL_ERROR
      "KDF provenance marker '${KDF_PROVENANCE_MARKER}' not found. Run the "
      "KDF build transformer before packaging Android.")
  endif()
  if(NOT EXISTS "${KDFLIB_PATH}")
    message(FATAL_ERROR
      "Static library '${KDFLIB_PATH}' not found. Run the KDF build "
      "transformer before packaging Android.")
  endif()

  file(READ "${KDF_BUILD_CONFIG}" KDF_BUILD_CONFIG_JSON)
  file(READ "${KDF_PROVENANCE_MARKER}" KDF_PROVENANCE_JSON)
  string(REPLACE "\n" "" KDF_BUILD_CONFIG_COMPACT "${KDF_BUILD_CONFIG_JSON}")
  string(REPLACE "\r" "" KDF_BUILD_CONFIG_COMPACT
    "${KDF_BUILD_CONFIG_COMPACT}")
  string(REPLACE " " "" KDF_BUILD_CONFIG_COMPACT
    "${KDF_BUILD_CONFIG_COMPACT}")

  string(REGEX MATCH
    "\"api_commit_hash\"[ \\t\\r\\n]*:[ \\t\\r\\n]*\"([a-f0-9]+)\""
    KDF_MANIFEST_COMMIT_MATCH "${KDF_BUILD_CONFIG_JSON}")
  set(KDF_MANIFEST_COMMIT "${CMAKE_MATCH_1}")
  string(REGEX MATCH
    "\"api_commit_hash\"[ \\t\\r\\n]*:[ \\t\\r\\n]*\"([a-f0-9]+)\""
    KDF_MARKER_COMMIT_MATCH "${KDF_PROVENANCE_JSON}")
  set(KDF_MARKER_COMMIT "${CMAKE_MATCH_1}")
  string(REGEX MATCH
    "\"valid_zip_sha256_checksums\":\\[\"([a-f0-9]+)\"\\],\"path\":\"${KDF_MANIFEST_ARTIFACT_PATH}\""
    KDF_MANIFEST_CHECKSUM_MATCH "${KDF_BUILD_CONFIG_COMPACT}")
  set(KDF_MANIFEST_CHECKSUM "${CMAKE_MATCH_1}")
  string(REGEX MATCH
    "\"checksums\"[ \\t\\r\\n]*:[ \\t\\r\\n]*\\[[ \\t\\r\\n]*\"([a-f0-9]+)\""
    KDF_MARKER_CHECKSUM_MATCH "${KDF_PROVENANCE_JSON}")
  set(KDF_MARKER_CHECKSUM "${CMAKE_MATCH_1}")
  string(REGEX MATCH
    "\"artifact_sha256\"[ \\t\\r\\n]*:[ \\t\\r\\n]*\"([a-f0-9]+)\""
    KDF_MARKER_ARTIFACT_CHECKSUM_MATCH "${KDF_PROVENANCE_JSON}")
  set(KDF_MARKER_ARTIFACT_CHECKSUM "${CMAKE_MATCH_1}")

  if(KDF_MANIFEST_COMMIT STREQUAL "" OR
      KDF_MARKER_COMMIT STREQUAL "" OR
      KDF_MANIFEST_CHECKSUM STREQUAL "" OR
      KDF_MARKER_CHECKSUM STREQUAL "")
    message(FATAL_ERROR "KDF artifact provenance is malformed.")
  endif()
  string(LENGTH "${KDF_MANIFEST_COMMIT}" KDF_MANIFEST_COMMIT_LENGTH)
  if(NOT KDF_MANIFEST_COMMIT_LENGTH EQUAL 40)
    message(FATAL_ERROR
      "KDF manifest must pin a full 40-character commit hash.")
  endif()
  if(KDF_MANIFEST_CHECKSUM STREQUAL
      "0000000000000000000000000000000000000000000000000000000000000000")
    message(FATAL_ERROR
      "KDF artifact release is blocked for ${KDF_PLATFORM} at "
      "${KDF_MANIFEST_COMMIT}; replace the all-zero checksum only after "
      "building the exact pinned commit archive.")
  endif()
  if(KDF_MARKER_ARTIFACT_CHECKSUM STREQUAL "")
    message(FATAL_ERROR
      "KDF artifact marker for ${KDF_PLATFORM} is missing the extracted "
      "library checksum; fetch the exact pinned artifact again.")
  endif()
  if(NOT KDF_MARKER_COMMIT STREQUAL KDF_MANIFEST_COMMIT)
    message(FATAL_ERROR
      "Stale KDF artifact for ${KDF_PLATFORM}: marker commit "
      "${KDF_MARKER_COMMIT} does not match manifest commit "
      "${KDF_MANIFEST_COMMIT}.")
  endif()
  if(NOT KDF_MARKER_CHECKSUM STREQUAL KDF_MANIFEST_CHECKSUM)
    message(FATAL_ERROR
      "KDF artifact checksum marker for ${KDF_PLATFORM} does not match the "
      "immutable manifest checksum.")
  endif()

  file(SHA256 "${KDFLIB_PATH}" KDF_ACTUAL_ARTIFACT_CHECKSUM)
  if(NOT KDF_ACTUAL_ARTIFACT_CHECKSUM STREQUAL
      KDF_MARKER_ARTIFACT_CHECKSUM)
    message(FATAL_ERROR
      "KDF library bytes for ${KDF_PLATFORM} do not match their verified "
      "artifact provenance marker.")
  endif()

  find_library(KDFLIB_PATH mm2 PATHS "${CMAKE_SOURCE_DIR}/path/to/library/directory" NO_DEFAULT_PATH )

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
