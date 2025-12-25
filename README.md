
# fortran-cuda-cublas-example (Linux / ifort)

示例：Intel Fortran (ifort) 主程序调用由 C++/CUDA 实现的库，GPU 路径使用 cuBLAS 做矩阵乘法（DGEMM），并使用 CUDA kernel 做逐元素后处理；运行时支持 GPU/CPU 切换（通过环境变量 `USE_GPU` 或自动检测）。

本分支目标（Linux）

- 构建系统：CMake (>=3.18) + make
- Fortran 编译器：Intel Fortran (`ifort`)
- CUDA：NVIDIA CUDA Toolkit（包含 `nvcc`、`libcudart`、`libcublas`）
- 可执行：`test_fortran`（在 build 目录生成）

文件

- `CMakeLists.txt` : CMake 配置，构建 CUDA 静态库并把它链接到 Fortran 可执行
- `gpu_lib.cu`     : CUDA + cuBLAS 实现（导出 C 接口）
- `main.f90`       : Fortran 主程序（通过 `ISO_C_BINDING` 调用外部库）
- `Makefile`       : 顶层辅助 make（封装 cmake 配置与构建，并提供 run 目标）
- `LICENSE`, `.gitignore`

快速开始

1. 先决条件
   - CMake >= 3.18
   - NVIDIA CUDA Toolkit（nvcc 在 PATH）
   - Intel Fortran (`ifort`) 可在命令行使用
   - gcc/g++（nvcc 的 host 编译器）

2. 构建（推荐）

   ```bash
   # 在项目根
   make build
   # 等价于：
   # mkdir -p build && cd build
   # cmake -S .. -B . -DCMAKE_Fortran_COMPILER=ifort -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_CUDA_COMPILER=$(which nvcc)
   # cmake --build . --config Release --parallel $(nproc)
   ```

3. 运行（通过 Makefile 的 run 目标）

- 自动检测 GPU（默认）：

   ```bash
   make run
   ```

- 强制 GPU 路径：

   ```bash
   make run MODE=gpu
   # 或
   make run USE_GPU=1
   ```

- 强制 CPU 路径：

   ```bash
   make run MODE=cpu
   # 或
   make run USE_GPU=0
   ```

说明：

- `make run` 在执行时会先检查 `build/test_fortran` 是否存在，不存在会先自动构建。
- `make run` 会在运行时临时把 CUDA 库目录（默认 `/usr/local/cuda-12.2/lib64`）加入 `LD_LIBRARY_PATH`。如果你的 CUDA 库在其它路径，请通过命令行覆盖：

   ```bash
   make run CUDA_LIB_DIR=/path/to/your/cuda/lib64
   ```

- 如果你希望永久性设置库路径，请在 shell 中导出：

   ```bash
   export LD_LIBRARY_PATH=/path/to/your/cuda/lib64:$LD_LIBRARY_PATH
   ```

静默输出说明

- Makefile 的 `run` 目标默认会抑制 shell 命令回显（避免显示很多 if/echo/LD_LIBRARY_PATH 之类的中间命令），但程序本身的输出（例如 `test_fortran` 打印的矩阵结果）仍然会显示。
- 如果你在运行时仍看到命令回显，可以使用静默模式：

   ```bash
   make -s run
   ```

常见问题与排查

- CMake 没找到 CUDAToolkit（或找不到 libcudart / libcublas）：
  - 确保 `nvcc --version` 可用，且在 cmake 时显式指定 CUDA 路径，例如：

  ```bash
  cmake -S . -B build -DCMAKE_Fortran_COMPILER=ifort -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.2/bin/nvcc -DCUDAToolkit_ROOT=/usr/local/cuda-12.2
  ```

- 运行时报错找不到 libcudart.so：
  - 设置 `LD_LIBRARY_PATH` 或把 CUDA lib 目录加入系统库搜索路径（`/etc/ld.so.conf.d/` + `ldconfig`）。
- 如果需要在 CMake 中指定 CUDA 架构以消除警告或生成针对性代码：
  - 在 cmake 调用中添加 `-DCMAKE_CUDA_ARCHITECTURES=86`（例如用于 RTX A6000）。

性能测试建议

- 将 `main.f90` 中的矩阵尺寸 `n` 增大到 512/1024/2048 进行性能比较
- 在 GPU 路径考虑使用 CUDA 流或分块以减少数据传输开销
- 把 CPU 的 naive GEMM 替换为 MKL/OpenBLAS 做更公平对比

许可证

- MIT（详见 LICENSE 文件）

如果你希望我把 README 的其它部分（例如 Windows 构建说明或更详细的性能脚本）也补上，告诉我我会继续补充并提供操作步骤。
