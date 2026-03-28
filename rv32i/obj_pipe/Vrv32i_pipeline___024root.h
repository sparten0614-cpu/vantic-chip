// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vrv32i_pipeline.h for the primary calling header

#ifndef VERILATED_VRV32I_PIPELINE___024ROOT_H_
#define VERILATED_VRV32I_PIPELINE___024ROOT_H_  // guard

#include "verilated.h"


class Vrv32i_pipeline__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vrv32i_pipeline___024root final {
  public:

    // DESIGN SPECIFIC STATE
    // Anonymous structures to workaround compiler member-count bugs
    struct {
        VL_IN8(clk,0,0);
        VL_IN8(rst_n,0,0);
        VL_OUT8(dmem_wstrb,3,0);
        VL_OUT8(dmem_wen,0,0);
        VL_OUT8(dmem_ren,0,0);
        VL_OUT8(halt,0,0);
        CData/*0:0*/ rv32i_pipeline__DOT__stall;
        CData/*0:0*/ rv32i_pipeline__DOT__flush;
        CData/*0:0*/ rv32i_pipeline__DOT__ifid_valid;
        CData/*4:0*/ rv32i_pipeline__DOT__idex_rd;
        CData/*4:0*/ rv32i_pipeline__DOT__idex_rs1;
        CData/*4:0*/ rv32i_pipeline__DOT__idex_rs2;
        CData/*2:0*/ rv32i_pipeline__DOT__idex_funct3;
        CData/*6:0*/ rv32i_pipeline__DOT__idex_funct7;
        CData/*6:0*/ rv32i_pipeline__DOT__idex_opcode;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_reg_wen;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_mem_ren;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_mem_wen;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_is_branch;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_is_jal;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_is_jalr;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_use_imm;
        CData/*0:0*/ rv32i_pipeline__DOT__idex_valid;
        CData/*4:0*/ rv32i_pipeline__DOT__exmem_rd;
        CData/*2:0*/ rv32i_pipeline__DOT__exmem_funct3;
        CData/*0:0*/ rv32i_pipeline__DOT__exmem_reg_wen;
        CData/*0:0*/ rv32i_pipeline__DOT__exmem_mem_ren;
        CData/*0:0*/ rv32i_pipeline__DOT__exmem_mem_wen;
        CData/*4:0*/ rv32i_pipeline__DOT__memwb_rd;
        CData/*2:0*/ rv32i_pipeline__DOT__memwb_funct3;
        CData/*0:0*/ rv32i_pipeline__DOT__memwb_reg_wen;
        CData/*0:0*/ rv32i_pipeline__DOT__memwb_mem_ren;
        CData/*0:0*/ __VstlFirstIteration;
        CData/*0:0*/ __VstlPhaseResult;
        CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
        CData/*0:0*/ __Vtrigprevexpr___TOP__rst_n__0;
        CData/*0:0*/ __VactPhaseResult;
        CData/*0:0*/ __VnbaPhaseResult;
        VL_OUT(imem_addr,31,0);
        VL_IN(imem_data,31,0);
        VL_OUT(dmem_addr,31,0);
        VL_OUT(dmem_wdata,31,0);
        VL_IN(dmem_rdata,31,0);
        VL_OUT(pc_out,31,0);
        IData/*31:0*/ rv32i_pipeline__DOT__pc;
        IData/*31:0*/ rv32i_pipeline__DOT__pc_next;
        IData/*31:0*/ rv32i_pipeline__DOT__ifid_instr;
        IData/*31:0*/ rv32i_pipeline__DOT__ifid_pc;
        IData/*31:0*/ rv32i_pipeline__DOT__id_imm;
        IData/*31:0*/ rv32i_pipeline__DOT__idex_pc;
        IData/*31:0*/ rv32i_pipeline__DOT__idex_rs1_data;
        IData/*31:0*/ rv32i_pipeline__DOT__idex_rs2_data;
        IData/*31:0*/ rv32i_pipeline__DOT__idex_imm;
        IData/*31:0*/ rv32i_pipeline__DOT__ex_rs2;
        IData/*31:0*/ rv32i_pipeline__DOT__branch_target;
        IData/*31:0*/ rv32i_pipeline__DOT__ex_mem_addr;
        IData/*31:0*/ rv32i_pipeline__DOT__exmem_alu_result;
        IData/*31:0*/ rv32i_pipeline__DOT__exmem_rs2_data;
        IData/*31:0*/ rv32i_pipeline__DOT__exmem_mem_addr;
        IData/*31:0*/ rv32i_pipeline__DOT__memwb_alu_result;
        IData/*31:0*/ rv32i_pipeline__DOT__memwb_mem_data;
        IData/*31:0*/ rv32i_pipeline__DOT__wb_data;
        IData/*31:0*/ __VdfgRegularize_hebeb780c_0_1;
        IData/*31:0*/ __VactIterCount;
    };
    struct {
        VlUnpacked<IData/*31:0*/, 32> rv32i_pipeline__DOT__regs;
        VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
        VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
        VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    };

    // INTERNAL VARIABLES
    Vrv32i_pipeline__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vrv32i_pipeline___024root(Vrv32i_pipeline__Syms* symsp, const char* namep);
    ~Vrv32i_pipeline___024root();
    VL_UNCOPYABLE(Vrv32i_pipeline___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
