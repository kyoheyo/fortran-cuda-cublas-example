# fortran-cuda-cublas-example

示例：Intel Fortran (ifort) 主程序调用由 C++/CUDA 实现的库，GPU 路径使用 cuBLAS 做矩阵乘法（DGEMM），并使用 CUDA kernel 做逐元素后处理；运行时支持 GPU/CPU 切换（通过环境变量 USE_GPU 或自动检测）。

文件

- gpu_lib.cu    : CUDA + cuBLAS 实现，导出 C 接口给 Fortran
- main.f90      : Fortran 主程序（使用 ISO_C_BINDING）
- Makefile      : 构建脚本
- LICENSE       : MIT
- .gitignore    : 常见忽略项

快速使用

1. 修改 Makefile 中的 CUDA_LIB_DIR（若 CUDA 不在 /usr/local/cuda）
2. 编译：
   make
3. 运行：
   - 自动检测（若有 GPU 则优先 GPU）: ./test
   - 强制 GPU: export USE_GPU=1; ./test
   - 强制 CPU: export USE_GPU=0; ./test

说明与注意

- 链接时需包含 libcudart 和 libcublas，并且要链接 C++ 标准库（-lstdc++）。
- Fortran 数组默认是 column-major，与 cuBLAS 的默认布局兼容（呼应 DGEMM 参数）。
- 若要把 CPU 路径换成高性能 BLAS（如 MKL 或 OpenBLAS），可替换 gemm_cpu_naive 实现。
- 这是教学示例，未做大规模性能优化（异步拷贝、流、分块等）。
