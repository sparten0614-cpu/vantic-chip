// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vrv32i_pipeline__pch.h"

//============================================================
// Constructors

Vrv32i_pipeline::Vrv32i_pipeline(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vrv32i_pipeline__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , rst_n{vlSymsp->TOP.rst_n}
    , dmem_wstrb{vlSymsp->TOP.dmem_wstrb}
    , dmem_wen{vlSymsp->TOP.dmem_wen}
    , dmem_ren{vlSymsp->TOP.dmem_ren}
    , halt{vlSymsp->TOP.halt}
    , imem_addr{vlSymsp->TOP.imem_addr}
    , imem_data{vlSymsp->TOP.imem_data}
    , dmem_addr{vlSymsp->TOP.dmem_addr}
    , dmem_wdata{vlSymsp->TOP.dmem_wdata}
    , dmem_rdata{vlSymsp->TOP.dmem_rdata}
    , pc_out{vlSymsp->TOP.pc_out}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vrv32i_pipeline::Vrv32i_pipeline(const char* _vcname__)
    : Vrv32i_pipeline(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vrv32i_pipeline::~Vrv32i_pipeline() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vrv32i_pipeline___024root___eval_debug_assertions(Vrv32i_pipeline___024root* vlSelf);
#endif  // VL_DEBUG
void Vrv32i_pipeline___024root___eval_static(Vrv32i_pipeline___024root* vlSelf);
void Vrv32i_pipeline___024root___eval_initial(Vrv32i_pipeline___024root* vlSelf);
void Vrv32i_pipeline___024root___eval_settle(Vrv32i_pipeline___024root* vlSelf);
void Vrv32i_pipeline___024root___eval(Vrv32i_pipeline___024root* vlSelf);

void Vrv32i_pipeline::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vrv32i_pipeline::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vrv32i_pipeline___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vrv32i_pipeline___024root___eval_static(&(vlSymsp->TOP));
        Vrv32i_pipeline___024root___eval_initial(&(vlSymsp->TOP));
        Vrv32i_pipeline___024root___eval_settle(&(vlSymsp->TOP));
        vlSymsp->__Vm_didInit = true;
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vrv32i_pipeline___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vrv32i_pipeline::eventsPending() { return false; }

uint64_t Vrv32i_pipeline::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vrv32i_pipeline::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vrv32i_pipeline___024root___eval_final(Vrv32i_pipeline___024root* vlSelf);

VL_ATTR_COLD void Vrv32i_pipeline::final() {
    Vrv32i_pipeline___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vrv32i_pipeline::hierName() const { return vlSymsp->name(); }
const char* Vrv32i_pipeline::modelName() const { return "Vrv32i_pipeline"; }
unsigned Vrv32i_pipeline::threads() const { return 1; }
void Vrv32i_pipeline::prepareClone() const { contextp()->prepareClone(); }
void Vrv32i_pipeline::atClone() const {
    contextp()->threadPoolpOnClone();
}
