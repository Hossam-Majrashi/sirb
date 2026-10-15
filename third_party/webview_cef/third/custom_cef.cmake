# Optional developer-supplied, legally distributable Standard Distributions.
# Shared by Linux/Windows CMake and the macOS CocoaPods preparation path.
# No binary mirror is trusted implicitly and no codec support is inferred from
# a filename/stamp. Verify actual decoding with tool/verify_stream_codecs.py.
function(cef_custom_archive package archive digest identity)
  set(directory "$ENV{SIRB_CEF_ARCHIVE_DIR}")
  set(${archive} "" PARENT_SCOPE)
  set(${digest} "" PARENT_SCOPE)
  set(${identity} "${package}" PARENT_SCOPE)
  if(directory STREQUAL "")
    return()
  endif()
  file(TO_CMAKE_PATH "${directory}" directory)
  get_filename_component(directory "${directory}" ABSOLUTE)
  set(path "${directory}/${package}")
  if(NOT EXISTS "${path}" OR IS_DIRECTORY "${path}" OR NOT EXISTS "${path}.sha256")
    message(FATAL_ERROR "SIRB_CEF_ARCHIVE_DIR requires ${path} and ${path}.sha256; refusing to fall back to the codec-limited official build.")
  endif()
  file(READ "${path}.sha256" expected)
  string(STRIP "${expected}" expected)
  string(LENGTH "${expected}" length)
  if(NOT length EQUAL 64 OR NOT expected MATCHES "^[0-9a-fA-F]+$")
    message(FATAL_ERROR "Invalid custom CEF SHA-256 sidecar: ${path}.sha256 (expected a bare digest)")
  endif()
  string(TOLOWER "${expected}" expected)
  set(${archive} "${path}" PARENT_SCOPE)
  set(${digest} "${expected}" PARENT_SCOPE)
  set(${identity} "${package}|sha256=${expected}" PARENT_SCOPE)
endfunction()

# macOS needs the same identity BEFORE its prepared-framework fast path. The
# helper uses only CMake 3.10, no Python, jq or platform-specific checksum tool.
if(DEFINED CEF_IDENTITY_PACKAGE AND DEFINED CEF_IDENTITY_OUTPUT)
  cef_custom_archive("${CEF_IDENTITY_PACKAGE}" archive digest identity)
  file(WRITE "${CEF_IDENTITY_OUTPUT}" "${identity}")
endif()
