# Top-level helper Makefile (Linux)
# Usage:
#   make build    # configure + build with cmake in build/
#   make clean    # remove build dir
#   make run      # run executable (from build/)
CMAKE := cmake
BUILD_DIR := build
CMAKE_FLAGS := -DCMAKE_Fortran_COMPILER=ifort -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_CUDA_COMPILER=$(shell which nvcc)

.PHONY: build clean run

build:
	@mkdir -p $(BUILD_DIR)
	@(cd $(BUILD_DIR) && $(CMAKE) .. $(CMAKE_FLAGS))
	@(cd $(BUILD_DIR) && $(CMAKE) --build . --config Release)

run:
	@$(BUILD_DIR)/test_fortran

clean:
	@rm -rf $(BUILD_DIR)