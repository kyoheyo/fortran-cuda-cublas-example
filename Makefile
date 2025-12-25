# Makefile for fortran-cuda-cublas-example
# Use:
#   make build           # configure & build
#   make run             # run (auto-detect GPU)
#   make run MODE=gpu    # force GPU
#   make run MODE=cpu    # force CPU
#   make run USE_GPU=1   # equivalent to MODE=gpu
#   make run USE_GPU=0   # equivalent to MODE=cpu
#   make run-gpu         # shortcut for MODE=gpu
#   make run-cpu         # shortcut for MODE=cpu
#   make clean           # remove build dir
#
# You can override CUDA lib path if needed:
#   make run CUDA_LIB_DIR=/path/to/cuda/lib64

CMAKE := cmake
BUILD_DIR := build
# If nvcc is not in PATH, set CUDA_BIN or set CMAKE_CUDA_COMPILER explicitly
NVCC := $(shell which nvcc 2>/dev/null)
CMAKE_FLAGS := -DCMAKE_Fortran_COMPILER=ifort -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_CUDA_COMPILER=$(NVCC)

# Default CUDA lib dir; override on command line if needed
CUDA_LIB_DIR ?= /usr/local/cuda-12.2/lib64

.PHONY: build clean run

build:
# 	在目录已存在时不报错并会递归创建父目录
	@mkdir -p $(BUILD_DIR)
# 	在 build 目录运行 cmake 配置（生成 makefile）
	@(cd $(BUILD_DIR) && $(CMAKE) .. $(CMAKE_FLAGS))
# 	在 build 目录调用 cmake --build，把 -j 和 --no-print-directory 传给底层 make，使并行且不打印进入/离开目录信息
	@(cd $(BUILD_DIR) && $(CMAKE) --build . --config Release -- -j$(NPROCS) --no-print-directory)

# MODE: "gpu" or "cpu"
# USE_GPU: 1 (gpu) or 0 (cpu) — legacy-compatible
run:
	@if [ ! -x "$(BUILD_DIR)/test_fortran" ]; then \
	  echo "Binary not found, building first..."; \
	  $(MAKE) build; \
	fi; \
	\
	# Determine desired mode
	@if [ "$(USE_GPU)" = "1" ] || [ "$(MODE)" = "gpu" ]; then \
	  echo "Running with GPU (USE_GPU=1)"; \
	  LD_LIBRARY_PATH="$(CUDA_LIB_DIR):$$LD_LIBRARY_PATH" USE_GPU=1 $(BUILD_DIR)/test_fortran; \
	elif [ "$(USE_GPU)" = "0" ] || [ "$(MODE)" = "cpu" ]; then \
	  echo "Running with CPU (USE_GPU=0)"; \
	  LD_LIBRARY_PATH="$(CUDA_LIB_DIR):$$LD_LIBRARY_PATH" USE_GPU=0 $(BUILD_DIR)/test_fortran; \
	else \
	  echo "Running with auto-detect (no USE_GPU set)"; \
	  LD_LIBRARY_PATH="$(CUDA_LIB_DIR):$$LD_LIBRARY_PATH" $(BUILD_DIR)/test_fortran; \
	fi

run-gpu:
	@$(MAKE) run MODE=gpu

run-cpu:
	@$(MAKE) run MODE=cpu

clean:
	@rm -rf $(BUILD_DIR)