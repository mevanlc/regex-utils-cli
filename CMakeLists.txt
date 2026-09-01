cmake_minimum_required(VERSION 3.24)
project(regex_utils_cli LANGUAGES C)

include(CTest)
include(FetchContent)

option(REGEX_UTILS_ENABLE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
option(REGEX_UTILS_BUILD_REGEXTRIE_C
       "Build the RegexTrie C exercise" ON)
option(REGEX_UTILS_BUILD_TRE
       "Build the TRE agrep exercise" ON)

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

if(REGEX_UTILS_BUILD_TRE)
  if(WIN32)
    message(FATAL_ERROR
      "REGEX_UTILS_BUILD_TRE requires a POSIX host; the selected upstream build does not provide agrep on native Windows")
  endif()
  if(NOT EXISTS "/bin/sh")
    message(FATAL_ERROR "REGEX_UTILS_BUILD_TRE requires /bin/sh")
  endif()
  if(REGEX_UTILS_ENABLE_SANITIZERS AND
     NOT CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    message(FATAL_ERROR
      "REGEX_UTILS_ENABLE_SANITIZERS requires a Clang or GCC C compiler")
  endif()

  include(ExternalProject)

  set(TRE_FIND_PROGRAM_OPTIONS
    REQUIRED
    NO_CACHE
    NO_CMAKE_PATH
    NO_CMAKE_ENVIRONMENT_PATH
    NO_CMAKE_SYSTEM_PATH
    NO_CMAKE_INSTALL_PREFIX
  )
  find_program(TRE_MAKE_PROGRAM NAMES gmake make
    ${TRE_FIND_PROGRAM_OPTIONS})
  foreach(tool IN ITEMS autoconf autoheader automake aclocal autopoint)
    string(TOUPPER "${tool}" tool_upper)
    find_program("TRE_${tool_upper}" "${tool}"
      ${TRE_FIND_PROGRAM_OPTIONS})
  endforeach()
  find_program(TRE_LIBTOOLIZE NAMES glibtoolize libtoolize
    ${TRE_FIND_PROGRAM_OPTIONS})

  set(TRE_COMMIT 71bfcaf0af3994384987c6c2679ed7d078ffe189)
  set(TRE_INSTALL_DIR "${CMAKE_BINARY_DIR}/tre-install")
  set(TRE_AGREP "${TRE_INSTALL_DIR}/bin/agrep")
  set(TRE_CFLAGS "-O0 -g3 -Wall -Wextra -Wpedantic")
  set(TRE_LDFLAGS "")
  if(REGEX_UTILS_ENABLE_SANITIZERS)
    string(APPEND TRE_CFLAGS
      " -fsanitize=address,undefined -fno-omit-frame-pointer")
    set(TRE_LDFLAGS "-fsanitize=address,undefined")
  endif()

  ExternalProject_Add(
    tre_upstream
    URL
      "https://github.com/laurikari/tre/archive/${TRE_COMMIT}.tar.gz"
    URL_HASH
      "SHA256=8f630500dcd10ad5c086e3e8e851888107ecca93c384793f856384c6a5c19664"
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
    PREFIX "${CMAKE_BINARY_DIR}/tre"
    INSTALL_DIR "${TRE_INSTALL_DIR}"
    UPDATE_DISCONNECTED TRUE
    PATCH_COMMAND
      "${CMAKE_COMMAND}" -E chdir <SOURCE_DIR> /bin/sh ./utils/autogen.sh
    CONFIGURE_COMMAND
      "${CMAKE_COMMAND}" -E env
        "CC=${CMAKE_C_COMPILER}"
        "CFLAGS=${TRE_CFLAGS}"
        "LDFLAGS=${TRE_LDFLAGS}"
        <SOURCE_DIR>/configure
          --prefix=<INSTALL_DIR>
          --disable-shared
          --enable-static
          --disable-nls
          --disable-system-abi
          --disable-debug
          --enable-warnings
          --enable-approx
          --enable-agrep
          --enable-wchar
          --enable-multibyte
    BUILD_COMMAND "${TRE_MAKE_PROGRAM}"
    INSTALL_COMMAND "${TRE_MAKE_PROGRAM}" install
  )

  ExternalProject_Get_Property(tre_upstream BINARY_DIR)
  add_custom_target(
    tre-upstream-check
    COMMAND "${TRE_MAKE_PROGRAM}" check
    WORKING_DIRECTORY "${BINARY_DIR}"
    DEPENDS tre_upstream
    USES_TERMINAL
  )

  if(BUILD_TESTING)
    add_test(
      NAME tre-agrep-cli
      COMMAND /bin/sh "${CMAKE_SOURCE_DIR}/tests/tre_agrep_cli_test.sh"
              "${TRE_AGREP}"
    )
    set_tests_properties(tre-agrep-cli PROPERTIES TIMEOUT 120)
    if(REGEX_UTILS_ENABLE_SANITIZERS)
      # A 65,536-byte literal reaches upstream's public limit but exhausts
      # its recursive compiler stack under ASan on the validated macOS host.
      # The normal suite retains that exact boundary check; sanitizer runs
      # cover all practical cases.
      set_property(TEST tre-agrep-cli APPEND PROPERTY ENVIRONMENT
        "REGEX_UTILS_TRE_SKIP_REGEX_LIMIT_TESTS=1")
    endif()
  endif()
endif()
