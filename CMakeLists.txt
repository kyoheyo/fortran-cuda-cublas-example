cmake_minimum_required(VERSION 3.10)
project(fortran_cuda_cublas_example
  LANGUAGES Fortran C CXX CUDA
)

# --- 消除 CMP0074: 让 find_package 使用 <Package>_ROOT 变量（如 CUDAToolkit_ROOT）
if (POLICY CMP0074)
  cmake_policy(SET CMP0074 NEW)
endif()

# --- 消除 CMP0104: 使用新的 CUDA 架构策略
if (POLICY CMP0104)
  cmake_policy(SET CMP0104 NEW)
endif()

# --- 如果用户没有显式传入 CUDA 架构，则设为 RTX A6000 的 compute capability (86)
#     可改为其它值或列表（如 "75;86"）以覆盖多种 GPU。
if (NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
  set(CMAKE_CUDA_ARCHITECTURES 86 CACHE STRING "CUDA architectures to build for" FORCE)
  # set(CMAKE_CUDA_ARCHITECTURES "75;80;86" CACHE STRING "CUDA architectures to build for" FORCE)
endif()

option(ENABLE_CUDA "Build CUDA/cuBLAS GPU backend" ON)

set(CUDA_LINK_TARGETS "")

if (ENABLE_CUDA)
  # Try modern CUDAToolkit first
  find_package(CUDAToolkit QUIET)
  if (CUDAToolkit_FOUND)
    message(STATUS "Found CUDAToolkit: ${CUDAToolkit_INCLUDE_DIRS}")
    # If imported targets exist, prefer them
    if (TARGET CUDAToolkit::cudart AND TARGET CUDAToolkit::cublas)
      message(STATUS "Using imported targets CUDAToolkit::cudart and CUDAToolkit::cublas")
      list(APPEND CUDA_LINK_TARGETS CUDAToolkit::cudart CUDAToolkit::cublas)
    else()
      # Try to find concrete library files under CUDAToolkit root or common locations
      set(_cuda_hints "")
      if (DEFINED CUDAToolkit_ROOT)
        list(APPEND _cuda_hints "${CUDAToolkit_ROOT}/lib64" "${CUDAToolkit_ROOT}/lib")
      endif()
      list(APPEND _cuda_hints "/usr/local/cuda/lib64" "/usr/lib/x86_64-linux-gnu")

      find_library(CUDA_CUDART_LIB cudart HINTS ${_cuda_hints} PATH_SUFFIXES lib lib64)
      find_library(CUDA_CUBLAS_LIB cublas HINTS ${_cuda_hints} PATH_SUFFIXES lib lib64)

      if (CUDA_CUDART_LIB)
        message(STATUS "Found cudart: ${CUDA_CUDART_LIB}")
        list(APPEND CUDA_LINK_TARGETS ${CUDA_CUDART_LIB})
      endif()
      if (CUDA_CUBLAS_LIB)
        message(STATUS "Found cublas: ${CUDA_CUBLAS_LIB}")
        list(APPEND CUDA_LINK_TARGETS ${CUDA_CUBLAS_LIB})
      endif()
    endif()
  else()
    message(STATUS "CUDAToolkit not found via modern package; try legacy FindCUDA or manual search")
    find_package(CUDA QUIET)
    if (CUDA_FOUND)
      message(STATUS "Legacy FindCUDA found: ${CUDA_TOOLKIT_ROOT_DIR}")
      if (DEFINED CUDA_CUDART_LIBRARY)
        list(APPEND CUDA_LINK_TARGETS ${CUDA_CUDART_LIBRARY})
      endif()
      if (DEFINED CUDA_CUBLAS_LIBRARIES)
        list(APPEND CUDA_LINK_TARGETS ${CUDA_CUBLAS_LIBRARIES})
      else()
        find_library(CUDA_CUBLAS_LIB cublas HINTS ${CUDA_TOOLKIT_ROOT_DIR}/lib64 /usr/local/cuda/lib64 PATH_SUFFIXES lib lib64)
        if (CUDA_CUBLAS_LIB)
          list(APPEND CUDA_LINK_TARGETS ${CUDA_CUBLAS_LIB})
        endif()
      endif()
    else()
      # final fallback manual find
      find_library(CUDA_CUDART_LIB cudart HINTS /usr/local/cuda/lib64 /usr/lib/x86_64-linux-gnu PATH_SUFFIXES lib lib64)
      find_library(CUDA_CUBLAS_LIB cublas HINTS /usr/local/cuda/lib64 /usr/lib/x86_64-linux-gnu PATH_SUFFIXES lib lib64)
      if (CUDA_CUDART_LIB)
        message(STATUS "Found cudart (manual): ${CUDA_CUDART_LIB}")
        list(APPEND CUDA_LINK_TARGETS ${CUDA_CUDART_LIB})
      endif()
      if (CUDA_CUBLAS_LIB)
        message(STATUS "Found cublas (manual): ${CUDA_CUBLAS_LIB}")
        list(APPEND CUDA_LINK_TARGETS ${CUDA_CUBLAS_LIB})
      endif()
    endif()
  endif()

  if (NOT CUDA_LINK_TARGETS)
    message(FATAL_ERROR "CUDA enabled but could not locate cudart / cublas. Ensure CUDA is installed and nvcc is on PATH, or set ENABLE_CUDA=OFF.")
  else()
    message(STATUS "CUDA link targets: ${CUDA_LINK_TARGETS}")
  endif()
endif()

message(STATUS "Fortran compiler: ${CMAKE_Fortran_COMPILER_ID} ${CMAKE_Fortran_COMPILER}")

set(SRC_FORTRAN main.f90)
set(SRC_CUDA gpu_lib.cu)

if (ENABLE_CUDA)
  add_library(gpu_lib_cuda STATIC ${SRC_CUDA})
  set_target_properties(gpu_lib_cuda PROPERTIES POSITION_INDEPENDENT_CODE ON)
  target_compile_options(gpu_lib_cuda PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler;-fPIC>)
  target_link_libraries(gpu_lib_cuda PUBLIC ${CUDA_LINK_TARGETS})
endif()

add_executable(test_fortran ${SRC_FORTRAN})

if (ENABLE_CUDA)
  target_link_libraries(test_fortran PRIVATE gpu_lib_cuda)
  if (UNIX)
    find_library(STDCXX_LIB stdc++)
    if (STDCXX_LIB)
      target_link_libraries(test_fortran PRIVATE ${STDCXX_LIB})
    endif()
  endif()
endif()

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

message(STATUS "ENABLE_CUDA = ${ENABLE_CUDA}")
message(STATUS "CMake generator: ${CMAKE_GENERATOR}")