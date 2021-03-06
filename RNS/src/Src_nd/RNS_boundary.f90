module RNS_boundary_module

  implicit none

  double precision, save :: Twall = -1.d0

contains

  subroutine get_hyper_bc_flag(dir,lo,hi,domain_lo,domain_hi,dx,flag)

    use prob_params_module, only : physbc_lo,Symmetry,SlipWall,NoSlipWall

    integer, intent(in) :: dir, lo(:), hi(:), domain_lo(:), domain_hi(:)
    double precision, intent(in) :: dx(:)
    integer, intent(out) :: flag(2)

    ! see riemann.f90 for the effect of flag
    flag = 1

  end subroutine get_hyper_bc_flag

end module RNS_boundary_module

