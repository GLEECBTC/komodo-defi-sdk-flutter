# Standalone invocation: cmake -DKDF_FRAMEWORK_DIR=<package> -P <this file>
# KDF_READELF may select GNU readelf or llvm-readelf for cross-packaging.
cmake_minimum_required(VERSION 3.15)

if(NOT DEFINED KDF_FRAMEWORK_DIR)
  message(FATAL_ERROR "KDF_FRAMEWORK_DIR must identify the framework package.")
endif()
if(DEFINED FLUTTER_TARGET_PLATFORM AND NOT FLUTTER_TARGET_PLATFORM STREQUAL "linux-x64")
  message(FATAL_ERROR "The pinned Linux KDF artifact supports only linux-x64.")
endif()

set(KDF_LINUX_BIN "${KDF_FRAMEWORK_DIR}/linux/bin")
set(KDF_LINUX_LIBRARIES "")
foreach(NAME libkdflib.so libkdflib_static.so)
  set(LIBRARY "${KDF_LINUX_BIN}/${NAME}")
  if(IS_SYMLINK "${LIBRARY}")
    message(FATAL_ERROR "Linked KDF runtime files are not allowed.")
  endif()
  if(EXISTS "${LIBRARY}")
    list(APPEND KDF_LINUX_LIBRARIES "${LIBRARY}")
  endif()
endforeach()
if(NOT KDF_LINUX_LIBRARIES)
  message(FATAL_ERROR
    "Missing verified Linux bin/libkdflib.so or bin/libkdflib_static.so. "
    "An executable-only KDF archive cannot be used for wallet credentials.")
endif()

function(kdf_linux_json_string JSON KEY OUTPUT)
  string(REGEX MATCH "\"${KEY}\"[ \t\r\n]*:[ \t\r\n]*\"([^\"]+)\"" MATCH "${JSON}")
  if(NOT MATCH)
    message(FATAL_ERROR "Missing KDF provenance field: ${KEY}.")
  endif()
  set(${OUTPUT} "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

function(kdf_linux_json_checksums JSON KEY OUTPUT)
  string(REGEX MATCH "\"${KEY}\"[ \t\r\n]*:[ \t\r\n]*\\[([^]]+)\\]" MATCH "${JSON}")
  if(NOT MATCH)
    message(FATAL_ERROR "Missing KDF checksum set: ${KEY}.")
  endif()
  string(REGEX MATCHALL "\"[a-f0-9]+\"" VALUES "${CMAKE_MATCH_1}")
  set(CHECKSUMS "")
  foreach(VALUE IN LISTS VALUES)
    string(REPLACE "\"" "" VALUE "${VALUE}")
    string(LENGTH "${VALUE}" LENGTH)
    if(NOT LENGTH EQUAL 64 OR VALUE STREQUAL
        "0000000000000000000000000000000000000000000000000000000000000000")
      message(FATAL_ERROR "Invalid KDF checksum set: ${KEY}.")
    endif()
    list(APPEND CHECKSUMS "${VALUE}")
  endforeach()
  if(NOT CHECKSUMS)
    message(FATAL_ERROR "Empty KDF checksum set: ${KEY}.")
  endif()
  list(SORT CHECKSUMS)
  set(${OUTPUT} "${CHECKSUMS}" PARENT_SCOPE)
endfunction()

file(READ "${KDF_FRAMEWORK_DIR}/app_build/build_config.json" KDF_MANIFEST)
file(READ "${KDF_LINUX_BIN}/.api_last_updated_linux" KDF_MARKER)
# The filename regexp can contain braces; anchor to the extraction path.
string(REGEX MATCH "\"linux\"[ \t\r\n]*:[ \t\r\n]*\\{.*\"path\"[ \t\r\n]*:[ \t\r\n]*\"linux/bin\"" KDF_PLATFORM "${KDF_MANIFEST}")
kdf_linux_json_string("${KDF_MANIFEST}" "api_commit_hash" KDF_COMMIT)
kdf_linux_json_string("${KDF_MARKER}" "api_commit_hash" KDF_MARKER_COMMIT)
string(LENGTH "${KDF_COMMIT}" KDF_COMMIT_LENGTH)
if(NOT KDF_COMMIT_LENGTH EQUAL 40 OR NOT KDF_COMMIT MATCHES "^[a-f0-9]+$" OR
    NOT KDF_COMMIT STREQUAL KDF_MARKER_COMMIT)
  message(FATAL_ERROR "Linux KDF artifact commit does not match the immutable manifest.")
endif()
kdf_linux_json_checksums("${KDF_PLATFORM}" "valid_zip_sha256_checksums" KDF_CHECKSUMS)
kdf_linux_json_checksums("${KDF_MARKER}" "checksums" KDF_MARKER_CHECKSUMS)
kdf_linux_json_string("${KDF_MARKER}" "archive_sha256" KDF_ARCHIVE_SHA)
list(FIND KDF_CHECKSUMS "${KDF_ARCHIVE_SHA}" KDF_ARCHIVE_INDEX)
if(NOT KDF_CHECKSUMS STREQUAL KDF_MARKER_CHECKSUMS OR KDF_ARCHIVE_INDEX LESS 0)
  message(FATAL_ERROR "Linux KDF archive checksum does not match the immutable manifest.")
endif()

# Match the build transformer's complete deterministic Linux runtime-set digest.
# The executable remains part of archive provenance but is never bundled or run.
set(KDF_RUNTIME_NAMES kdf mm2 libmm2.so libkdflib.so libkdflib_static.so)
list(SORT KDF_RUNTIME_NAMES)
set(KDF_RUNTIME_JSON "[")
set(KDF_JSON_SEPARATOR "")
set(KDF_ENTRYPOINTS "")
foreach(NAME IN LISTS KDF_RUNTIME_NAMES)
  set(FILE "${KDF_LINUX_BIN}/${NAME}")
  if(IS_SYMLINK "${FILE}")
    message(FATAL_ERROR "Linked KDF runtime files are not allowed.")
  endif()
  if(EXISTS "${FILE}")
    file(SHA256 "${FILE}" DIGEST)
    string(APPEND KDF_RUNTIME_JSON "${KDF_JSON_SEPARATOR}[\"${NAME}\",\"${DIGEST}\"]")
    set(KDF_JSON_SEPARATOR ",")
    if(NAME STREQUAL "kdf" OR NAME STREQUAL "mm2")
      list(APPEND KDF_ENTRYPOINTS "${NAME}")
      set(KDF_CORE_SHA "${DIGEST}")
    endif()
  endif()
endforeach()
string(APPEND KDF_RUNTIME_JSON "]")
string(SHA256 KDF_RUNTIME_SHA "${KDF_RUNTIME_JSON}")
kdf_linux_json_string("${KDF_MARKER}" "runtime_set_sha256" KDF_EXPECTED_RUNTIME_SHA)
kdf_linux_json_string("${KDF_MARKER}" "artifact_sha256" KDF_EXPECTED_CORE_SHA)
list(LENGTH KDF_ENTRYPOINTS KDF_ENTRYPOINT_COUNT)
if(NOT KDF_ENTRYPOINT_COUNT EQUAL 1 OR
    NOT KDF_CORE_SHA STREQUAL KDF_EXPECTED_CORE_SHA OR
    NOT KDF_RUNTIME_SHA STREQUAL KDF_EXPECTED_RUNTIME_SHA)
  message(FATAL_ERROR "Linux KDF library/runtime bytes do not match their verified artifact marker.")
endif()

if(NOT KDF_READELF)
  find_program(KDF_READELF NAMES readelf llvm-readelf)
endif()
if(NOT KDF_READELF)
  message(FATAL_ERROR "Linux KDF packaging requires readelf or llvm-readelf; set KDF_READELF for cross-packaging.")
endif()

foreach(LIBRARY IN LISTS KDF_LINUX_LIBRARIES)
  file(SIZE "${LIBRARY}" KDF_LIBRARY_SIZE)
  if(KDF_LIBRARY_SIZE LESS 64)
    message(FATAL_ERROR "Linux KDF ELF header is truncated.")
  endif()
  file(READ "${LIBRARY}" KDF_ELF_HEADER LIMIT 20 HEX)
  # ELF64, little-endian, current ELF version; ET_DYN; EM_X86_64.
  if(NOT KDF_ELF_HEADER MATCHES "^7f454c46020101[a-f0-9]+03003e00$")
    message(FATAL_ERROR "Linux KDF library must be an x64 ELF shared library.")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "LC_ALL=C" "${KDF_READELF}"
      --wide --program-headers --dynamic "${LIBRARY}"
    RESULT_VARIABLE KDF_ELF_STATUS
    OUTPUT_VARIABLE KDF_ELF_INFO
    ERROR_VARIABLE KDF_ELF_ERROR
  )
  if(NOT KDF_ELF_STATUS EQUAL 0 OR NOT KDF_ELF_ERROR STREQUAL "")
    message(FATAL_ERROR "Linux KDF ELF structure could not be validated.")
  endif()
  # PIE executables are also ET_DYN. Never accept the old kdf executable renamed
  # as a .so, including PIEs linked without a program interpreter.
  if(KDF_ELF_INFO MATCHES "[\r\n][ \t]+INTERP[ \t]" OR
      KDF_ELF_INFO MATCHES "FLAGS_1[^\r\n]*[ \t]PIE([ \t\r\n]|$)")
    message(FATAL_ERROR "Linux KDF ELF image is executable-only (PIE), not a shared library.")
  endif()
  if(NOT KDF_ELF_INFO MATCHES "[\r\n][ \t]+LOAD[ \t]" OR
      NOT KDF_ELF_INFO MATCHES "[\r\n][ \t]+DYNAMIC[ \t]")
    message(FATAL_ERROR "Linux KDF ELF load/dynamic segments are missing.")
  endif()

  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "LC_ALL=C" "${KDF_READELF}"
      --wide --dyn-syms "${LIBRARY}"
    RESULT_VARIABLE KDF_SYMBOL_STATUS
    OUTPUT_VARIABLE KDF_SYMBOL_INFO
    ERROR_VARIABLE KDF_SYMBOL_ERROR
  )
  if(NOT KDF_SYMBOL_STATUS EQUAL 0 OR NOT KDF_SYMBOL_ERROR STREQUAL "" OR
      NOT KDF_SYMBOL_INFO MATCHES
        "^[ \t\r\n]*Symbol table '\\.dynsym' contains ([0-9]+) entries:")
    message(FATAL_ERROR "Linux KDF dynamic symbol table could not be validated.")
  endif()
  set(KDF_SYMBOL_COUNT "${CMAKE_MATCH_1}")
  # Do not let characters in symbol names become CMake list separators/escapes.
  # Neither character occurs in a required KDF export or a readelf row prefix.
  string(REPLACE "\\" "?" KDF_SYMBOL_INFO "${KDF_SYMBOL_INFO}")
  string(REPLACE ";" "?" KDF_SYMBOL_INFO "${KDF_SYMBOL_INFO}")
  # Symbol names may contain newlines. Some readelf implementations print these
  # literally, permitting a name to impersonate another row. Require the complete
  # declared table with consecutive indices before trusting any exported name.
  string(REGEX MATCHALL "(^|[\r\n])[ \t]*[0-9]+:[^\r\n]*"
    KDF_SYMBOL_ROWS "${KDF_SYMBOL_INFO}")
  list(LENGTH KDF_SYMBOL_ROWS KDF_SYMBOL_ROW_COUNT)
  if(NOT KDF_SYMBOL_COUNT STREQUAL "${KDF_SYMBOL_ROW_COUNT}")
    message(FATAL_ERROR "Linux KDF dynamic symbol table rows are malformed.")
  endif()
  set(KDF_SYMBOL_INDEX 0)
  foreach(ROW IN LISTS KDF_SYMBOL_ROWS)
    string(REGEX MATCH "^[ \t\r\n]*([0-9]+):" KDF_ROW_INDEX "${ROW}")
    if(NOT CMAKE_MATCH_1 STREQUAL "${KDF_SYMBOL_INDEX}")
      message(FATAL_ERROR "Linux KDF dynamic symbol table rows are malformed.")
    endif()
    math(EXPR KDF_SYMBOL_INDEX "${KDF_SYMBOL_INDEX} + 1")
  endforeach()
  foreach(SYMBOL mm2_main mm2_main_status mm2_stop)
    # Anchor the complete symbol-table row. An arbitrary symbol name can itself
    # contain spaces and text resembling the remaining readelf columns.
    if(NOT KDF_SYMBOL_INFO MATCHES
        "(^|[\r\n])[ \t]*[0-9]+:[ \t]+[a-fA-F0-9]+[ \t]+[0-9]+[ \t]+FUNC[ \t]+GLOBAL[ \t]+DEFAULT[ \t]+[0-9]+[ \t]+${SYMBOL}([\r\n]|$)")
      message(FATAL_ERROR "Linux KDF library is missing the defined exported function ${SYMBOL}.")
    endif()
  endforeach()
endforeach()
message(STATUS "Verified pinned Linux x64 KDF shared libraries for packaging.")
