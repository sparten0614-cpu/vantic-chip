// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VRV32I_PIPELINE__SYMS_H_
#define VERILATED_VRV32I_PIPELINE__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vrv32i_pipeline.h"

// INCLUDE MODULE CLASSES
#include "Vrv32i_pipeline___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vrv32i_pipeline__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vrv32i_pipeline* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vrv32i_pipeline___024root      TOP;

    // CONSTRUCTORS
    Vrv32i_pipeline__Syms(VerilatedContext* contextp, const char* namep, Vrv32i_pipeline* modelp);
    ~Vrv32i_pipeline__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
