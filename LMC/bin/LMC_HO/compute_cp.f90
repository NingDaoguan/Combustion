subroutine compute_cp(cp, T, Y)
   implicit none
   include 'spec.h'
   
   double precision, intent(out) :: cp
   double precision, intent(in ) :: T, Y(Nspec)
   
   double precision :: rwrk
   integer :: iwrk
   
   call CKCPBS(T, Y, iwrk, rwrk, cp)
end subroutine compute_cp
