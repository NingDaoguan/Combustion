module advance_module

  use bl_error_module
  use derivative_stencil_module
  use kernels_module
  use multifab_module
  use time_module
  use transport_properties
  use variables_module

  use chemistry_module, only : nspecies

  implicit none

  private
  public advance

contains

  subroutine advance(U, dt, dx, istep)
    type(multifab),    intent(inout) :: U
    double precision,  intent(  out) :: dt
    double precision,  intent(in   ) :: dx(U%dim)
    integer, intent(in) :: istep

    integer          :: ng
    double precision :: courno_proc
    type(layout)     :: la
    type(multifab)   :: Uprime, Unew

    type(bl_prof_timer), save :: bpt_rkstep1, bpt_rkstep2, bpt_rkstep3

    ng = nghost(U)
    la = get_layout(U)

    call multifab_build(Uprime, la, ncons, 0)
    call multifab_build(Unew,   la, ncons, ng)
    call multifab_setval(Unew, 0.d0, .true.)

    ! RK Step 1
    call build(bpt_rkstep1, "rkstep1")   !! vvvvvvvvvvvvvvvvvvvvvvv timer

    courno_proc = 1.0d-50
    call dUdt(U, Uprime, dx, courno=courno_proc)
    call set_dt(dt, courno_proc, istep)
    call update_rk3(Zero,Unew, One,U, dt,Uprime)
    call reset_density(Unew)

    call destroy(bpt_rkstep1)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    ! RK Step 2
    call build(bpt_rkstep2, "rkstep2")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    call dUdt(Unew, Uprime, dx)
    call update_rk3(OneQuarter, Unew, ThreeQuarters, U, OneQuarter*dt, Uprime)
    call reset_density(Unew)
    call destroy(bpt_rkstep2)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    ! RK Step 3
    call build(bpt_rkstep3, "rkstep3")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    call dUdt(Unew, Uprime, dx)
    call update_rk3(OneThird, U, TwoThirds, Unew, TwoThirds*dt, Uprime)
    call reset_density(U)
    call destroy(bpt_rkstep3)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    call destroy(Unew)
    call destroy(Uprime)

    if (contains_nan(U)) then
       call bl_error("U contains nan")
    end if

  end subroutine advance


  !
  ! Compute new time-step size
  !
  subroutine set_dt(dt, courno_proc, istep)

    use probin_module, only : cflfac, fixed_dt, init_shrink, max_dt, max_dt_growth, small_dt, stop_time

    double precision, intent(inout) :: dt
    double precision, intent(in   ) :: courno_proc
    integer,          intent(in   ) :: istep

    double precision :: dtold, courno

    if (fixed_dt > 0.d0) then

       dt = fixed_dt

       if (parallel_IOProcessor()) then
          print*, ""
          print*, "Setting fixed dt =",dt
          print*, ""
       end if

    else

       call parallel_reduce(courno, courno_proc, MPI_MAX)

       dtold = dt
       dt    = cflfac / courno

       if (parallel_IOProcessor()) then
          print*, "CFL: dt =", dt
       end if

       if (istep .eq. 1) then
          dt = dt * init_shrink
          if (parallel_IOProcessor()) then
             print*,'Limited by init_shrink: dt =',dt
          end if
       else
          if (dt .gt. dtold * max_dt_growth) then
             dt = dtold * max_dt_growth
             if (parallel_IOProcessor()) then
                print*,'Limited by dt_growth: dt =',dt
             end if
          end if
       end if

       if(dt .gt. max_dt) then
          if (parallel_IOProcessor()) then
             print*,'Limited by max_dt: dt =',max_dt
          end if
          dt = max_dt
       end if

       if (dt < small_dt) then
          call bl_error("ERROR: timestep < small_dt")
       endif

       if (stop_time > 0.d0) then
          if (time + dt > stop_time) then
             dt = stop_time - time
             if (parallel_IOProcessor()) then
                print*, "Limited by stop_time: dt =",dt
             end if
          end if
       end if
       
       if (parallel_IOProcessor()) then
          print *, ""
       end if

    end if

  end subroutine set_dt



  !
  ! Compute U1 = a U1 + b U2 + c Uprime.
  !
  subroutine update_rk3 (a,U1,b,U2,c,Uprime)

    type(multifab),   intent(in   ) :: U2, Uprime
    type(multifab),   intent(inout) :: U1
    double precision, intent(in   ) :: a, b, c

    integer :: lo(U1%dim), hi(U1%dim), i, j, k, m, n, nc

    double precision, pointer, dimension(:,:,:,:) :: u1p, u2p, upp

    nc = ncomp(U1)

    do n=1,nfabs(U1)
       u1p => dataptr(U1,    n)
       u2p => dataptr(U2,    n)
       upp => dataptr(Uprime,n)

       lo = lwb(get_box(U1,n))
       hi = upb(get_box(U1,n))

       do m = 1, nc
          !$OMP PARALLEL DO PRIVATE(i,j,k)
          do k = lo(3),hi(3)
             do j = lo(2),hi(2)
                do i = lo(1),hi(1)
                   u1p(i,j,k,m) = a * u1p(i,j,k,m) + b * u2p(i,j,k,m) + c * upp(i,j,k,m)
                end do
             end do
          end do
          !$OMP END PARALLEL DO
       end do
    end do

  end subroutine update_rk3


  !
  ! Compute dU/dt given U.
  !
  ! The Courant number (courno) is also computed if passed.
  !
  subroutine dUdt (U, Uprime, dx, courno)
    use derivative_stencil_module, only : stencil, compact, s3d

    type(multifab),   intent(inout) :: U, Uprime
    double precision, intent(in   ) :: dx(U%dim)
    double precision, intent(inout), optional :: courno

    if (stencil .eq. compact) then
       call dUdt_compact(U, Uprime, dx, courno)
    else if (stencil .eq. s3d) then
       call dUdt_S3D(U, Uprime, dx, courno)
    else
       call bl_error("advance: unknown stencil type")
    end if       

  end subroutine dUdt


  !
  ! Compute dU/dt given U using the compact stencil.
  !
  ! The Courant number (courno) is also computed if passed.
  !
  subroutine dUdt_compact (U, Uprime, dx, courno)

    use probin_module, only : overlap_comm_comp

    type(multifab),   intent(inout) :: U, Uprime
    double precision, intent(in   ) :: dx(U%dim)
    double precision, intent(inout), optional :: courno

    type(multifab) :: mu, xi ! viscosity
    type(multifab) :: lam ! partial thermal conductivity
    type(multifab) :: Ddiag ! diagonal components of rho * Y_k * D

    integer ::    lo(U%dim),    hi(U%dim)
    integer :: i,j,k,m,n, ng, dm
    integer :: ng_ctoprim, ng_gettrans

    type(layout)     :: la
    type(multifab)   :: Q, Fhyp, Fdif
    type(mf_fb_data) :: U_fb_data

    double precision, pointer, dimension(:,:,:,:) :: up, fhp, fdp, qp, mup, xip, lamp, Ddp, upp

    type(bl_prof_timer), save :: bpt_ctoprim, bpt_gettrans, bpt_hypterm
    type(bl_prof_timer), save :: bpt_diffterm, bpt_calcU, bpt_chemterm

    call multifab_fill_boundary_nowait(U, U_fb_data)

    call setval(Uprime, ZERO)

    dm = U%dim
    ng = nghost(U)
    la = get_layout(U)

    call multifab_build(Q, la, nprim, ng)

    call multifab_build(Fhyp, la, ncons, 0)
    call multifab_build(Fdif, la, ncons, 0)

    call multifab_build(mu , la, 1, ng)
    call multifab_build(xi , la, 1, ng)
    call multifab_build(lam, la, 1, ng)
    call multifab_build(Ddiag, la, nspecies, ng)

    if (overlap_comm_comp) then
       call multifab_fill_boundary_test(U, U_fb_data)
    else
       call multifab_fill_boundary_finish(U, U_fb_data)
    end if

    if (U_fb_data%rcvd) then
       ng_ctoprim = ng
    else
       ng_ctoprim = 0
    end if

    !
    ! Calculate primitive variables based on U
    !
    call build(bpt_ctoprim, "ctoprim")    !! vvvvvvvvvvvvvvvvvvvvvvv timer
    call ctoprim(U, Q, ng_ctoprim)
    call destroy(bpt_ctoprim)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    if (present(courno)) then
       call compute_courno(Q, dx, courno)
    end if

    if (overlap_comm_comp) then
       call multifab_fill_boundary_test(U, U_fb_data)
    end if

    ! 
    ! chemistry
    !
    call build(bpt_chemterm, "chemterm")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Q)
       qp  => dataptr(Q,n)
       upp => dataptr(Uprime,n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D chemsitry_term is supported")
       else
          call chemterm_3d(lo,hi,ng,qp,upp)
       end if
    end do
    call destroy(bpt_chemterm)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    if (overlap_comm_comp) then
       call multifab_fill_boundary_test(U, U_fb_data)
    end if

    if (U_fb_data%rcvd) then
       ng_gettrans = ng
    else
       ng_gettrans = 0
    end if

    ! Fill ghost cells here for get_transport_properties
    if (ng_gettrans .eq. ng .and. ng_ctoprim .eq. 0) then
       call build(bpt_ctoprim, "ctoprim")    !! vvvvvvvvvvvvvvvvvvvvvvv timer
       call ctoprim(U, Q, ghostcells_only=.true.)
       call destroy(bpt_ctoprim)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer
       ng_ctoprim = ng 
    end if

    !
    ! transport coefficients
    !
    call build(bpt_gettrans, "gettrans")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    call get_transport_properties(Q, mu, xi, lam, Ddiag, ng_gettrans)
    call destroy(bpt_gettrans)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    if (overlap_comm_comp) then
       call multifab_fill_boundary_finish(U, U_fb_data)

       if (ng_ctoprim .eq. 0) then
          call build(bpt_ctoprim, "ctoprim")    !! vvvvvvvvvvvvvvvvvvvvvvv timer
          call ctoprim(U, Q, ghostcells_only=.true.)
          call destroy(bpt_ctoprim)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer
       end if

       if (ng_gettrans .eq. 0) then
          call build(bpt_gettrans, "gettrans")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
          call get_transport_properties(Q, mu, xi, lam, Ddiag, ghostcells_only=.true.)
          call destroy(bpt_gettrans)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer
       end if
    end if

    !
    ! Transport terms
    !
    call build(bpt_diffterm, "diffterm")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Q)
       qp  => dataptr(Q,n)
       fdp => dataptr(Fdif,n)

       mup  => dataptr(mu   , n)
       xip  => dataptr(xi   , n)
       lamp => dataptr(lam  , n)
       Ddp  => dataptr(Ddiag, n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D compact_diffterm is supported")
       else
          call compact_diffterm_3d(lo,hi,ng,dx,qp,fdp,mup,xip,lamp,Ddp)
       end if
    end do
    call destroy(bpt_diffterm)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    !
    ! Hyperbolic terms
    !
    call build(bpt_hypterm, "hypterm")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Fhyp)
       up => dataptr(U,n)
       qp => dataptr(Q,n)
       fhp=> dataptr(Fhyp,n)

       lo = lwb(get_box(Fhyp,n))
       hi = upb(get_box(Fhyp,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D hypterm is supported")
       else
          call hypterm_3d(lo,hi,ng,dx,up,qp,fhp)
       end if
    end do
    call destroy(bpt_hypterm)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    !
    ! Calculate U'
    !
    call build(bpt_calcU, "calcU")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(U)
       fhp => dataptr(Fhyp,  n)
       fdp => dataptr(Fdif,  n)
       upp => dataptr(Uprime,n)

       lo = lwb(get_box(U,n))
       hi = upb(get_box(U,n))

       do m = 1, ncons
          !$OMP PARALLEL DO PRIVATE(i,j,k)
          do k = lo(3),hi(3)
             do j = lo(2),hi(2)
                do i = lo(1),hi(1)
                   upp(i,j,k,m) =  upp(i,j,k,m) + fhp(i,j,k,m) + fdp(i,j,k,m)
                end do
             end do
          end do
          !$OMP END PARALLEL DO
       end do
    end do
    call destroy(bpt_calcU)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    call destroy(Q)

    call destroy(Fhyp)
    call destroy(Fdif)

    call destroy(mu)
    call destroy(xi)
    call destroy(lam)
    call destroy(Ddiag)

  end subroutine dUdt_compact

  subroutine compute_courno(Q, dx, courno)
    type(multifab), intent(in) :: Q
    double precision, intent(in) :: dx(Q%dim)
    double precision, intent(inout) :: courno

    integer :: n, ng, dm, lo(Q%dim), hi(Q%dim)
    double precision, pointer :: qp(:,:,:,:)

    dm = Q%dim
    ng = nghost(Q)

    do n=1,nfabs(Q)
       qp => dataptr(Q,n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D compute_courno is supported")
       else
          call comp_courno_3d(lo,hi,ng,dx,qp,courno)
       end if
    end do
  end subroutine compute_courno


  !
  ! Compute dU/dt given U using the compact stencil.
  !
  ! The Courant number (courno) is also computed if passed.
  !
  subroutine dUdt_S3D (U, Uprime, dx, courno)

    use probin_module, only : overlap_comm_comp

    type(multifab),   intent(inout) :: U, Uprime
    double precision, intent(in   ) :: dx(U%dim)
    double precision, intent(inout), optional :: courno

    integer, parameter :: ng = 4

    type(multifab) :: mu, xi    ! viscosity
    type(multifab) :: lam       ! partial thermal conductivity
    type(multifab) :: Ddiag     ! diagonal components of rho * Y_k * D

    integer ::    lo(U%dim),    hi(U%dim)
    integer :: i,j,k,m,n, dm
    integer :: ndq, ng_ctoprim, ng_gettrans

    type(layout)     :: la
    type(multifab)   :: Q, Fhyp, Fdif
    type(multifab)   :: qx, qy, qz
    type(mf_fb_data) :: U_fb_data, qx_fb_data, qy_fb_data, qz_fb_data

    double precision, pointer, dimension(:,:,:,:) :: up, fhp, fdp, qp, mup, xip, lamp, &
         Ddp, upp, qxp, qyp, qzp

    type(bl_prof_timer), save :: bpt_ctoprim, bpt_gettrans, bpt_hypterm
    type(bl_prof_timer), save :: bpt_diffterm_1, bpt_diffterm_2, bpt_calcU, bpt_chemterm

    call multifab_fill_boundary_nowait(U, U_fb_data)

    call setval(Uprime, ZERO)

    ndq = idX1+nspecies-1

    dm = U%dim
    la = get_layout(U)

    call multifab_build(Q, la, nprim, ng)

    call multifab_build(Fhyp, la, ncons, 0)
    call multifab_build(Fdif, la, ncons, 0)

    call multifab_build(mu , la, 1, ng)
    call multifab_build(xi , la, 1, ng)
    call multifab_build(lam, la, 1, ng)
    call multifab_build(Ddiag, la, nspecies, ng)

    ! these multifabs are used to store first-derivatives
    call multifab_build(qx, la, ndq, ng)
    call multifab_build(qy, la, ndq, ng)
    call multifab_build(qz, la, ndq, ng)

    if (overlap_comm_comp) then
       call multifab_fill_boundary_test(U, U_fb_data)
    else
       call multifab_fill_boundary_finish(U, U_fb_data)
    end if

    if (U_fb_data%rcvd) then
       ng_ctoprim = ng
    else
       ng_ctoprim = 0
    end if

    !
    ! Calculate primitive variables based on U
    !
    call build(bpt_ctoprim, "ctoprim")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    call ctoprim(U, Q, ng_ctoprim)
    call destroy(bpt_ctoprim)            !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    if (present(courno)) then
       call compute_courno(Q, dx, courno)
    end if

    if (overlap_comm_comp) then
       call multifab_fill_boundary_test(U, U_fb_data)
    end if

    ! 
    ! chemistry
    !
    call build(bpt_chemterm, "chemterm")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Q)
       qp  => dataptr(Q,n)
       upp => dataptr(Uprime,n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D chemsitry_term is supported")
       else
          call chemterm_3d(lo,hi,ng,qp,upp)
       end if
    end do
    call destroy(bpt_chemterm)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    if (overlap_comm_comp) then
       call multifab_fill_boundary_test(U, U_fb_data)
    end if

    if (U_fb_data%rcvd) then
       ng_gettrans = ng
    else
       ng_gettrans = 0
    end if

    ! Fill ghost cells here for get_transport_properties
    if (ng_gettrans .eq. ng .and. ng_ctoprim .eq. 0) then
       call build(bpt_ctoprim, "ctoprim")    !! vvvvvvvvvvvvvvvvvvvvvvv timer
       call ctoprim(U, Q, ghostcells_only=.true.)
       call destroy(bpt_ctoprim)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer
       ng_ctoprim = ng 
    end if

    !
    ! transport coefficients
    !
    call build(bpt_gettrans, "gettrans")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    call get_transport_properties(Q, mu, xi, lam, Ddiag, ng_gettrans)
    call destroy(bpt_gettrans)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    if (overlap_comm_comp) then
       call multifab_fill_boundary_finish(U, U_fb_data)

       if (ng_ctoprim .eq. 0) then
          call build(bpt_ctoprim, "ctoprim")    !! vvvvvvvvvvvvvvvvvvvvvvv timer
          call ctoprim(U, Q, ghostcells_only=.true.)
          call destroy(bpt_ctoprim)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer
       end if

       if (ng_gettrans .eq. 0) then
          call build(bpt_gettrans, "gettrans")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
          call get_transport_properties(Q, mu, xi, lam, Ddiag, ghostcells_only=.true.)
          call destroy(bpt_gettrans)             !! ^^^^^^^^^^^^^^^^^^^^^^^ timer
       end if
    end if

    !
    ! Transport terms: first derivative terms 
    !
    call build(bpt_diffterm_1, "diffterm_1")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Q)
       qp  => dataptr(Q,n)
       fdp => dataptr(Fdif,n)

       mup  => dataptr(mu, n)
       xip  => dataptr(xi, n)

       qxp => dataptr(qx, n)
       qyp => dataptr(qy, n)
       qzp => dataptr(qz, n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D S3D_diffterm is supported")
       else
          call S3D_diffterm_1(lo,hi,ng,ndq,dx,qp,fdp,mup,xip,qxp,qyp,qzp)
       end if
    end do
    call destroy(bpt_diffterm_1)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    qx_fb_data%tag = 1001
    call multifab_fill_boundary_nowait(qx, qx_fb_data, idim=1)
    qy_fb_data%tag = 1002
    call multifab_fill_boundary_nowait(qy, qy_fb_data, idim=2)
    qz_fb_data%tag = 1003
    call multifab_fill_boundary_nowait(qz, qz_fb_data, idim=3)

    !
    ! Hyperbolic terms
    !
    call build(bpt_hypterm, "hypterm")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Fhyp)
       up => dataptr(U,n)
       qp => dataptr(Q,n)
       fhp=> dataptr(Fhyp,n)

       lo = lwb(get_box(Fhyp,n))
       hi = upb(get_box(Fhyp,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D hypterm is supported")
       else
          call hypterm_3d(lo,hi,ng,dx,up,qp,fhp)
       end if
    end do
    call destroy(bpt_hypterm)            !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    call multifab_fill_boundary_finish(qx, qx_fb_data, idim=1)
    call multifab_fill_boundary_finish(qy, qy_fb_data, idim=2)
    call multifab_fill_boundary_finish(qz, qz_fb_data, idim=3)

    !
    ! Transport terms: d(a du/dx)/dx terms
    !
    call build(bpt_diffterm_2, "diffterm_2")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(Q)
       qp  => dataptr(Q,n)
       fdp => dataptr(Fdif,n)

       mup  => dataptr(mu   , n)
       xip  => dataptr(xi   , n)
       lamp => dataptr(lam  , n)
       Ddp  => dataptr(Ddiag, n)

       qxp => dataptr(qx, n)
       qyp => dataptr(qy, n)
       qzp => dataptr(qz, n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dm .ne. 3) then
          call bl_error("Only 3D S3D_diffterm is supported")
       else
          call S3D_diffterm_2(lo,hi,ng,ndq,dx,qp,fdp,mup,xip,lamp,Ddp,qxp,qyp,qzp)
       end if
    end do
    call destroy(bpt_diffterm_2)              !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    !
    ! Calculate U'
    !
    call build(bpt_calcU, "calcU")   !! vvvvvvvvvvvvvvvvvvvvvvv timer
    do n=1,nfabs(U)
       fhp => dataptr(Fhyp,  n)
       fdp => dataptr(Fdif,  n)
       upp => dataptr(Uprime,n)

       lo = lwb(get_box(U,n))
       hi = upb(get_box(U,n))

       do m = 1, ncons
          !$OMP PARALLEL DO PRIVATE(i,j,k)
          do k = lo(3),hi(3)
             do j = lo(2),hi(2)
                do i = lo(1),hi(1)
                   upp(i,j,k,m) = upp(i,j,k,m) + fhp(i,j,k,m) + fdp(i,j,k,m)
                end do
             end do
          end do
          !$OMP END PARALLEL DO
       end do
    end do
    call destroy(bpt_calcU)                !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

    call destroy(Q)

    call destroy(Fhyp)
    call destroy(Fdif)

    call destroy(mu)
    call destroy(xi)
    call destroy(lam)
    call destroy(Ddiag)

    call destroy(qx)
    call destroy(qy)
    call destroy(qz)

  end subroutine dUdt_S3D

end module advance_module
