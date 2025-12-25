#!/usr/bin/env bash
# Simple, robust performance test script for fortran-cuda-cublas-example
# Usage:
#   ./perf_simple.sh            # default sizes 256 512 1024, repeats 3
#   ./perf_simple.sh 128 256    # test sizes 128 and 256
#   REPEATS=5 ./perf_simple.sh  # change repeats
#
set -euo pipefail

BINARY=build/test_fortran
REPEATS=${REPEATS:-3}
CUDA_LIB_DIR=${CUDA_LIB_DIR:-/usr/local/cuda-12.2/lib64}

# Determine sizes: use script args if provided, otherwise default sizes
if [ "$#" -gt 0 ]; then
  SIZES=("$@")
else
  SIZES=(1024 2048 4096)
fi

# ensure binary exists (build if needed)
if [ ! -x "$BINARY" ]; then
  echo "Binary not found: $BINARY"
  echo "Running: make build"
  make build
fi

echo "Simple performance test"
echo "Binary: $BINARY"
echo "CUDA lib dir: $CUDA_LIB_DIR"
echo "Repeats per size per mode: $REPEATS"
echo

# measure: run command (redirecting its stdout/stderr) and print elapsed seconds
measure() {
  local start end elapsed
  start=$(date +%s.%N)
  # run the command, redirecting both stdout and stderr to /dev/null
  "$@" > /dev/null 2>&1
  end=$(date +%s.%N)
  # use awk for subtraction (more portable than bc in some minimal systems)
  elapsed=$(awk -v e="$end" -v s="$start" 'BEGIN{printf "%.6f", e - s}')
  printf "%s" "$elapsed"
}

# print CSV header
printf "size,mode,iter,seconds\n"

for n in "${SIZES[@]}"; do
  # validate n is an integer > 0
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -le 0 ]; then
    echo "Skipping invalid size: $n" >&2
    continue
  fi

  for mode in gpu cpu; do
    for ((i=1; i<=REPEATS; i++)); do
      if [ "$mode" = "gpu" ]; then
        t=$(measure env LD_LIBRARY_PATH="$CUDA_LIB_DIR:${LD_LIBRARY_PATH:-}" USE_GPU=1 "$BINARY" "$n")
      else
        t=$(measure env LD_LIBRARY_PATH="$CUDA_LIB_DIR:${LD_LIBRARY_PATH:-}" USE_GPU=0 "$BINARY" "$n")
      fi
      printf "%s,%s,%d,%s\n" "$n" "$mode" "$i" "$t"
    done
  done
done

echo
echo "Done."