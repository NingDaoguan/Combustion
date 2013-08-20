subroutine cd_initchem(len_en, len_sn, ne, ns)
  use chemistry_module
  implicit none
  integer, intent(out) :: len_en, len_sn, ne, ns
  call chemistry_init()
  len_en = L_elem_name
  len_sn = L_spec_name
  ne = nelements
  ns = nspecies
end subroutine cd_initchem


subroutine cd_closechem()
  use chemistry_module
  implicit none
  call chemistry_close()
end subroutine cd_closechem


subroutine cd_getelemname(ielem, lname, name)
  use chemistry_module
  implicit none
  integer, intent(in)  :: ielem
  integer, intent(out) :: lname
  integer, intent(inout) :: name(L_elem_name)

  integer :: i

  lname = len_trim(elem_names(ielem))

  do i = 1, lname
     name(i) = ichar(elem_names(ielem)(i:i))
  end do
end subroutine cd_getelemname


subroutine cd_getspecname(ispec, lname, name)
  use chemistry_module
  implicit none
  integer, intent(in)  :: ispec
  integer, intent(out) :: lname
  integer, intent(inout) :: name(L_spec_name)

  integer :: i

  lname = len_trim(spec_names(ispec))

  do i = 1, lname
     name(i) = ichar(spec_names(ispec)(i:i))
  end do
end subroutine cd_getspecname


subroutine cd_initvode(neq_in, itol_in, rtol_in, atol_in, order_in, maxstep_in, &
     use_ajac_in, save_ajac_in, always_new_j_in, stiff_in, v_in)
  use vode_module, only : verbose, neq, itol, rtol, atol, order, maxstep, &
       use_ajac, save_ajac, always_new_j, stiff, vode_init
  implicit none
  integer, intent(in) :: neq_in, itol_in, order_in, maxstep_in, &
       use_ajac_in, save_ajac_in, always_new_j_in, stiff_in, v_in
  double precision, intent(in) :: rtol_in, atol_in
  verbose = v_in
  itol = itol_in
  rtol = rtol_in
  atol = atol_in
  order = order_in
  maxstep = maxstep_in
  if (use_ajac_in .ne. 0) then
     use_ajac = .true.
  else
     use_ajac = .false.
  end if
  if (save_ajac_in .ne. 0) then
     save_ajac = .true.
  else
     save_ajac = .false.
  end if
  if (always_new_j_in .ne. 0) then
     always_new_j = .true.
  else
     always_new_j = .false.
  end if
  if (stiff_in .ne. 0) then
     stiff = .true.
  else
     stiff = .false.
  end if
  call vode_init(neq_in)
end subroutine cd_initvode


subroutine cd_closevode()
  use vode_module, only : vode_close
  call vode_close()
end subroutine cd_closevode


subroutine cd_initeglib(use_bulk_visc_in)
  use egz_module
  implicit none
  integer, intent(in) :: use_bulk_visc_in
  call egz_init(use_bulk_visc_in)
end subroutine cd_initeglib


subroutine cd_closeeglib()
  use egz_module
  implicit none
  call egz_close()
end subroutine cd_closeeglib

