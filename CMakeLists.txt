cmake_minimum_required(VERSION 3.18)
project(fortran_cuda_cublas_example
  LANGUAGES Fortran C CXX CUDA
)

option(ENABLE_CUDA "Build CUDA/cuBLAS GPU backend" ON)

if (ENABLE_CUDA)
  find_package(CUDAToolkit REQUIRED)
  if (NOT CUDAToolkit_FOUND)
    message(FATAL_ERROR "CUDAToolkit not found. Make sure CUDA is installed and nvcc is available.")
  endif()
endif()

message(STATUS "Fortran compiler: ${CMAKE_Fortran_COMPILER_ID} ${CMAKE_Fortran_COMPILER}")

set(SRC_FORTRAN main.f90)
set(SRC_CUDA gpu_lib.cu)

if (ENABLE_CUDA)
  add_library(gpu_lib_cuda STATIC ${SRC_CUDA})
  set_target_properties(gpu_lib_cuda PROPERTIES POSITION_INDEPENDENT_CODE ON)
  # Use PIC on Unix; on Linux nvcc should emit PIC for static libs
  target_compile_options(gpu_lib_cuda PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler;-fPIC>)
  target_link_libraries(gpu_lib_cuda
    PUBLIC
      CUDAToolkit::cudart
      CUDAToolkit::cublas
  )
endif()

add_executable(test_fortran ${SRC_FORTRAN})

if (ENABLE_CUDA)
  target_link_libraries(test_fortran PRIVATE gpu_lib_cuda)
  if (UNIX)
    # ensure libstdc++ is available at link time if nvcc-generated objects need it
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