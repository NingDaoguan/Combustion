f90sources += main.f90

f90sources += advance.f90
f90sources += build_info.f90
f90sources += checkpoint.f90
f90sources += cputime.f90
f90sources += derivative_stencil.f90
f90sources += initialize.f90

ifdef EXPAND
  ifdef K_USE_STACK
    f90sources += kernels_stack_exp.f90
  else
    f90sources += kernels_exp.f90
  endif
else
  ifdef K_USE_STACK
    f90sources += kernels_stack.f90
  else
    f90sources += kernels.f90
  endif
endif

f90sources += make_plot_variables.f90
f90sources += make_plotfile.f90
f90sources += probin.f90
f90sources += smc.f90
f90sources += smcdata.f90
f90sources += smc_threadbox.f90
f90sources += time.f90
f90sources += transport_properties.f90
f90sources += variables.f90
f90sources += write_job_info.f90
