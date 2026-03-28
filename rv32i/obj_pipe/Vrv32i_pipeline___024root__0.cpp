// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vrv32i_pipeline.h for the primary calling header

#include "Vrv32i_pipeline__pch.h"

void Vrv32i_pipeline___024root___eval_triggers_vec__act(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_triggers_vec__act\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                    ((((~ (IData)(vlSelfRef.rst_n)) 
                                                       & (IData)(vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0)) 
                                                      << 1U) 
                                                     | ((IData)(vlSelfRef.clk) 
                                                        & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__0))))));
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0 = vlSelfRef.rst_n;
}

bool Vrv32i_pipeline___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

extern const VlUnpacked<CData/*0:0*/, 512> Vrv32i_pipeline__ConstPool__TABLE_hecd45ce9_0;

void Vrv32i_pipeline___024root___nba_sequent__TOP__0(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___nba_sequent__TOP__0\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ rv32i_pipeline__DOT__id_imm_i;
    rv32i_pipeline__DOT__id_imm_i = 0;
    IData/*31:0*/ rv32i_pipeline__DOT__alu_a;
    rv32i_pipeline__DOT__alu_a = 0;
    IData/*31:0*/ rv32i_pipeline__DOT__alu_b;
    rv32i_pipeline__DOT__alu_b = 0;
    CData/*0:0*/ rv32i_pipeline__DOT__alu_lt;
    rv32i_pipeline__DOT__alu_lt = 0;
    CData/*0:0*/ rv32i_pipeline__DOT__alu_ltu;
    rv32i_pipeline__DOT__alu_ltu = 0;
    CData/*0:0*/ rv32i_pipeline__DOT__branch_taken;
    rv32i_pipeline__DOT__branch_taken = 0;
    CData/*0:0*/ rv32i_pipeline__DOT__ex_branch_taken;
    rv32i_pipeline__DOT__ex_branch_taken = 0;
    CData/*0:0*/ rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_1;
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_1 = 0;
    CData/*0:0*/ rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_2;
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_2 = 0;
    CData/*0:0*/ rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_3;
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_3 = 0;
    CData/*0:0*/ rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_4;
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_4 = 0;
    SData/*8:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    IData/*31:0*/ __VdfgRegularize_hebeb780c_0_0;
    __VdfgRegularize_hebeb780c_0_0 = 0;
    IData/*31:0*/ __Vdly__rv32i_pipeline__DOT__pc;
    __Vdly__rv32i_pipeline__DOT__pc = 0;
    IData/*31:0*/ __VdlyVal__rv32i_pipeline__DOT__regs__v0;
    __VdlyVal__rv32i_pipeline__DOT__regs__v0 = 0;
    CData/*4:0*/ __VdlyDim0__rv32i_pipeline__DOT__regs__v0;
    __VdlyDim0__rv32i_pipeline__DOT__regs__v0 = 0;
    CData/*0:0*/ __VdlySet__rv32i_pipeline__DOT__regs__v0;
    __VdlySet__rv32i_pipeline__DOT__regs__v0 = 0;
    CData/*0:0*/ __VdlySet__rv32i_pipeline__DOT__regs__v1;
    __VdlySet__rv32i_pipeline__DOT__regs__v1 = 0;
    // Body
    __Vdly__rv32i_pipeline__DOT__pc = vlSelfRef.rv32i_pipeline__DOT__pc;
    __VdlySet__rv32i_pipeline__DOT__regs__v0 = 0U;
    __VdlySet__rv32i_pipeline__DOT__regs__v1 = 0U;
    vlSelfRef.rv32i_pipeline__DOT__memwb_mem_ren = 
        ((IData)(vlSelfRef.rst_n) && (IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_mem_ren));
    if (vlSelfRef.rst_n) {
        if (vlSelfRef.halt) {
            __Vdly__rv32i_pipeline__DOT__pc = vlSelfRef.rv32i_pipeline__DOT__pc;
        } else if ((1U & (~ (IData)(vlSelfRef.rv32i_pipeline__DOT__stall)))) {
            __Vdly__rv32i_pipeline__DOT__pc = vlSelfRef.rv32i_pipeline__DOT__pc_next;
        }
        if (((IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_reg_wen) 
             & (0U != (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_rd)))) {
            __VdlyVal__rv32i_pipeline__DOT__regs__v0 
                = vlSelfRef.rv32i_pipeline__DOT__wb_data;
            __VdlyDim0__rv32i_pipeline__DOT__regs__v0 
                = vlSelfRef.rv32i_pipeline__DOT__memwb_rd;
            __VdlySet__rv32i_pipeline__DOT__regs__v0 = 1U;
        }
        if ((1U & (~ (IData)(vlSelfRef.halt)))) {
            vlSelfRef.rv32i_pipeline__DOT__exmem_mem_addr 
                = vlSelfRef.rv32i_pipeline__DOT__ex_mem_addr;
            vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data 
                = vlSelfRef.rv32i_pipeline__DOT__ex_rs2;
        }
        if ((1U & (~ ((IData)(vlSelfRef.rv32i_pipeline__DOT__flush) 
                      | ((IData)(vlSelfRef.rv32i_pipeline__DOT__stall) 
                         & (~ (IData)(vlSelfRef.halt))))))) {
            if ((1U & (~ (IData)(vlSelfRef.rv32i_pipeline__DOT__stall)))) {
                vlSelfRef.rv32i_pipeline__DOT__idex_funct7 
                    = (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                       >> 0x00000019U);
                vlSelfRef.rv32i_pipeline__DOT__idex_use_imm 
                    = ((0x33U != (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                       & (0x63U != (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)));
                vlSelfRef.rv32i_pipeline__DOT__idex_rs2 
                    = (0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                      >> 0x00000014U));
                vlSelfRef.rv32i_pipeline__DOT__idex_rs2_data 
                    = ((0U == (0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                              >> 0x00000014U)))
                        ? 0U : vlSelfRef.rv32i_pipeline__DOT__regs
                       [(0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                        >> 0x00000014U))]);
                vlSelfRef.rv32i_pipeline__DOT__idex_rs1 
                    = (0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                      >> 0x0000000fU));
                vlSelfRef.rv32i_pipeline__DOT__idex_rs1_data 
                    = ((0U == (0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                              >> 0x0000000fU)))
                        ? 0U : vlSelfRef.rv32i_pipeline__DOT__regs
                       [(0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                        >> 0x0000000fU))]);
            }
        }
        if (((IData)(vlSelfRef.rv32i_pipeline__DOT__flush) 
             | ((IData)(vlSelfRef.rv32i_pipeline__DOT__stall) 
                & (~ (IData)(vlSelfRef.halt))))) {
            vlSelfRef.rv32i_pipeline__DOT__idex_is_jalr = 0U;
            vlSelfRef.rv32i_pipeline__DOT__idex_is_jal = 0U;
            vlSelfRef.rv32i_pipeline__DOT__idex_is_branch = 0U;
        } else if ((1U & (~ (IData)(vlSelfRef.rv32i_pipeline__DOT__stall)))) {
            vlSelfRef.rv32i_pipeline__DOT__idex_is_jalr 
                = (0x67U == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr));
            vlSelfRef.rv32i_pipeline__DOT__idex_is_jal 
                = (0x6fU == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr));
            vlSelfRef.rv32i_pipeline__DOT__idex_is_branch 
                = (0x63U == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr));
        }
        vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
            = vlSelfRef.dmem_rdata;
    } else {
        __Vdly__rv32i_pipeline__DOT__pc = 0U;
        __VdlySet__rv32i_pipeline__DOT__regs__v1 = 1U;
        vlSelfRef.rv32i_pipeline__DOT__idex_is_jalr = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_is_jal = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_is_branch = 0U;
    }
    if (__VdlySet__rv32i_pipeline__DOT__regs__v0) {
        vlSelfRef.rv32i_pipeline__DOT__regs[__VdlyDim0__rv32i_pipeline__DOT__regs__v0] 
            = __VdlyVal__rv32i_pipeline__DOT__regs__v0;
    }
    if (__VdlySet__rv32i_pipeline__DOT__regs__v1) {
        vlSelfRef.rv32i_pipeline__DOT__regs[0U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[1U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[2U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[3U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[4U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[5U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[6U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[7U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[8U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[9U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[10U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[11U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[12U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[13U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[14U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[15U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[16U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[17U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[18U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[19U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[20U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[21U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[22U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[23U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[24U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[25U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[26U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[27U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[28U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[29U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[30U] = 0U;
        vlSelfRef.rv32i_pipeline__DOT__regs[31U] = 0U;
    }
    vlSelfRef.rv32i_pipeline__DOT__memwb_reg_wen = 
        ((IData)(vlSelfRef.rst_n) && (IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_reg_wen));
    if (vlSelfRef.rst_n) {
        vlSelfRef.rv32i_pipeline__DOT__memwb_funct3 
            = vlSelfRef.rv32i_pipeline__DOT__exmem_funct3;
        vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result 
            = vlSelfRef.rv32i_pipeline__DOT__exmem_alu_result;
        vlSelfRef.rv32i_pipeline__DOT__memwb_rd = vlSelfRef.rv32i_pipeline__DOT__exmem_rd;
        if ((1U & (~ (IData)(vlSelfRef.halt)))) {
            vlSelfRef.rv32i_pipeline__DOT__exmem_mem_wen 
                = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_mem_wen) 
                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
            vlSelfRef.rv32i_pipeline__DOT__exmem_funct3 
                = vlSelfRef.rv32i_pipeline__DOT__idex_funct3;
            vlSelfRef.rv32i_pipeline__DOT__exmem_mem_ren 
                = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_mem_ren) 
                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
            vlSelfRef.rv32i_pipeline__DOT__exmem_alu_result 
                = ((0x00000040U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                    ? ((0x00000020U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                        ? ((0x00000010U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                            ? vlSelfRef.__VdfgRegularize_hebeb780c_0_1
                            : ((4U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                ? ((2U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                    ? ((1U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                        ? ((IData)(4U) 
                                           + vlSelfRef.rv32i_pipeline__DOT__idex_pc)
                                        : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                                    : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                                : vlSelfRef.__VdfgRegularize_hebeb780c_0_1))
                        : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                    : ((0x00000020U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                        ? ((0x00000010U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                            ? ((8U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                ? vlSelfRef.__VdfgRegularize_hebeb780c_0_1
                                : ((4U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                    ? ((2U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                        ? ((1U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                            ? vlSelfRef.rv32i_pipeline__DOT__idex_imm
                                            : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                                        : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                                    : vlSelfRef.__VdfgRegularize_hebeb780c_0_1))
                            : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                        : ((0x00000010U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                            ? ((8U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                ? vlSelfRef.__VdfgRegularize_hebeb780c_0_1
                                : ((4U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                    ? ((2U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                        ? ((1U & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode))
                                            ? vlSelfRef.rv32i_pipeline__DOT__branch_target
                                            : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                                        : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)
                                    : vlSelfRef.__VdfgRegularize_hebeb780c_0_1))
                            : vlSelfRef.__VdfgRegularize_hebeb780c_0_1)));
            vlSelfRef.rv32i_pipeline__DOT__exmem_reg_wen 
                = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_reg_wen) 
                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
            vlSelfRef.rv32i_pipeline__DOT__exmem_rd 
                = vlSelfRef.rv32i_pipeline__DOT__idex_rd;
        }
        if (((IData)(vlSelfRef.rv32i_pipeline__DOT__flush) 
             | ((IData)(vlSelfRef.rv32i_pipeline__DOT__stall) 
                & (~ (IData)(vlSelfRef.halt))))) {
            vlSelfRef.rv32i_pipeline__DOT__idex_mem_wen = 0U;
            vlSelfRef.rv32i_pipeline__DOT__idex_mem_ren = 0U;
            vlSelfRef.rv32i_pipeline__DOT__idex_opcode = 0U;
            vlSelfRef.rv32i_pipeline__DOT__idex_valid = 0U;
            vlSelfRef.rv32i_pipeline__DOT__idex_reg_wen = 0U;
        } else if ((1U & (~ (IData)(vlSelfRef.rv32i_pipeline__DOT__stall)))) {
            vlSelfRef.rv32i_pipeline__DOT__idex_mem_wen 
                = (0x23U == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr));
            vlSelfRef.rv32i_pipeline__DOT__idex_mem_ren 
                = (3U == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr));
            vlSelfRef.rv32i_pipeline__DOT__idex_opcode 
                = (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr);
            vlSelfRef.rv32i_pipeline__DOT__idex_valid 
                = vlSelfRef.rv32i_pipeline__DOT__ifid_valid;
            vlSelfRef.rv32i_pipeline__DOT__idex_reg_wen 
                = (((0x37U == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                    | ((0x17U == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                       | ((0x6fU == (0x0000007fU & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                          | ((0x67U == (0x0000007fU 
                                        & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                             | ((3U == (0x0000007fU 
                                        & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                                | ((0x13U == (0x0000007fU 
                                              & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)) 
                                   | (0x33U == (0x0000007fU 
                                                & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)))))))) 
                   & (0U != (0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                            >> 7U))));
        }
        if ((1U & (~ ((IData)(vlSelfRef.rv32i_pipeline__DOT__flush) 
                      | ((IData)(vlSelfRef.rv32i_pipeline__DOT__stall) 
                         & (~ (IData)(vlSelfRef.halt))))))) {
            if ((1U & (~ (IData)(vlSelfRef.rv32i_pipeline__DOT__stall)))) {
                vlSelfRef.rv32i_pipeline__DOT__idex_funct3 
                    = (7U & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                             >> 0x0000000cU));
                vlSelfRef.rv32i_pipeline__DOT__idex_pc 
                    = vlSelfRef.rv32i_pipeline__DOT__ifid_pc;
                vlSelfRef.rv32i_pipeline__DOT__idex_imm 
                    = vlSelfRef.rv32i_pipeline__DOT__id_imm;
                vlSelfRef.rv32i_pipeline__DOT__idex_rd 
                    = (0x0000001fU & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                      >> 7U));
            }
        }
        if (vlSelfRef.rv32i_pipeline__DOT__flush) {
            vlSelfRef.rv32i_pipeline__DOT__ifid_pc = 0U;
            vlSelfRef.rv32i_pipeline__DOT__ifid_valid = 0U;
            vlSelfRef.rv32i_pipeline__DOT__ifid_instr = 0x00000013U;
        } else if ((1U & (~ (IData)(vlSelfRef.rv32i_pipeline__DOT__stall)))) {
            vlSelfRef.rv32i_pipeline__DOT__ifid_pc 
                = vlSelfRef.rv32i_pipeline__DOT__pc;
            vlSelfRef.rv32i_pipeline__DOT__ifid_valid = 1U;
            vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                = vlSelfRef.imem_data;
        }
    } else {
        vlSelfRef.rv32i_pipeline__DOT__exmem_mem_wen = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_mem_wen = 0U;
        vlSelfRef.rv32i_pipeline__DOT__exmem_mem_ren = 0U;
        vlSelfRef.rv32i_pipeline__DOT__exmem_reg_wen = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_mem_ren = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_opcode = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_valid = 0U;
        vlSelfRef.rv32i_pipeline__DOT__idex_reg_wen = 0U;
        vlSelfRef.rv32i_pipeline__DOT__ifid_pc = 0U;
        vlSelfRef.rv32i_pipeline__DOT__ifid_valid = 0U;
        vlSelfRef.rv32i_pipeline__DOT__ifid_instr = 0x00000013U;
    }
    vlSelfRef.dmem_addr = vlSelfRef.rv32i_pipeline__DOT__exmem_mem_addr;
    vlSelfRef.dmem_wen = vlSelfRef.rv32i_pipeline__DOT__exmem_mem_wen;
    vlSelfRef.rv32i_pipeline__DOT__wb_data = ((IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_mem_ren)
                                               ? ((4U 
                                                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_funct3))
                                                   ? 
                                                  ((2U 
                                                    & (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_funct3))
                                                    ? vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data
                                                    : 
                                                   ((1U 
                                                     & (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_funct3))
                                                     ? 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                      ? 
                                                     VL_SHIFTR_III(32,32,32, vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data, 0x00000010U)
                                                      : 
                                                     (0x0000ffffU 
                                                      & vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data))
                                                     : 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                      ? 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                       ? 
                                                      VL_SHIFTR_III(32,32,32, vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data, 0x00000018U)
                                                       : 
                                                      (0x000000ffU 
                                                       & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                          >> 0x00000010U)))
                                                      : 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                       ? 
                                                      (0x000000ffU 
                                                       & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                          >> 8U))
                                                       : 
                                                      (0x000000ffU 
                                                       & vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data)))))
                                                   : 
                                                  ((2U 
                                                    & (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_funct3))
                                                    ? vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data
                                                    : 
                                                   ((1U 
                                                     & (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_funct3))
                                                     ? 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                      ? 
                                                     (((- (IData)(
                                                                  (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                                   >> 0x0000001fU))) 
                                                       << 0x00000010U) 
                                                      | (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                         >> 0x00000010U))
                                                      : 
                                                     (((- (IData)(
                                                                  (1U 
                                                                   & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                                      >> 0x0000000fU)))) 
                                                       << 0x00000010U) 
                                                      | (0x0000ffffU 
                                                         & vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data)))
                                                     : 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                      ? 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                       ? 
                                                      (((- (IData)(
                                                                   (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                                    >> 0x0000001fU))) 
                                                        << 8U) 
                                                       | (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                          >> 0x00000018U))
                                                       : 
                                                      (((- (IData)(
                                                                   (1U 
                                                                    & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                                       >> 0x00000017U)))) 
                                                        << 8U) 
                                                       | (0x000000ffU 
                                                          & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                             >> 0x00000010U))))
                                                      : 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result)
                                                       ? 
                                                      (((- (IData)(
                                                                   (1U 
                                                                    & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                                       >> 0x0000000fU)))) 
                                                        << 8U) 
                                                       | (0x000000ffU 
                                                          & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                             >> 8U)))
                                                       : 
                                                      (((- (IData)(
                                                                   (1U 
                                                                    & (vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data 
                                                                       >> 7U)))) 
                                                        << 8U) 
                                                       | (0x000000ffU 
                                                          & vlSelfRef.rv32i_pipeline__DOT__memwb_mem_data)))))))
                                               : vlSelfRef.rv32i_pipeline__DOT__memwb_alu_result);
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_2 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_reg_wen) 
           & (0U != (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_rd)));
    if ((0U == (3U & (IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_funct3)))) {
        vlSelfRef.dmem_wdata = ((vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data 
                                 << 0x00000018U) | 
                                ((0x00ff0000U & (vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data 
                                                 << 0x00000010U)) 
                                 | ((0x0000ff00U & 
                                     (vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data 
                                      << 8U)) | (0x000000ffU 
                                                 & vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data))));
        vlSelfRef.dmem_wstrb = (0x0000000fU & ((IData)(1U) 
                                               << (3U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__exmem_mem_addr)));
    } else if ((1U == (3U & (IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_funct3)))) {
        vlSelfRef.dmem_wdata = ((vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data 
                                 << 0x00000010U) | 
                                (0x0000ffffU & vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data));
        vlSelfRef.dmem_wstrb = (0x0000000fU & ((IData)(3U) 
                                               << (2U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__exmem_mem_addr)));
    } else {
        vlSelfRef.dmem_wdata = vlSelfRef.rv32i_pipeline__DOT__exmem_rs2_data;
        vlSelfRef.dmem_wstrb = (0x0000000fU & 0x0fU);
    }
    vlSelfRef.dmem_ren = vlSelfRef.rv32i_pipeline__DOT__exmem_mem_ren;
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_1 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_reg_wen) 
           & (0U != (IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_rd)));
    vlSelfRef.rv32i_pipeline__DOT__branch_target = 
        (vlSelfRef.rv32i_pipeline__DOT__idex_imm + vlSelfRef.rv32i_pipeline__DOT__idex_pc);
    vlSelfRef.rv32i_pipeline__DOT__ex_rs2 = (((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_1) 
                                              & ((IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_rd) 
                                                 == (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_rs2)))
                                              ? vlSelfRef.rv32i_pipeline__DOT__exmem_alu_result
                                              : (((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_2) 
                                                  & ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_rs2) 
                                                     == (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_rd)))
                                                  ? vlSelfRef.rv32i_pipeline__DOT__wb_data
                                                  : vlSelfRef.rv32i_pipeline__DOT__idex_rs2_data));
    rv32i_pipeline__DOT__alu_a = (((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_1) 
                                   & ((IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_rd) 
                                      == (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_rs1)))
                                   ? vlSelfRef.rv32i_pipeline__DOT__exmem_alu_result
                                   : (((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_2) 
                                       & ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_rs1) 
                                          == (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_rd)))
                                       ? vlSelfRef.rv32i_pipeline__DOT__wb_data
                                       : vlSelfRef.rv32i_pipeline__DOT__idex_rs1_data));
    vlSelfRef.rv32i_pipeline__DOT__pc = __Vdly__rv32i_pipeline__DOT__pc;
    vlSelfRef.halt = ((0x73U == (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode)) 
                      & (vlSelfRef.rv32i_pipeline__DOT__idex_imm 
                         & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid)));
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_3 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_jal) 
           & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_4 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_jalr) 
           & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
    rv32i_pipeline__DOT__alu_b = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_use_imm)
                                   ? vlSelfRef.rv32i_pipeline__DOT__idex_imm
                                   : vlSelfRef.rv32i_pipeline__DOT__ex_rs2);
    vlSelfRef.rv32i_pipeline__DOT__ex_mem_addr = (rv32i_pipeline__DOT__alu_a 
                                                  + vlSelfRef.rv32i_pipeline__DOT__idex_imm);
    vlSelfRef.imem_addr = vlSelfRef.rv32i_pipeline__DOT__pc;
    vlSelfRef.pc_out = vlSelfRef.rv32i_pipeline__DOT__pc;
    rv32i_pipeline__DOT__alu_lt = VL_LTS_III(32, rv32i_pipeline__DOT__alu_a, rv32i_pipeline__DOT__alu_b);
    rv32i_pipeline__DOT__alu_ltu = (rv32i_pipeline__DOT__alu_a 
                                    < rv32i_pipeline__DOT__alu_b);
    vlSelfRef.__VdfgRegularize_hebeb780c_0_1 = ((4U 
                                                 & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                 ? 
                                                ((2U 
                                                  & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                  ? 
                                                 ((1U 
                                                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                   ? 
                                                  (rv32i_pipeline__DOT__alu_a 
                                                   & rv32i_pipeline__DOT__alu_b)
                                                   : 
                                                  (rv32i_pipeline__DOT__alu_a 
                                                   | rv32i_pipeline__DOT__alu_b))
                                                  : 
                                                 ((1U 
                                                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                   ? 
                                                  (rv32i_pipeline__DOT__alu_a 
                                                   >> 
                                                   (0x0000001fU 
                                                    & rv32i_pipeline__DOT__alu_b))
                                                   : 
                                                  (rv32i_pipeline__DOT__alu_a 
                                                   ^ rv32i_pipeline__DOT__alu_b)))
                                                 : 
                                                ((2U 
                                                  & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                  ? 
                                                 ((1U 
                                                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                   ? (IData)(rv32i_pipeline__DOT__alu_ltu)
                                                   : (IData)(rv32i_pipeline__DOT__alu_lt))
                                                  : 
                                                 ((1U 
                                                   & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3))
                                                   ? 
                                                  (rv32i_pipeline__DOT__alu_a 
                                                   << 
                                                   (0x0000001fU 
                                                    & rv32i_pipeline__DOT__alu_b))
                                                   : 
                                                  (rv32i_pipeline__DOT__alu_a 
                                                   + 
                                                   ((((0x33U 
                                                       == (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode)) 
                                                      & ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct7) 
                                                         >> 5U)) 
                                                     | (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_branch))
                                                     ? 
                                                    ((IData)(1U) 
                                                     + 
                                                     (~ rv32i_pipeline__DOT__alu_b))
                                                     : rv32i_pipeline__DOT__alu_b)))));
    __Vtableidx1 = ((((((rv32i_pipeline__DOT__alu_a 
                         == vlSelfRef.rv32i_pipeline__DOT__ex_rs2) 
                        << 4U) | (((rv32i_pipeline__DOT__alu_a 
                                    != vlSelfRef.rv32i_pipeline__DOT__ex_rs2) 
                                   << 3U) | ((IData)(rv32i_pipeline__DOT__alu_lt) 
                                             << 2U))) 
                      | ((2U & ((~ (IData)(rv32i_pipeline__DOT__alu_lt)) 
                                << 1U)) | (IData)(rv32i_pipeline__DOT__alu_ltu))) 
                     << 4U) | ((8U & ((~ (IData)(rv32i_pipeline__DOT__alu_ltu)) 
                                      << 3U)) | (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_funct3)));
    rv32i_pipeline__DOT__branch_taken = Vrv32i_pipeline__ConstPool__TABLE_hecd45ce9_0
        [__Vtableidx1];
    vlSelfRef.rv32i_pipeline__DOT__stall = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_mem_ren) 
                                            & ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid) 
                                               & ((((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_rd) 
                                                    == 
                                                    (0x0000001fU 
                                                     & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                        >> 0x0000000fU))) 
                                                   & (0U 
                                                      != 
                                                      (0x0000001fU 
                                                       & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                          >> 0x0000000fU)))) 
                                                  | (((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_rd) 
                                                      == 
                                                      (0x0000001fU 
                                                       & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                          >> 0x00000014U))) 
                                                     & (0U 
                                                        != 
                                                        (0x0000001fU 
                                                         & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                            >> 0x00000014U)))))));
    rv32i_pipeline__DOT__id_imm_i = (((- (IData)((vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                  >> 0x0000001fU))) 
                                      << 0x0000000cU) 
                                     | (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                        >> 0x00000014U));
    rv32i_pipeline__DOT__ex_branch_taken = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_branch) 
                                            & ((IData)(rv32i_pipeline__DOT__branch_taken) 
                                               & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid)));
    __VdfgRegularize_hebeb780c_0_0 = ((8U & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                       ? rv32i_pipeline__DOT__id_imm_i
                                       : ((4U & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                           ? ((2U & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                               ? ((1U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                   ? 
                                                  (0xfffff000U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                   : rv32i_pipeline__DOT__id_imm_i)
                                               : rv32i_pipeline__DOT__id_imm_i)
                                           : rv32i_pipeline__DOT__id_imm_i));
    vlSelfRef.rv32i_pipeline__DOT__flush = ((IData)(rv32i_pipeline__DOT__ex_branch_taken) 
                                            | ((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_3) 
                                               | (IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_4)));
    vlSelfRef.rv32i_pipeline__DOT__pc_next = ((IData)(rv32i_pipeline__DOT__ex_branch_taken)
                                               ? vlSelfRef.rv32i_pipeline__DOT__branch_target
                                               : ((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_3)
                                                   ? vlSelfRef.rv32i_pipeline__DOT__branch_target
                                                   : 
                                                  ((IData)(rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_4)
                                                    ? 
                                                   (0xfffffffeU 
                                                    & vlSelfRef.rv32i_pipeline__DOT__ex_mem_addr)
                                                    : 
                                                   ((IData)(4U) 
                                                    + vlSelfRef.rv32i_pipeline__DOT__pc))));
    vlSelfRef.rv32i_pipeline__DOT__id_imm = ((0x00000040U 
                                              & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                              ? ((0x00000020U 
                                                  & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                  ? 
                                                 ((0x00000010U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                   ? rv32i_pipeline__DOT__id_imm_i
                                                   : 
                                                  ((8U 
                                                    & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                    ? 
                                                   ((4U 
                                                     & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                     ? 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                      ? 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                       ? 
                                                      ((((0x00000ffeU 
                                                          & ((- (IData)(
                                                                        (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                         >> 0x0000001fU))) 
                                                             << 1U)) 
                                                         | (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                            >> 0x0000001fU)) 
                                                        << 0x00000014U) 
                                                       | ((((0x000001feU 
                                                             & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                >> 0x0000000bU)) 
                                                            | (1U 
                                                               & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                  >> 0x00000014U))) 
                                                           << 0x0000000bU) 
                                                          | (0x000007feU 
                                                             & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                >> 0x00000014U))))
                                                       : rv32i_pipeline__DOT__id_imm_i)
                                                      : rv32i_pipeline__DOT__id_imm_i)
                                                     : rv32i_pipeline__DOT__id_imm_i)
                                                    : 
                                                   ((4U 
                                                     & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                     ? rv32i_pipeline__DOT__id_imm_i
                                                     : 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                      ? 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                       ? 
                                                      (((- (IData)(
                                                                   (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                    >> 0x0000001fU))) 
                                                        << 0x0000000dU) 
                                                       | ((((2U 
                                                             & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                >> 0x0000001eU)) 
                                                            | (1U 
                                                               & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                  >> 7U))) 
                                                           << 0x0000000bU) 
                                                          | ((0x000007e0U 
                                                              & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                 >> 0x00000014U)) 
                                                             | (0x0000001eU 
                                                                & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                   >> 7U)))))
                                                       : rv32i_pipeline__DOT__id_imm_i)
                                                      : rv32i_pipeline__DOT__id_imm_i))))
                                                  : rv32i_pipeline__DOT__id_imm_i)
                                              : ((0x00000020U 
                                                  & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                  ? 
                                                 ((0x00000010U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                   ? __VdfgRegularize_hebeb780c_0_0
                                                   : 
                                                  ((8U 
                                                    & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                    ? rv32i_pipeline__DOT__id_imm_i
                                                    : 
                                                   ((4U 
                                                     & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                     ? rv32i_pipeline__DOT__id_imm_i
                                                     : 
                                                    ((2U 
                                                      & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                      ? 
                                                     ((1U 
                                                       & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                       ? 
                                                      (((- (IData)(
                                                                   (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                    >> 0x0000001fU))) 
                                                        << 0x0000000cU) 
                                                       | ((0x00000fe0U 
                                                           & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                              >> 0x00000014U)) 
                                                          | (0x0000001fU 
                                                             & (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                                >> 7U))))
                                                       : rv32i_pipeline__DOT__id_imm_i)
                                                      : rv32i_pipeline__DOT__id_imm_i))))
                                                  : 
                                                 ((0x00000010U 
                                                   & vlSelfRef.rv32i_pipeline__DOT__ifid_instr)
                                                   ? __VdfgRegularize_hebeb780c_0_0
                                                   : rv32i_pipeline__DOT__id_imm_i)));
}

void Vrv32i_pipeline___024root___eval_nba(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_nba\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vrv32i_pipeline___024root___nba_sequent__TOP__0(vlSelf);
    }
}

void Vrv32i_pipeline___024root___trigger_orInto__act_vec_vec(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___trigger_orInto__act_vec_vec\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((0U >= n));
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrv32i_pipeline___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool Vrv32i_pipeline___024root___eval_phase__act(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_phase__act\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vrv32i_pipeline___024root___eval_triggers_vec__act(vlSelf);
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vrv32i_pipeline___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
    Vrv32i_pipeline___024root___trigger_orInto__act_vec_vec(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vrv32i_pipeline___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vrv32i_pipeline___024root___eval_phase__nba(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_phase__nba\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vrv32i_pipeline___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vrv32i_pipeline___024root___eval_nba(vlSelf);
        Vrv32i_pipeline___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vrv32i_pipeline___024root___eval(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vrv32i_pipeline___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("rtl/rv32i_pipeline.v", 16, "", "DIDNOTCONVERGE: NBA region did not converge after '--converge-limit' of 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vrv32i_pipeline___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("rtl/rv32i_pipeline.v", 16, "", "DIDNOTCONVERGE: Active region did not converge after '--converge-limit' of 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
            vlSelfRef.__VactPhaseResult = Vrv32i_pipeline___024root___eval_phase__act(vlSelf);
        } while (vlSelfRef.__VactPhaseResult);
        vlSelfRef.__VnbaPhaseResult = Vrv32i_pipeline___024root___eval_phase__nba(vlSelf);
    } while (vlSelfRef.__VnbaPhaseResult);
}

#ifdef VL_DEBUG
void Vrv32i_pipeline___024root___eval_debug_assertions(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_debug_assertions\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.rst_n & 0xfeU)))) {
        Verilated::overWidthError("rst_n");
    }
}
#endif  // VL_DEBUG
