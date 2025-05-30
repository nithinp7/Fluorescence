cmake_minimum_required(VERSION 3.24 FATAL_ERROR)

option(BUILD_FLR_APP "Build Fluorescence as a standalone app" on)

project(
    Fluorescence
    VERSION 0.1.0
    LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

function(glob_files out_var_name regexes)
    set(files "")
    foreach(arg ${ARGV})
        list(APPEND regexes_only "${arg}")
    endforeach()
    list(POP_FRONT regexes_only)
    if (GLOB_USE_CONFIGURE_DEPENDS)
        file(GLOB_RECURSE files CONFIGURE_DEPENDS ${regexes_only})
    else()
        file(GLOB files ${regexes_only})
    endif()
    set(${ARGV0} "${files}" PARENT_SCOPE)
endfunction()

include_directories(Include/Fluorescence Src)

glob_files(SRC_FILES_LIST "Src/*.cpp" "Src/*/*.cpp")
if (BUILD_FLR_APP)
  add_executable(Fluorescence ${SRC_FILES_LIST})
  target_compile_definitions(${PROJECT_NAME} PRIVATE BUILD_FLR_APP=1)
else()
  add_library(Fluorescence ${SRC_FILES_LIST})
  target_include_directories (Fluorescence
      PUBLIC
        Include
  )
  target_compile_definitions(${PROJECT_NAME} PRIVATE BUILD_FLR_APP=0)
endif()

target_compile_definitions(${PROJECT_NAME} PRIVATE MAX_UV_COORDS=4)

add_subdirectory(Extern/Althea)
if (MSVC)
  add_compile_options(/MP)
  target_link_options(Fluorescence PRIVATE $<$<CONFIG:Debug>:/INCREMENTAL>)
  target_compile_options(Fluorescence PRIVATE $<$<CONFIG:Debug>:/ZI>)
endif()

target_link_libraries(${PROJECT_NAME} PUBLIC Althea)

