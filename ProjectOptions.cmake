include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(interpreting_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(interpreting_setup_options)
  option(interpreting_ENABLE_HARDENING "Enable hardening" ON)
  option(interpreting_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    interpreting_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    interpreting_ENABLE_HARDENING
    OFF)

  interpreting_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR interpreting_PACKAGING_MAINTAINER_MODE)
    option(interpreting_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(interpreting_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(interpreting_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(interpreting_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(interpreting_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(interpreting_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(interpreting_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(interpreting_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(interpreting_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(interpreting_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(interpreting_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(interpreting_ENABLE_PCH "Enable precompiled headers" OFF)
    option(interpreting_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(interpreting_ENABLE_IPO "Enable IPO/LTO" ON)
    option(interpreting_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(interpreting_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(interpreting_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(interpreting_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(interpreting_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(interpreting_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(interpreting_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(interpreting_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(interpreting_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(interpreting_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(interpreting_ENABLE_PCH "Enable precompiled headers" OFF)
    option(interpreting_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      interpreting_ENABLE_IPO
      interpreting_WARNINGS_AS_ERRORS
      interpreting_ENABLE_USER_LINKER
      interpreting_ENABLE_SANITIZER_ADDRESS
      interpreting_ENABLE_SANITIZER_LEAK
      interpreting_ENABLE_SANITIZER_UNDEFINED
      interpreting_ENABLE_SANITIZER_THREAD
      interpreting_ENABLE_SANITIZER_MEMORY
      interpreting_ENABLE_UNITY_BUILD
      interpreting_ENABLE_CLANG_TIDY
      interpreting_ENABLE_CPPCHECK
      interpreting_ENABLE_COVERAGE
      interpreting_ENABLE_PCH
      interpreting_ENABLE_CACHE)
  endif()

  interpreting_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (interpreting_ENABLE_SANITIZER_ADDRESS OR interpreting_ENABLE_SANITIZER_THREAD OR interpreting_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(interpreting_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(interpreting_global_options)
  if(interpreting_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    interpreting_enable_ipo()
  endif()

  interpreting_supports_sanitizers()

  if(interpreting_ENABLE_HARDENING AND interpreting_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR interpreting_ENABLE_SANITIZER_UNDEFINED
       OR interpreting_ENABLE_SANITIZER_ADDRESS
       OR interpreting_ENABLE_SANITIZER_THREAD
       OR interpreting_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${interpreting_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${interpreting_ENABLE_SANITIZER_UNDEFINED}")
    interpreting_enable_hardening(interpreting_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(interpreting_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(interpreting_warnings INTERFACE)
  add_library(interpreting_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  interpreting_set_project_warnings(
    interpreting_warnings
    ${interpreting_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(interpreting_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(interpreting_options)
  endif()

  include(cmake/Sanitizers.cmake)
  interpreting_enable_sanitizers(
    interpreting_options
    ${interpreting_ENABLE_SANITIZER_ADDRESS}
    ${interpreting_ENABLE_SANITIZER_LEAK}
    ${interpreting_ENABLE_SANITIZER_UNDEFINED}
    ${interpreting_ENABLE_SANITIZER_THREAD}
    ${interpreting_ENABLE_SANITIZER_MEMORY})

  set_target_properties(interpreting_options PROPERTIES UNITY_BUILD ${interpreting_ENABLE_UNITY_BUILD})

  if(interpreting_ENABLE_PCH)
    target_precompile_headers(
      interpreting_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(interpreting_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    interpreting_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(interpreting_ENABLE_CLANG_TIDY)
    interpreting_enable_clang_tidy(interpreting_options ${interpreting_WARNINGS_AS_ERRORS})
  endif()

  if(interpreting_ENABLE_CPPCHECK)
    interpreting_enable_cppcheck(${interpreting_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(interpreting_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    interpreting_enable_coverage(interpreting_options)
  endif()

  if(interpreting_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(interpreting_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(interpreting_ENABLE_HARDENING AND NOT interpreting_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR interpreting_ENABLE_SANITIZER_UNDEFINED
       OR interpreting_ENABLE_SANITIZER_ADDRESS
       OR interpreting_ENABLE_SANITIZER_THREAD
       OR interpreting_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    interpreting_enable_hardening(interpreting_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
