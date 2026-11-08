cmake_minimum_required(VERSION 3.20)
project(global_load_16_ir LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED REPO_ROOT OR NOT DEFINED SPIRV_HEADERS_ROOT)
    message(FATAL_ERROR "REPO_ROOT and SPIRV_HEADERS_ROOT are required")
endif()

file(GLOB_RECURSE BACKEND_SOURCES CONFIGURE_DEPENDS
    "${REPO_ROOT}/gpu/vk/eden/shader_recompiler/backend/spirv/*.cpp")
file(GLOB_RECURSE IR_SOURCES CONFIGURE_DEPENDS
    "${REPO_ROOT}/gpu/vk/eden/shader_recompiler/frontend/ir/*.cpp")
file(GLOB_RECURSE OPTIMIZATION_SOURCES CONFIGURE_DEPENDS
    "${REPO_ROOT}/gpu/vk/eden/shader_recompiler/ir_opt/*.cpp")
file(GLOB_RECURSE SIRIT_SOURCES CONFIGURE_DEPENDS
    "${REPO_ROOT}/gpu/vk/sirit/src/*.cpp")

# The fixture source may live next to this file (tests/global_load_16/) or one
# level up (tests/). Use whichever exists so a move can't break the build.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/global_load_16_ir.cpp")
    set(FIXTURE_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/global_load_16_ir.cpp")
elseif(EXISTS "${REPO_ROOT}/tests/global_load_16_ir.cpp")
    set(FIXTURE_SOURCE "${REPO_ROOT}/tests/global_load_16_ir.cpp")
else()
    message(FATAL_ERROR "global_load_16_ir.cpp not found in "
        "${CMAKE_CURRENT_SOURCE_DIR} or ${REPO_ROOT}/tests")
endif()

add_executable(global_load_16_ir
    "${FIXTURE_SOURCE}"
    ${BACKEND_SOURCES}
    ${IR_SOURCES}
    ${OPTIMIZATION_SOURCES}
    ${SIRIT_SOURCES})

target_include_directories(global_load_16_ir PRIVATE
    "${REPO_ROOT}/gpu/vk/compat"
    "${REPO_ROOT}/gpu/compat"
    "${REPO_ROOT}/gpu/vk/eden"
    "${REPO_ROOT}/gpu/third_party/suyu"
    "${REPO_ROOT}/gpu/vk/sirit/include"
    "${REPO_ROOT}/gpu/vk/sirit/src"
    "${SPIRV_HEADERS_ROOT}/include")

target_compile_definitions(global_load_16_ir PRIVATE
    NDEBUG MKWVK_INCLUDES=2 VK_NO_PROTOTYPES)

if(MSVC)
    target_compile_options(global_load_16_ir PRIVATE /W0 /O1 /EHsc)
else()
    target_compile_options(global_load_16_ir PRIVATE -w -O1)
endif()
