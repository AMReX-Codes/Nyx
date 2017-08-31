
subroutine f_rhs(num_eq, time, e_in, energy, rpar, ipar)

      use amrex_fort_module, only : rt => amrex_real
      use fundamental_constants_module, only: e_to_cgs, density_to_cgs, & 
                                              heat_from_cgs
      use eos_module, only: iterate_ne
      use atomic_rates_module, ONLY: TCOOLMIN, TCOOLMAX, NCOOLTAB, deltaT, &
                                     MPROTON, XHYDROGEN, &
                                     AlphaHp, AlphaHep, AlphaHepp, Alphad, &
                                     GammaeH0, GammaeHe0, GammaeHep, &
                                     BetaH0, BetaHe0, BetaHep, Betaff1, Betaff4, &
                                     RecHp, RecHep, RecHepp, &
                                     eh0, ehe0, ehep

      use vode_aux_module       , only: z_vode, rho_vode, T_vode, ne_vode, i_vode, j_vode, k_vode

      integer, intent(in)             :: num_eq, ipar
      real(rt), intent(inout) :: e_in(num_eq)
      real(rt), intent(in   ) :: time
      real(rt), intent(in   ) :: rpar
      real(rt), intent(  out) :: energy

      real(rt), parameter :: compt_c = 1.01765467d-37, T_cmb = 2.725d0

      real(rt) :: logT, tmp, fhi, flo
      real(rt) :: ahp, ahep, ahepp, ad, geh0, gehe0, gehep
      real(rt) :: bh0, bhe0, bhep, bff1, bff4, rhp, rhep, rhepp
      real(rt) :: lambda_c, lambda_ff, lambda, heat
      real(rt) :: rho, U, a
      real(rt) :: nh, nh0, nhp, nhe0, nhep, nhepp
      integer :: j

      if (e_in(1) .lt. 0.d0) &
         e_in(1) = tiny(e_in(1))

     ! Converts from code units to CGS
      rho = rho_vode * density_to_cgs * (1.0d0+z_vode)**3
        U = e_in(1) * e_to_cgs
      nh  = rho*XHYDROGEN/MPROTON

      if (time .gt. 1) then
         print *,'TIME INTO F_RHS ',time
         print *,'AT              ',i_vode,j_vode,k_vode
         call bl_pd_abort("TOO BIG TIME IN F_RHS")
      end if

      ! Get gas temperature and individual ionization species
      call iterate_ne(z_vode, U, T_vode, nh, ne_vode, nh0, nhp, nhe0, nhep, nhepp)

      ! Convert species to CGS units: 
      ne_vode = nh * ne_vode
      nh0   = nh * nh0
      nhp   = nh * nhp
      nhe0  = nh * nhe0
      nhep  = nh * nhep
      nhepp = nh * nhepp

      logT = dlog10(T_vode)
      if (logT .ge. TCOOLMAX) then ! Only free-free and Compton cooling are relevant
         lambda_ff = 1.42d-27 * dsqrt(T_vode) * (1.1d0 + 0.34d0*dexp(-(5.5d0 - logT)**2 / 3.0d0)) &
                              * (nhp + 4.0d0*nhepp)*ne_vode
         lambda_c  = compt_c*T_cmb**4 * ne_vode * (T_vode - T_cmb*(1.0d0+z_vode))*(1.0d0 + z_vode)**4

         energy  = (-lambda_ff -lambda_c) * heat_from_cgs/(1.0d0+z_vode)**4

         ! Convert to the actual term to be used in e_out = e_in + dt*energy
         energy  = energy / rho_vode * (1.0d0+z_vode)
         ne_vode = ne_vode / nh
         return
      endif

      ! Temperature floor
      if (logT .le. TCOOLMIN) logT = TCOOLMIN + 0.5d0*deltaT

      ! Interpolate rates
      tmp = (logT-TCOOLMIN)/deltaT
      j = int(tmp)
      fhi = tmp - j
      flo = 1.0d0 - fhi
      j = j + 1 ! F90 arrays start with 1

      ahp   = flo*AlphaHp  (j) + fhi*AlphaHp  (j+1)
      ahep  = flo*AlphaHep (j) + fhi*AlphaHep (j+1)
      ahepp = flo*AlphaHepp(j) + fhi*AlphaHepp(j+1)
      ad    = flo*Alphad   (j) + fhi*Alphad   (j+1)
      geh0  = flo*GammaeH0 (j) + fhi*GammaeH0 (j+1)
      gehe0 = flo*GammaeHe0(j) + fhi*GammaeHe0(j+1)
      gehep = flo*GammaeHep(j) + fhi*GammaeHep(j+1)
      bh0   = flo*BetaH0   (j) + fhi*BetaH0   (j+1)
      bhe0  = flo*BetaHe0  (j) + fhi*BetaHe0  (j+1)
      bhep  = flo*BetaHep  (j) + fhi*BetaHep  (j+1)
      bff1  = flo*Betaff1  (j) + fhi*Betaff1  (j+1)
      bff4  = flo*Betaff4  (j) + fhi*Betaff4  (j+1)
      rhp   = flo*RecHp    (j) + fhi*RecHp    (j+1)
      rhep  = flo*RecHep   (j) + fhi*RecHep   (j+1)
      rhepp = flo*RecHepp  (j) + fhi*RecHepp  (j+1)

      ! Cooling: 
      lambda = ( bh0*nh0 + bhe0*nhe0 + bhep*nhep + &
                 rhp*nhp + rhep*nhep + rhepp*nhepp + &
                 bff1*(nhp+nhep) + bff4*nhepp ) * ne_vode

      lambda_c = compt_c*T_cmb**4*ne_vode*(T_vode - T_cmb*(1.0d0+z_vode))*(1.0d0 + z_vode)**4   ! Compton cooling
      lambda = lambda + lambda_c

      ! Heating terms
      heat = nh0*eh0 + nhe0*ehe0 + nhep*ehep

      ! Convert back to code units
      ne_vode     = ne_vode / nh
      energy = (heat - lambda)*heat_from_cgs/(1.0d0+z_vode)**4

      ! Convert to the actual term to be used in e_out = e_in + dt*energy
      a = 1.d0 / (1.d0 + z_vode)
      energy = energy / rho_vode / a

end subroutine f_rhs

subroutine f_rhs_vec(time, e_in, energy)

      use amrex_fort_module, only : rt => amrex_real
      use fundamental_constants_module, only: e_to_cgs, density_to_cgs, & 
                                              heat_from_cgs
      use eos_module, only: iterate_ne_vec
      use atomic_rates_module, ONLY: TCOOLMIN, TCOOLMAX, NCOOLTAB, deltaT, &
                                     MPROTON, XHYDROGEN, &
                                     AlphaHp, AlphaHep, AlphaHepp, Alphad, &
                                     GammaeH0, GammaeHe0, GammaeHep, &
                                     BetaH0, BetaHe0, BetaHep, Betaff1, Betaff4, &
                                     RecHp, RecHep, RecHepp, &
                                     eh0, ehe0, ehep

      use vode_aux_module       , only: T_vode_vec, ne_vode_vec, rho_vode_vec, z_vode
      use misc_params, only: simd_width

      implicit none

      real(rt),                        intent(in   ) :: time
      real(rt), dimension(simd_width), intent(inout) :: e_in
      real(rt), dimension(simd_width), intent(  out) :: energy

      real(rt), parameter :: compt_c = 1.01765467d-37, T_cmb = 2.725d0

      real(rt), dimension(simd_width) :: logT, tmp, fhi, flo
      real(rt), dimension(simd_width) :: ahp, ahep, ahepp, ad, geh0, gehe0, gehep
      real(rt), dimension(simd_width) :: bh0, bhe0, bhep, bff1, bff4, rhp, rhep, rhepp
      real(rt), dimension(simd_width) :: lambda_c, lambda_ff, lambda, heat
      real(rt), dimension(simd_width) :: rho, U
      real(rt) :: a
      real(rt), dimension(simd_width) :: nh, nh0, nhp, nhe0, nhep, nhepp
      integer, dimension(simd_width) :: j
      integer :: m
      logical, dimension(simd_width) :: hot

      do m = 1, simd_width
        if (e_in(m) .lt. 0.d0) then
           e_in(m) = tiny(e_in(m))
        endif
      end do

     ! Converts from code units to CGS
      rho = rho_vode_vec * density_to_cgs * (1.0d0+z_vode)**3
        U = e_in * e_to_cgs
      nh  = rho*XHYDROGEN/MPROTON

      if (time .gt. 1) then
         print *,'TIME INTO F_RHS ',time
         call bl_pd_abort("TOO BIG TIME IN F_RHS")
      end if

      ! Get gas temperature and individual ionization species
      call iterate_ne_vec(z_vode, U, T_vode_vec, nh, ne_vode_vec, nh0, nhp, nhe0, nhep, nhepp, simd_width)

      ! Convert species to CGS units: 
      ne_vode_vec = nh * ne_vode_vec
      nh0   = nh * nh0
      nhp   = nh * nhp
      nhe0  = nh * nhe0
      nhep  = nh * nhep
      nhepp = nh * nhepp

      logT = dlog10(T_vode_vec)
      do m = 1, simd_width
         if (logT(m) .ge. TCOOLMAX) then ! Only free-free and Compton cooling are relevant
            lambda_ff(m) = 1.42d-27 * dsqrt(T_vode_vec(m)) * (1.1d0 + 0.34d0*dexp(-(5.5d0 - logT(m))**2 / 3.0d0)) &
                                 * (nhp(m) + 4.0d0*nhepp(m))*ne_vode_vec(m)
            lambda_c(m)  = compt_c*T_cmb**4 * ne_vode_vec(m) * (T_vode_vec(m) - T_cmb*(1.0d0+z_vode))*(1.0d0 + z_vode)**4

            energy(m)  = (-lambda_ff(m) -lambda_c(m)) * heat_from_cgs/(1.0d0+z_vode)**4

            ! Convert to the actual term to be used in e_out = e_in + dt*energy
            energy(m)  = energy(m) / rho_vode_vec(m) * (1.0d0+z_vode)
            ne_vode_vec(m) = ne_vode_vec(m) / nh(m)
            hot(m) = .true.
         endif
      end do

      do m = 1, simd_width
         if (.not. hot(m)) then
            ! Temperature floor
            if (logT(m) .le. TCOOLMIN) logT(m) = TCOOLMIN + 0.5d0*deltaT
      
            ! Interpolate rates
            tmp(m) = (logT(m)-TCOOLMIN)/deltaT
            j(m) = int(tmp(m))
            fhi(m) = tmp(m) - j(m)
            flo(m) = 1.0d0 - fhi(m)
            j(m) = j(m) + 1 ! F90 arrays start with 1
      
            ahp(m)   = flo(m)*AlphaHp  (j(m)) + fhi(m)*AlphaHp  (j(m)+1)
            ahep(m)  = flo(m)*AlphaHep (j(m)) + fhi(m)*AlphaHep (j(m)+1)
            ahepp(m) = flo(m)*AlphaHepp(j(m)) + fhi(m)*AlphaHepp(j(m)+1)
            ad(m)    = flo(m)*Alphad   (j(m)) + fhi(m)*Alphad   (j(m)+1)
            geh0(m)  = flo(m)*GammaeH0 (j(m)) + fhi(m)*GammaeH0 (j(m)+1)
            gehe0(m) = flo(m)*GammaeHe0(j(m)) + fhi(m)*GammaeHe0(j(m)+1)
            gehep(m) = flo(m)*GammaeHep(j(m)) + fhi(m)*GammaeHep(j(m)+1)
            bh0(m)   = flo(m)*BetaH0   (j(m)) + fhi(m)*BetaH0   (j(m)+1)
            bhe0(m)  = flo(m)*BetaHe0  (j(m)) + fhi(m)*BetaHe0  (j(m)+1)
            bhep(m)  = flo(m)*BetaHep  (j(m)) + fhi(m)*BetaHep  (j(m)+1)
            bff1(m)  = flo(m)*Betaff1  (j(m)) + fhi(m)*Betaff1  (j(m)+1)
            bff4(m)  = flo(m)*Betaff4  (j(m)) + fhi(m)*Betaff4  (j(m)+1)
            rhp(m)   = flo(m)*RecHp    (j(m)) + fhi(m)*RecHp    (j(m)+1)
            rhep(m)  = flo(m)*RecHep   (j(m)) + fhi(m)*RecHep   (j(m)+1)
            rhepp(m) = flo(m)*RecHepp  (j(m)) + fhi(m)*RecHepp  (j(m)+1)
      
            ! Cooling: 
            lambda(m) = ( bh0(m)*nh0(m) + bhe0(m)*nhe0(m) + bhep(m)*nhep(m) + &
                       rhp(m)*nhp(m) + rhep(m)*nhep(m) + rhepp(m)*nhepp(m) + &
                       bff1(m)*(nhp(m)+nhep(m)) + bff4(m)*nhepp(m) ) * ne_vode_vec(m)

            lambda_c(m) = compt_c*T_cmb**4*ne_vode_vec(m)*(T_vode_vec(m) - T_cmb*(1.0d0+z_vode))*(1.0d0 + z_vode)**4   ! Compton cooling
            lambda(m) = lambda(m) + lambda_c(m)
      
            ! Heating terms
            heat(m) = nh0(m)*eh0 + nhe0(m)*ehe0 + nhep(m)*ehep
      
            ! Convert back to code units
            ne_vode_vec(m)     = ne_vode_vec(m) / nh(m)
            energy(m) = (heat(m) - lambda(m))*heat_from_cgs/(1.0d0+z_vode)**4
      
            ! Convert to the actual term to be used in e_out = e_in + dt*energy
            a = 1.d0 / (1.d0 + z_vode)
            energy(m) = energy(m) / rho_vode_vec(m) / a
         end if
      end do

end subroutine f_rhs_vec

subroutine jac(neq, t, y, ml, mu, pd, nrpd, rpar, ipar)

  use amrex_fort_module, only : rt => amrex_real
  implicit none

  integer         , intent(in   ) :: neq, ml, mu, nrpd, ipar
  real(rt), intent(in   ) :: y(neq), rpar, t
  real(rt), intent(  out) :: pd(neq,neq)

  ! Should never get here, we are using a numerical Jacobian
  print *,'IN JAC ROUTINE'
  stop

end subroutine jac
