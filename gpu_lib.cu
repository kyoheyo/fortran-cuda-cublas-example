/*
  gpu_lib.cu
  CUDA + cuBLAS implementation for Linux (export C interface).

  - GPU path: use cuBLAS Dgemm for matrix multiply and a CUDA kernel for postprocessing
  - CPU fallback: naive gemm + host-side postprocessing

  Compile via CMake (CUDAToolkit) or:
    nvcc -O3 -Xcompiler -fPIC -c gpu_lib.cu -o gpu_lib.o
*/
#include <cuda_runtime.h>
#include <cublas_v2.h>
#include <stdio.h>
#include <math.h>

static inline void cuda_check(cudaError_t e, const char* msg) {
    if (e != cudaSuccess) {
        fprintf(stderr, "CUDA Error (%s): %s\n", msg, cudaGetErrorString(e));
    }
}
static inline void cublas_check(cublasStatus_t s, const char* msg) {
    if (s != CUBLAS_STATUS_SUCCESS) {
        fprintf(stderr, "cuBLAS Error (%s): %d\n", msg, (int)s);
    }
}

// 确保函数名无 C++ 名称修饰，能被 Fortran 的 bind(C,name="...") 直接链接
extern "C" {

// 返回1表示发现可用 GPU，0表示没有或出错
int gpu_available() {
    int count = 0;
    cudaError_t err = cudaGetDeviceCount(&count);
    if (err != cudaSuccess || count <= 0) return 0;
    return 1;
}

// postproc kernel: C = C*2 + sqrt(A)
__global__ void postproc_kernel(double* C, const double* A, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int total = n * n;
    if (idx < total) {
        C[idx] = C[idx] * 2.0 + sqrt(A[idx]);
    }
}

// CPU fallback: naive GEMM (column-major)
void gemm_cpu_naive(const double* A, const double* B, double* C, int n) {
    int i,j,k;
    for (j = 0; j < n; ++j)
        for (i = 0; i < n; ++i)
            C[j*n + i] = 0.0;
    for (k = 0; k < n; ++k) {
        for (j = 0; j < n; ++j) {
            double b_kj = B[j*n + k];
            for (i = 0; i < n; ++i) {
                C[j*n + i] += A[k*n + i] * b_kj;
            }
        }
    }
}


// Return codes
#define GPU_SUCCESS 0
#define CPU_FALLBACK 1
#define INVALID_ARGS -1

// compute_mat: A,B,C are column-major n x n. use_gpu: 0/1.
// Returns status code as described above.
int compute_mat(const double* A, const double* B, double* C, int n, int use_gpu) {
    if (!A || !B || !C || n <= 0) {
        return INVALID_ARGS;
    }

    if (use_gpu && gpu_available()) {
        double *d_A = nullptr, *d_B = nullptr, *d_C = nullptr;
        size_t bytes = sizeof(double) * (size_t)n * (size_t)n;
        cudaError_t cerr;
        cublasStatus_t cstat;
        cublasHandle_t handle = nullptr;

        // 每步分配空间都检查 cuda 返回值，若失败则释放已分配资源并退回 CPU 实现
        cerr = cudaMalloc((void**)&d_A, bytes);
        if (cerr != cudaSuccess) { cuda_check(cerr, "cudaMalloc d_A"); gemm_cpu_naive(A,B,C,n); return CPU_FALLBACK; }
        cerr = cudaMalloc((void**)&d_B, bytes);
        if (cerr != cudaSuccess) { cudaFree(d_A); cuda_check(cerr, "cudaMalloc d_B"); gemm_cpu_naive(A,B,C,n); return CPU_FALLBACK; }
        cerr = cudaMalloc((void**)&d_C, bytes);
        if (cerr != cudaSuccess) { cudaFree(d_A); cudaFree(d_B); cuda_check(cerr, "cudaMalloc d_C"); gemm_cpu_naive(A,B,C,n); return CPU_FALLBACK; }

        // 主机 -> 设备(显卡) 拷贝
        // 若失败同样回退 CPU 实现
        cerr = cudaMemcpy(d_A, A, bytes, cudaMemcpyHostToDevice);
        if (cerr != cudaSuccess) { cudaFree(d_A); cudaFree(d_B); cudaFree(d_C); cuda_check(cerr, "cudaMemcpy d_A"); gemm_cpu_naive(A,B,C,n); return CPU_FALLBACK; }
        cerr = cudaMemcpy(d_B, B, bytes, cudaMemcpyHostToDevice);
        if (cerr != cudaSuccess) { cudaFree(d_A); cudaFree(d_B); cudaFree(d_C); cuda_check(cerr, "cudaMemcpy d_B"); gemm_cpu_naive(A,B,C,n); return CPU_FALLBACK; }

        // cuBLAS handle 创建
        cstat = cublasCreate(&handle);
        if (cstat != CUBLAS_STATUS_SUCCESS) {
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            cublas_check(cstat, "cublasCreate");
            gemm_cpu_naive(A,B,C,n);
            return CPU_FALLBACK;
        }

        // alpha/beta 是指向 host 或 device 上的数据的指针
        // 当前用的是 host double variables 的地址
        const double alpha = 1.0;
        const double beta = 0.0;
        // cuBLAS uses column-major by default; Fortran arrays are column-major.
        cstat = cublasDgemm(handle,
                            CUBLAS_OP_N, CUBLAS_OP_N,
                            n, n, n,
                            &alpha,
                            d_A, n,
                            d_B, n,
                            &beta,
                            d_C, n);
        if (cstat != CUBLAS_STATUS_SUCCESS) {
            cublas_check(cstat, "cublasDgemm");
            cublasDestroy(handle);
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            gemm_cpu_naive(A,B,C,n);
            return CPU_FALLBACK;
        }

        int total = n * n;
        int block = 256;
        int grid = (total + block - 1) / block;
        // 每个线程处理一个元素：C[idx] = C[idx]*2 + sqrt(A[idx])。
        postproc_kernel<<<grid, block>>>(d_C, d_A, n);
        cerr = cudaGetLastError();
        if (cerr != cudaSuccess) {
            cuda_check(cerr, "postproc kernel launch");
            cublasDestroy(handle);
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            gemm_cpu_naive(A,B,C,n);
            return CPU_FALLBACK;
        }

        cerr = cudaMemcpy(C, d_C, bytes, cudaMemcpyDeviceToHost);
        if (cerr != cudaSuccess) {
            cuda_check(cerr, "cudaMemcpy d_C -> host");
            cublasDestroy(handle);
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            gemm_cpu_naive(A,B,C,n);
            return CPU_FALLBACK;
        }
        
        // 销毁 cublas handle（cublasDestroy）
        cublasDestroy(handle);
        // 释放 d_A,d_B,d_C（cudaFree）
        cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
        return GPU_SUCCESS;
    } else {
        // CPU path
        gemm_cpu_naive(A,B,C,n);
        int total = n * n;
        for (int idx = 0; idx < total; ++idx) {
            C[idx] = C[idx] * 2.0 + sqrt(A[idx]);
        }
        return CPU_FALLBACK;
    }
}

} // extern "C"