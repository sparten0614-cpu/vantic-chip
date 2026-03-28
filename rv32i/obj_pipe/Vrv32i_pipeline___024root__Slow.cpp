// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vrv32i_pipeline.h for the primary calling header

#include "Vrv32i_pipeline__pch.h"

void Vrv32i_pipeline___024root___ctor_var_reset(Vrv32i_pipeline___024root* vlSelf);

Vrv32i_pipeline___024root::Vrv32i_pipeline___024root(Vrv32i_pipeline__Syms* symsp, const char* namep)
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    Vrv32i_pipeline___024root___ctor_var_reset(this);
}

void Vrv32i_pipeline___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vrv32i_pipeline___024root::~Vrv32i_pipeline___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
