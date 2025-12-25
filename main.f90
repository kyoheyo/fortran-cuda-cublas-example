! main.f90
! Fortran (ifort) main program. USE_GPU env var controls backend:
!   USE_GPU=1 -> try GPU (fallback to CPU if GPU calls fail)
!   USE_GPU=0 -> force CPU
!   not set   -> auto-detect via gpu_available()
program test_cublas_switch
  use iso_c_binding
  implicit none

  interface
    function gpu_available() bind(C, name="gpu_available")
      import :: c_int
      integer(c_int) :: gpu_available
    end function

    subroutine compute_mat(a_ptr, b_ptr, c_ptr, n, use_gpu) bind(C, name="compute_mat")
      import :: c_ptr, c_int
      type(c_ptr), value :: a_ptr, b_ptr, c_ptr
      integer(c_int), value :: n
      integer(c_int), value :: use_gpu
    end subroutine
  end interface

  integer :: n, i, j
  real(c_double), allocatable :: A(:,:), B(:,:), C(:,:)
  character(len=16) :: env
  integer :: env_len
  integer(c_int) :: use_gpu_flag
  integer(c_int) :: detected

  n = 4   ! small for demonstration; increase for performance tests
  allocate(A(n,n), B(n,n), C(n,n))

  ! initialize
  do j = 1, n
    do i = 1, n
      A(i,j) = real(i, kind=c_double) + 0.1d0 * real(j, kind=c_double)
      B(i,j) = 1.0d0 + 0.5d0 * real(i, kind=c_double) + 0.2d0 * real(j, kind=c_double)
      C(i,j) = 0.0d0
    end do
  end do

  call get_environment_variable("USE_GPU", value=env, length=env_len)
  if (env_len > 0) then
    if (trim(env) == "1") then
      use_gpu_flag = 1
    else
      use_gpu_flag = 0
    end if
  else
    detected = gpu_available()
    if (detected /= 0) then
      use_gpu_flag = 1
    else
      use_gpu_flag = 0
    end if
  end if

  if (use_gpu_flag /= 0) then
    print *, "Using GPU path (or attempting to)."
  else
    print *, "Using CPU path."
  end if

  ! call C/CUDA library (pass address of first element)
  call compute_mat(c_loc(A(1,1)), c_loc(B(1,1)), c_loc(C(1,1)), n, use_gpu_flag)

  print *, "Result matrix C (after C = A*B ; then C = C*2 + sqrt(A) )"
  do j = 1, n
    write (*,'(A)', advance='no') "row " // trim(adjustl(to_string(j))) // ": "
    write (*, '(F12.6)', advance='no') ( C(i,j), i=1,n )
    write (*,*)
  end do

  deallocate(A,B,C)
contains
  function to_string(x) result(s)
    integer, intent(in) :: x
    character(len=16) :: s
    write(s, '(I0)') x
  end function
end program