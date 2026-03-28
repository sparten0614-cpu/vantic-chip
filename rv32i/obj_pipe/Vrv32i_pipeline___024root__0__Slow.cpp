// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vrv32i_pipeline.h for the primary calling header

#include "Vrv32i_pipeline__pch.h"

VL_ATTR_COLD void Vrv32i_pipeline___024root___eval_static(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_static\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0 = vlSelfRef.rst_n;
}

VL_ATTR_COLD void Vrv32i_pipeline___024root___eval_initial(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_initial\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vrv32i_pipeline___024root___eval_final(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_final\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrv32i_pipeline___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vrv32i_pipeline___024root___eval_phase__stl(Vrv32i_pipeline___024root* vlSelf);

VL_ATTR_COLD void Vrv32i_pipeline___024root___eval_settle(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_settle\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vrv32i_pipeline___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("rtl/rv32i_pipeline.v", 16, "", "DIDNOTCONVERGE: Settle region did not converge after '--converge-limit' of 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        vlSelfRef.__VstlPhaseResult = Vrv32i_pipeline___024root___eval_phase__stl(vlSelf);
        vlSelfRef.__VstlFirstIteration = 0U;
    } while (vlSelfRef.__VstlPhaseResult);
}

VL_ATTR_COLD void Vrv32i_pipeline___024root___eval_triggers_vec__stl(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_triggers_vec__stl\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered[0U]) 
                                     | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
}

VL_ATTR_COLD bool Vrv32i_pipeline___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrv32i_pipeline___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vrv32i_pipeline___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vrv32i_pipeline___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___trigger_anySet__stl\n"); );
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

VL_ATTR_COLD void Vrv32i_pipeline___024root___stl_sequent__TOP__0(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___stl_sequent__TOP__0\n"); );
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
    // Body
    vlSelfRef.imem_addr = vlSelfRef.rv32i_pipeline__DOT__pc;
    vlSelfRef.pc_out = vlSelfRef.rv32i_pipeline__DOT__pc;
    vlSelfRef.dmem_addr = vlSelfRef.rv32i_pipeline__DOT__exmem_mem_addr;
    vlSelfRef.dmem_wen = vlSelfRef.rv32i_pipeline__DOT__exmem_mem_wen;
    vlSelfRef.dmem_ren = vlSelfRef.rv32i_pipeline__DOT__exmem_mem_ren;
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
    vlSelfRef.halt = ((0x73U == (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_opcode)) 
                      & (vlSelfRef.rv32i_pipeline__DOT__idex_imm 
                         & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid)));
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
    vlSelfRef.rv32i_pipeline__DOT__branch_target = 
        (vlSelfRef.rv32i_pipeline__DOT__idex_imm + vlSelfRef.rv32i_pipeline__DOT__idex_pc);
    rv32i_pipeline__DOT__id_imm_i = (((- (IData)((vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                                  >> 0x0000001fU))) 
                                      << 0x0000000cU) 
                                     | (vlSelfRef.rv32i_pipeline__DOT__ifid_instr 
                                        >> 0x00000014U));
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_3 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_jal) 
           & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_4 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_jalr) 
           & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid));
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_1 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_reg_wen) 
           & (0U != (IData)(vlSelfRef.rv32i_pipeline__DOT__exmem_rd)));
    rv32i_pipeline__DOT____VdfgRegularize_ha02ecbec_0_2 
        = ((IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_reg_wen) 
           & (0U != (IData)(vlSelfRef.rv32i_pipeline__DOT__memwb_rd)));
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
    rv32i_pipeline__DOT__alu_b = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_use_imm)
                                   ? vlSelfRef.rv32i_pipeline__DOT__idex_imm
                                   : vlSelfRef.rv32i_pipeline__DOT__ex_rs2);
    vlSelfRef.rv32i_pipeline__DOT__ex_mem_addr = (rv32i_pipeline__DOT__alu_a 
                                                  + vlSelfRef.rv32i_pipeline__DOT__idex_imm);
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
    rv32i_pipeline__DOT__ex_branch_taken = ((IData)(vlSelfRef.rv32i_pipeline__DOT__idex_is_branch) 
                                            & ((IData)(rv32i_pipeline__DOT__branch_taken) 
                                               & (IData)(vlSelfRef.rv32i_pipeline__DOT__idex_valid)));
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
}

VL_ATTR_COLD void Vrv32i_pipeline___024root___eval_stl(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_stl\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
        Vrv32i_pipeline___024root___stl_sequent__TOP__0(vlSelf);
    }
}

VL_ATTR_COLD bool Vrv32i_pipeline___024root___eval_phase__stl(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___eval_phase__stl\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    Vrv32i_pipeline___024root___eval_triggers_vec__stl(vlSelf);
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vrv32i_pipeline___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
    __VstlExecute = Vrv32i_pipeline___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        Vrv32i_pipeline___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool Vrv32i_pipeline___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vrv32i_pipeline___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vrv32i_pipeline___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @(negedge rst_n)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vrv32i_pipeline___024root___ctor_var_reset(Vrv32i_pipeline___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vrv32i_pipeline___024root___ctor_var_reset\n"); );
    Vrv32i_pipeline__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->rst_n = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1638864771569018232ull);
    vlSelf->imem_addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 3458333758007846314ull);
    vlSelf->imem_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 16345309528064776366ull);
    vlSelf->dmem_addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 1850890521623420478ull);
    vlSelf->dmem_wdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 14835905180964925233ull);
    vlSelf->dmem_wstrb = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 7859379407741398197ull);
    vlSelf->dmem_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 12721373027701697618ull);
    vlSelf->dmem_ren = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2407022582228024669ull);
    vlSelf->dmem_rdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2017903772712052182ull);
    vlSelf->pc_out = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 4379395961601650806ull);
    vlSelf->halt = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 11049222807502041558ull);
    vlSelf->rv32i_pipeline__DOT__stall = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5306017516165541154ull);
    vlSelf->rv32i_pipeline__DOT__flush = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 10513777803814408089ull);
    vlSelf->rv32i_pipeline__DOT__pc = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 15512893717177161643ull);
    vlSelf->rv32i_pipeline__DOT__pc_next = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 11252384352889784410ull);
    vlSelf->rv32i_pipeline__DOT__ifid_instr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 7375777768055420464ull);
    vlSelf->rv32i_pipeline__DOT__ifid_pc = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 13017363640446770852ull);
    vlSelf->rv32i_pipeline__DOT__ifid_valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1888345513828881743ull);
    for (int __Vi0 = 0; __Vi0 < 32; ++__Vi0) {
        vlSelf->rv32i_pipeline__DOT__regs[__Vi0] = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 1182468724648310750ull);
    }
    vlSelf->rv32i_pipeline__DOT__id_imm = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 9424958653489511362ull);
    vlSelf->rv32i_pipeline__DOT__idex_pc = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 11447752711396253132ull);
    vlSelf->rv32i_pipeline__DOT__idex_rs1_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 9716773702990076041ull);
    vlSelf->rv32i_pipeline__DOT__idex_rs2_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 4767995079434220085ull);
    vlSelf->rv32i_pipeline__DOT__idex_imm = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 17024907289175102303ull);
    vlSelf->rv32i_pipeline__DOT__idex_rd = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 7523033999137301991ull);
    vlSelf->rv32i_pipeline__DOT__idex_rs1 = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 467613611006312339ull);
    vlSelf->rv32i_pipeline__DOT__idex_rs2 = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 12609594250872297851ull);
    vlSelf->rv32i_pipeline__DOT__idex_funct3 = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 5947112935810260540ull);
    vlSelf->rv32i_pipeline__DOT__idex_funct7 = VL_SCOPED_RAND_RESET_I(7, __VscopeHash, 4907063066833727647ull);
    vlSelf->rv32i_pipeline__DOT__idex_opcode = VL_SCOPED_RAND_RESET_I(7, __VscopeHash, 14252024652372555044ull);
    vlSelf->rv32i_pipeline__DOT__idex_reg_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7414717016257845924ull);
    vlSelf->rv32i_pipeline__DOT__idex_mem_ren = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6843129309689594407ull);
    vlSelf->rv32i_pipeline__DOT__idex_mem_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1721009938224194837ull);
    vlSelf->rv32i_pipeline__DOT__idex_is_branch = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16340195752972966136ull);
    vlSelf->rv32i_pipeline__DOT__idex_is_jal = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1248252592848939082ull);
    vlSelf->rv32i_pipeline__DOT__idex_is_jalr = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7415925533143004381ull);
    vlSelf->rv32i_pipeline__DOT__idex_use_imm = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3402671864349917247ull);
    vlSelf->rv32i_pipeline__DOT__idex_valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13163727020755501302ull);
    vlSelf->rv32i_pipeline__DOT__ex_rs2 = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 17790155536300678987ull);
    vlSelf->rv32i_pipeline__DOT__branch_target = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12661184849066582252ull);
    vlSelf->rv32i_pipeline__DOT__ex_mem_addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 7843538206830799835ull);
    vlSelf->rv32i_pipeline__DOT__exmem_alu_result = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 9454347867801429606ull);
    vlSelf->rv32i_pipeline__DOT__exmem_rs2_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 8198555617468288538ull);
    vlSelf->rv32i_pipeline__DOT__exmem_mem_addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 16552701215516323200ull);
    vlSelf->rv32i_pipeline__DOT__exmem_rd = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 10209991191159764332ull);
    vlSelf->rv32i_pipeline__DOT__exmem_funct3 = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 2690003350329540214ull);
    vlSelf->rv32i_pipeline__DOT__exmem_reg_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5552367583365129569ull);
    vlSelf->rv32i_pipeline__DOT__exmem_mem_ren = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6057796188361654021ull);
    vlSelf->rv32i_pipeline__DOT__exmem_mem_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16544100529341077095ull);
    vlSelf->rv32i_pipeline__DOT__memwb_alu_result = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 14148991897081277484ull);
    vlSelf->rv32i_pipeline__DOT__memwb_mem_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 1474050561461248641ull);
    vlSelf->rv32i_pipeline__DOT__memwb_rd = VL_SCOPED_RAND_RESET_I(5, __VscopeHash, 4007769652230437226ull);
    vlSelf->rv32i_pipeline__DOT__memwb_funct3 = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 5365223238409638392ull);
    vlSelf->rv32i_pipeline__DOT__memwb_reg_wen = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17433839125312007702ull);
    vlSelf->rv32i_pipeline__DOT__memwb_mem_ren = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3449224772776414534ull);
    vlSelf->rv32i_pipeline__DOT__wb_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 7699621642048926699ull);
    vlSelf->__VdfgRegularize_hebeb780c_0_1 = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__rst_n__0 = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
}
