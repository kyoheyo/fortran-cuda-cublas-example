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

extern "C" {

// Return 1 if GPU available, 0 otherwise
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

// compute_mat: A,B,C are column-major n x n. use_gpu: 0/1.
void compute_mat(const double* A, const double* B, double* C, int n, int use_gpu) {
    if (use_gpu && gpu_available()) {
        double *d_A = nullptr, *d_B = nullptr, *d_C = nullptr;
        size_t bytes = sizeof(double) * (size_t)n * (size_t)n;
        cudaError_t cerr;
        cublasStatus_t cstat;
        cublasHandle_t handle = nullptr;

        cerr = cudaMalloc((void**)&d_A, bytes);
        if (cerr != cudaSuccess) { cuda_check(cerr, "cudaMalloc d_A"); gemm_cpu_naive(A,B,C,n); return; }
        cerr = cudaMalloc((void**)&d_B, bytes);
        if (cerr != cudaSuccess) { cudaFree(d_A); cuda_check(cerr, "cudaMalloc d_B"); gemm_cpu_naive(A,B,C,n); return; }
        cerr = cudaMalloc((void**)&d_C, bytes);
        if (cerr != cudaSuccess) { cudaFree(d_A); cudaFree(d_B); cuda_check(cerr, "cudaMalloc d_C"); gemm_cpu_naive(A,B,C,n); return; }

        cerr = cudaMemcpy(d_A, A, bytes, cudaMemcpyHostToDevice);
        if (cerr != cudaSuccess) { cudaFree(d_A); cudaFree(d_B); cudaFree(d_C); cuda_check(cerr, "cudaMemcpy d_A"); gemm_cpu_naive(A,B,C,n); return; }
        cerr = cudaMemcpy(d_B, B, bytes, cudaMemcpyHostToDevice);
        if (cerr != cudaSuccess) { cudaFree(d_A); cudaFree(d_B); cudaFree(d_C); cuda_check(cerr, "cudaMemcpy d_B"); gemm_cpu_naive(A,B,C,n); return; }

        cstat = cublasCreate(&handle);
        if (cstat != CUBLAS_STATUS_SUCCESS) {
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            cublas_check(cstat, "cublasCreate");
            gemm_cpu_naive(A,B,C,n);
            return;
        }

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
            return;
        }

        int total = n * n;
        int block = 256;
        int grid = (total + block - 1) / block;
        postproc_kernel<<<grid, block>>>(d_C, d_A, n);
        cerr = cudaGetLastError();
        if (cerr != cudaSuccess) {
            cuda_check(cerr, "postproc kernel launch");
            cublasDestroy(handle);
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            gemm_cpu_naive(A,B,C,n);
            return;
        }

        cerr = cudaMemcpy(C, d_C, bytes, cudaMemcpyDeviceToHost);
        if (cerr != cudaSuccess) {
            cuda_check(cerr, "cudaMemcpy d_C -> host");
            cublasDestroy(handle);
            cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
            gemm_cpu_naive(A,B,C,n);
            return;
        }

        cublasDestroy(handle);
        cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
    } else {
        gemm_cpu_naive(A,B,C,n);
        int total = n * n;
        for (int idx = 0; idx < total; ++idx) {
            C[idx] = C[idx] * 2.0 + sqrt(A[idx]);
        }
    }
}

} // extern "C"