module eos_module 

  implicit none

  double precision, parameter :: Ru = 8.31451d+07
  double precision, parameter :: mu = 28.97d0
  double precision, parameter :: R_mu = Ru/mu

  double precision, save, public :: gamma_const = 1.4d0

  double precision, save, private :: smalld = 1.d-50
  double precision, save, private :: smallt = 1.d-50
  double precision, save, private :: smallp = 1.d-50
  double precision, save, private :: smallc = 1.d-50

  double precision, save, private :: cv = Ru/(mu*0.4d0)

  logical, save, private :: initialized = .false.

contains

  subroutine eos_init(small_temp, small_dens, gamma_in)

    implicit none
 
    double precision, intent(in), optional :: small_temp
    double precision, intent(in), optional :: small_dens
    double precision, intent(in), optional :: gamma_in
    
    if (present(small_temp)) then
       if (small_temp > 0.d0) then
          smallt = small_temp
       end if
    endif
 
    if (present(small_dens)) then
       if (small_dens > 0.d0) then
          smalld = small_dens
       end if
    endif
 
    if (present(gamma_in)) then
       gamma_const = gamma_in
       cv = Ru/(mu*(gamma_const-1.d0))
    end if

    initialized = .true.
    
  end subroutine eos_init

  subroutine eos_get_small_temp(small_temp_out)
    
    double precision, intent(out) :: small_temp_out
 
    small_temp_out = smallt
 
  end subroutine eos_get_small_temp
 
  subroutine eos_get_small_dens(small_dens_out)
    
    double precision, intent(out) :: small_dens_out
    
    small_dens_out = smalld
    
  end subroutine eos_get_small_dens


  subroutine eos_get_c(c,rho,T,Y,pt_index)
    double precision, intent(out) :: c
    double precision, intent(in) :: rho, T, Y(2)
    integer, optional, intent(in) :: pt_index(:)
    double precision :: p
    p = rho*Ru*T/mu
    p = max(p, smallp)
    c = sqrt(gamma_const*p/rho)
  end subroutine eos_get_c


  subroutine eos_get_T(T, e, Y, pt_index)
    double precision, intent(out) :: T
    double precision, intent(in ) :: e, Y(2)
    integer, optional, intent(in) :: pt_index(:)
    T = e/cv
  end subroutine eos_get_T


  subroutine eos_given_RTY(e, p, c, dpdr, dpde, rho, T, Y, pt_index)
    double precision, intent(out) :: e, p, c, dpdr(2), dpde
    double precision, intent(in ) :: rho, T, Y(2)
    integer, optional, intent(in) :: pt_index(:)
    e = cv*T
    p = rho*R_mu*T
    p = max(p, smallp)
    c = sqrt(gamma_const*p/rho)
    dpdr(1) = (gamma_const-1.d0)*e
    dpdr(2) = (gamma_const-1.d0)*e
    dpde    = (gamma_const-1.d0)*rho
  end subroutine eos_given_RTY


  subroutine eos_given_ReY(p, c, T, dpdr, dpde, rho, e, Y, pt_index)
    double precision, intent(out) :: p, c, T, dpdr(2), dpde
    double precision, intent(in ) :: rho, e, Y(2)
    integer, optional, intent(in) :: pt_index(:)
    T = e/cv
    p = rho*R_mu*T
    p = max(p, smallp)
    c = sqrt(gamma_const*p/rho)
    dpdr(1) = (gamma_const-1.d0)*e
    dpdr(2) = (gamma_const-1.d0)*e
    dpde    = (gamma_const-1.d0)*rho
  end subroutine eos_given_ReY

end module eos_module
