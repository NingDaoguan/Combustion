      subroutine update_vel(vel_old,vel_new,gp,rhohalf,
     &                      macvel,veledge,alpha,beta,
     &                      Rhs,dx,dt,be_cn_theta)
      implicit none
      include 'spec.h'
      real*8 vel_old(-2:nx+1)
      real*8 vel_new(-2:nx+1)
      real*8      gp(-1:nx)
      real*8 rhohalf(0 :nx-1)
      real*8  macvel(0 :nx)
      real*8 veledge(0 :nx)
      real*8   alpha(0 :nx-1)
      real*8    beta(-1:nx  )
      real*8     Rhs(0 :nx-1)
      real*8 dx,dt,be_cn_theta
      
! local
      real*8  visc(-1:nx)
      real*8  aofs,visc_term
      integer i


      call get_vel_visc_terms(vel_old,beta,visc,dx)

c     rho.DU/Dt + G(pi) = D(tau), here D(tau) = d/dx ( a . du/dx ), a=4.mu/3
      do i = 0,nx-1
         visc_term = dt*(1.d0 - be_cn_theta)*visc(i)

         aofs = ( (macvel(i+1)*veledge(i+1) - macvel(i)*veledge(i))  -
     $        0.5d0*(macvel(i+1)-macvel(i))*(veledge(i)+veledge(i+1)) )/dx

         vel_new(i) = vel_old(i) - dt * ( aofs + gp(i)/rhohalf(i) )
         alpha(i) = rhohalf(i)
         Rhs(i) = vel_new(i)*alpha(i) + visc_term
      enddo

      call set_bc_v(vel_new)

      end
      
