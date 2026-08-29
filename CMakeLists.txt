cmake_minimum_required(VERSION 3.24)
project(regex_utils_cli LANGUAGES C)

include(CTest)
include(FetchContent)

option(REGEX_UTILS_ENABLE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
option(REGEX_UTILS_BUILD_REGEXTRIE_C
       "Build the RegexTrie C exercise" ON)

function(regex_utils_project_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /WX)
  elseif(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  endif()
endfunction()

function(regex_utils_runtime_directory target)
  set_target_properties(${target} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
  )
endfunction()

function(regex_utils_enable_sanitizers target)
  if(REGEX_UTILS_ENABLE_SANITIZERS)
    if(NOT CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
      message(FATAL_ERROR
        "REGEX_UTILS_ENABLE_SANITIZERS requires a Clang or GCC C compiler")
    endif()
    target_compile_options(${target} PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

if(REGEX_UTILS_BUILD_REGEXTRIE_C)
  FetchContent_Declare(
    regextrie_upstream
    URL
      "https://github.com/ikeofilic1/RegexTrie/archive/c35e88931f646a24ed9a1f09d0b13fb204a773b1.tar.gz"
    URL_HASH
      "SHA256=ed0e39fb3359927ff74f0a552a85e96371898ada82ca483fb68a115a73e7133c"
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
  )
  FetchContent_MakeAvailable(regextrie_upstream)

  add_library(regextrie_c_upstream STATIC
    "${regextrie_upstream_SOURCE_DIR}/src/trie.c"
  )
  target_include_directories(regextrie_c_upstream SYSTEM PUBLIC
    "${regextrie_upstream_SOURCE_DIR}/src"
  )
  target_compile_features(regextrie_c_upstream PUBLIC c_std_11)
  set_target_properties(regextrie_c_upstream PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS OFF
  )
  if(MSVC)
    target_compile_options(regextrie_c_upstream PRIVATE /W4)
  elseif(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(regextrie_c_upstream PRIVATE -Wall -Wextra -Wpedantic)
  endif()
  regex_utils_enable_sanitizers(regextrie_c_upstream)

  add_executable(regextrie-c native/regextrie_c_cli.c)
  target_link_libraries(regextrie-c PRIVATE regextrie_c_upstream)
  target_compile_features(regextrie-c PRIVATE c_std_11)
  set_target_properties(regextrie-c PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS OFF
  )
  regex_utils_project_warnings(regextrie-c)
  regex_utils_runtime_directory(regextrie-c)
  regex_utils_enable_sanitizers(regextrie-c)

  if(BUILD_TESTING)
    add_executable(regextrie-c-library-tests tests/regextrie_c_library_test.c)
    target_link_libraries(regextrie-c-library-tests PRIVATE regextrie_c_upstream)
    target_compile_features(regextrie-c-library-tests PRIVATE c_std_11)
    set_target_properties(regextrie-c-library-tests PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED YES
      C_EXTENSIONS OFF
    )
    regex_utils_project_warnings(regextrie-c-library-tests)
    regex_utils_enable_sanitizers(regextrie-c-library-tests)

    add_test(NAME regextrie-c-library COMMAND regextrie-c-library-tests)
    add_test(
      NAME regextrie-c-cli
      COMMAND sh "${CMAKE_SOURCE_DIR}/tests/regextrie_c_cli_test.sh"
                 "$<TARGET_FILE:regextrie-c>"
    )
  endif()
endif()
