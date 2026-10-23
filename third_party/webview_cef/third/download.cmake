# Official CEF "Standard Distribution" from the Spotify automated builds CDN
# (https://cef-builds.spotifycdn.com). All platforms are kept on the same
# CEF/Chromium version. To bump CEF, change CEF_VERSION below.
set(CEF_CDN "https://cef-builds.spotifycdn.com")
set(CEF_VERSION "149.0.4+g2f1bfd8+chromium-149.0.7827.156")

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(STATUS "current system is Linux")
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" OR
           CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64" OR
           CMAKE_CXX_COMPILER_TARGET MATCHES "aarch64" OR
           CMAKE_CXX_COMPILER_TARGET MATCHES "arm64")
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_linuxarm64.tar.bz2")
    else()
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_linux64.tar.bz2")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    message(STATUS "current system is Windows")
    # Use the official CEF standard distribution and build libcef_dll_wrapper
    # from source (see windows/CMakeLists.txt), the same way Linux does.
    if(CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_windowsarm64.tar.bz2")
    else()
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_windows64.tar.bz2")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    message(STATUS "current system is macOS")
    if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "arm64")
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_macosarm64.tar.bz2")
    else()
        set(cef_prebuilt_version "cef_binary_${CEF_VERSION}_macosx64.tar.bz2")
    endif()
else()
    message(FATAL_ERROR "Unsupported CEF platform: ${CMAKE_SYSTEM_NAME}")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/validate_cef.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/custom_cef.cmake")

# The CDN path requires '+' to be percent-encoded as %2B.
string(REPLACE "+" "%2B" cef_prebuilt_url_name "${cef_prebuilt_version}")
set(cef_prebuilt_path "${CEF_CDN}/${cef_prebuilt_url_name}")


function(extract_file filename extract_dir output_root)
    message(STATUS "Extracting CEF into ${extract_dir}")
    file(MAKE_DIRECTORY "${extract_dir}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar -xf "${filename}"
        WORKING_DIRECTORY "${extract_dir}"
        RESULT_VARIABLE extract_result ERROR_VARIABLE extract_error)
    if(NOT extract_result EQUAL 0)
        message(FATAL_ERROR "CEF extraction failed: ${extract_error}")
    endif()
    string(REGEX REPLACE "\\.tar\\.bz2$" "" package_root "${cef_prebuilt_version}")
    file(GLOB contents "${extract_dir}/*")
    list(LENGTH contents count)
    if(NOT count EQUAL 1 OR NOT IS_DIRECTORY "${extract_dir}/${package_root}")
        message(FATAL_ERROR "Unexpected CEF archive layout: expected ${package_root}")
    endif()
    set(${output_root} "${extract_dir}/${package_root}" PARENT_SCOPE)
endfunction()

function(download_file url filename)
    message(STATUS "Downloading CEF from ${url}")
    file(DOWNLOAD "${url}" "${filename}" STATUS download_status SHOW_PROGRESS
        TLS_VERIFY ON TIMEOUT 1800 INACTIVITY_TIMEOUT 60)
    list(GET download_status 0 download_code)
    if(NOT download_code EQUAL 0)
        file(REMOVE "${filename}")
        message(FATAL_ERROR "CEF download failed: ${download_status}. Re-run the build to retry.")
    endif()
endfunction()

function(prepare_prebuilt_files filepath)
    get_filename_component(filepath "${filepath}" ABSOLUTE)
    get_filename_component(parent "${filepath}" DIRECTORY)
    file(MAKE_DIRECTORY "${parent}")
    # Flutter exposes path plugins through .plugin_symlinks on Windows. Newer
    # libarchive correctly rejects extraction through a symlink ancestor, even
    # when the archive itself contains no symlinks. Canonicalize the existing
    # parent before creating lock/staging/cache paths; do not relax extraction
    # safety or resolve an as-yet nonexistent cache directory.
    get_filename_component(cache_name "${filepath}" NAME)
    get_filename_component(parent "${parent}" REALPATH)
    set(filepath "${parent}/${cache_name}")
    # Debug/release or separate build trees can share this source cache.
    file(LOCK "${filepath}.lock" GUARD FUNCTION TIMEOUT 1800)
    set(work "${filepath}.prepare")
    set(previous "${filepath}.previous")
    # Recover if a process stopped between the two same-filesystem renames.
    if(NOT EXISTS "${filepath}" AND EXISTS "${previous}")
        file(RENAME "${previous}" "${filepath}")
    endif()

    cef_custom_archive("${cef_prebuilt_version}" custom_archive custom_digest wanted_version)
    set(local_version "")
    if(EXISTS "${filepath}/version.txt")
        file(READ "${filepath}/version.txt" local_version)
        string(STRIP "${local_version}" local_version)
    endif()
    if(local_version STREQUAL wanted_version)
        cef_validate_distribution("${filepath}" "${CMAKE_SYSTEM_NAME}" complete reason)
        if(complete)
            cef_validate_version("${filepath}" "${CEF_VERSION}" complete reason)
        endif()
        if(complete)
            message(STATUS "CEF cache verified: ${filepath}")
            file(REMOVE_RECURSE "${work}" "${previous}")
            return()
        endif()
        message(STATUS "Incomplete CEF cache (${reason}); preparing a clean replacement")
    else()
        message(STATUS "Preparing CEF ${cef_prebuilt_version}")
    endif()

    # Never delete the current cache before download/extraction/validation have
    # succeeded. Failed work is not version-stamped and is retried next time.
    file(REMOVE_RECURSE "${work}")
    file(MAKE_DIRECTORY "${work}")
    set(archive "${work}/distribution.tar.bz2")
    if(custom_archive)
        message(STATUS "Using developer-supplied CEF archive: ${custom_archive}")
        # Copy first so a concurrently replaced input cannot change after hash
        # verification. All headers, runtime and resources come from one bundle.
        file(COPY "${custom_archive}" DESTINATION "${work}")
        file(RENAME "${work}/${cef_prebuilt_version}" "${archive}")
        file(SHA256 "${archive}" actual_hash)
        if(NOT actual_hash STREQUAL custom_digest)
            message(FATAL_ERROR "Custom CEF SHA-256 mismatch; existing cache is unchanged.")
        endif()
    else()
        download_file("${cef_prebuilt_path}.sha1" "${work}/checksum.sha1")
        file(READ "${work}/checksum.sha1" expected_hash)
        string(STRIP "${expected_hash}" expected_hash)
        string(LENGTH "${expected_hash}" hash_length)
        if(NOT hash_length EQUAL 40 OR NOT expected_hash MATCHES "^[0-9a-fA-F]+$")
            message(FATAL_ERROR "Invalid CEF checksum from ${cef_prebuilt_path}.sha1")
        endif()
        download_file("${cef_prebuilt_path}" "${archive}")
        file(SHA1 "${archive}" actual_hash)
        string(TOLOWER "${expected_hash}" expected_hash)
        if(NOT actual_hash STREQUAL expected_hash)
            message(FATAL_ERROR "CEF archive checksum mismatch. Re-run the build to retry.")
        endif()
    endif()
    extract_file("${archive}" "${work}/extracted" staged)
    cef_validate_distribution("${staged}" "${CMAKE_SYSTEM_NAME}" complete reason)
    if(complete)
        cef_validate_version("${staged}" "${CEF_VERSION}" complete reason)
    endif()
    if(NOT complete)
        message(FATAL_ERROR "Incomplete extracted CEF distribution: ${reason}")
    endif()

    # Official CEF uses arm64; Linux also reports aarch64. Avoid a host sed
    # dependency, and apply the patch only to the newly validated distribution.
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set(variables "${staged}/cmake/cef_variables.cmake")
        file(READ "${variables}" contents)
        string(REPLACE [=["${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "arm64"]=]
            [=[("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "arm64" OR "${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "aarch64")]=]
            contents "${contents}")
        file(WRITE "${variables}" "${contents}")
    endif()
    file(WRITE "${staged}/version.txt" "${wanted_version}")
    file(REMOVE_RECURSE "${previous}")
    if(EXISTS "${filepath}")
        file(RENAME "${filepath}" "${previous}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E rename "${staged}" "${filepath}"
        RESULT_VARIABLE install_result ERROR_VARIABLE install_error)
    if(NOT install_result EQUAL 0)
        if(EXISTS "${previous}")
            file(RENAME "${previous}" "${filepath}")
        endif()
        message(FATAL_ERROR "Could not install CEF: ${install_error}")
    endif()
    file(REMOVE_RECURSE "${previous}" "${work}")
    message(STATUS "CEF distribution installed and verified: ${filepath}")
endfunction()

# CocoaPods can reuse the exact same verified preparation path per architecture.
if(DEFINED CEF_PREPARE_DEST)
    prepare_prebuilt_files("${CEF_PREPARE_DEST}")
endif()
