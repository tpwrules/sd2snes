#!c:\Python27\python.exe

import argparse
import os.path
import sys

from shutil import copyfile

def enum(**enums):
  return type('Enum', (), enums)
  
#class ByteCount(Enum):

eOpcode = enum(
               ADC=0,
               AND=1,
               ASL=2,
               BCC=3,
               BCS=4,
               BEQ=5,
               BIT=6,
               BMI=7,
               BNE=8,
               BPL=9,
               BRA=10,
               BRK=11,
               BRL=12,
               BVC=13,
               BVS=14,
               CLC=15,
               CLD=16,
               CLI=17,
               CLV=18,
               CMP=19,
               COP=20,
               CPX=21,
               CPY=22,
               DEC=23,
               DEX=24,
               DEY=25,
               EOR=26,
               INC=27,
               INX=28,
               INY=29,
               JML=30,
               JMP=31,
               JSL=32,
               JSR=33,
               LDA=34,
               LDX=35,
               LDY=36,
               LSR=37,
               MVN=38,
               MVP=39,
               NOP=40,
               ORA=41,
               PEA=42,
               PEI=43,
               PER=44,
               PHA=45,
               PHB=46,
               PHD=47,
               PHK=48,
               PHP=49,
               PHX=50,
               PHY=51,
               PLA=52,
               PLB=53,
               PLD=54,
               PLP=55,
               PLX=56,
               PLY=57,
               REP=58,
               ROL=59,
               ROR=60,
               RTI=61,
               RTL=62,
               RTS=63,
               SBC=64,
               SEC=65,
               SED=66,
               SEI=67,
               SEP=68,
               STA=69,
               STP=70,
               STX=71,
               STY=72,
               STZ=73,
               TAX=74,
               TAY=75,
               TCD=76,
               TCS=77,
               TDC=78,
               TRB=79,
               TSB=80,
               TSC=81,
               TSX=82,
               TXA=83,
               TXS=84,
               TXY=85,
               TYA=86,
               TYX=87,
               WAI=88,
               WDM=89,
               XBA=90,
               XCE=91,
              )

# addressing modes
eMode = enum(Absolute=0,
             AbsoluteIndexedX=1,
             AbsoluteIndexedY=2,
             AbsoluteIndexedIndirect=3,
             AbsoluteIndirect=4,
             AbsoluteIndirectLong=5,
             AbsoluteLong=6,
             AbsoluteLongIndexedX=7,
             Accumulator=8,
             #BlockMove=
             
             DirectPage=9,
             DirectPageIndexedX=10,
             DirectPageIndexedY=11,
             DirectPageIndexedIndirectX=12,
             DirectPageIndirect=13,
             DirectPageIndirectLong=14,
             DirectPageIndirectIndexedY=15,
             DirectPageIndirectLongIndexedY=16,
             
             Immediate=17,
             Implied=18,
             ProgramCounterRelative=19,
             ProgramCounterRelativeLong=20,
             
             StackAbsolute=21,
             StackDirectPageIndirect=22,
             StackInterrupt=23,
             StackProgramCounterRelative=24,
             StackPull=25,
             StackPush=26,
             StackRTI=27,
             StackRTL=28,
             StackRTS=29,
             StackRelative=30,
             StackRelativeIndirectIndexedY=31,
            )

ePrc = enum(B=0,M=1,X=2,W=3)
eReg = enum(I=0,A=1,X=2,Y=3,S=4,D=5,B=6,P=7,K=4,   C=0,Z=1,V=2,N=3,c=4,z=5,v=6,n=7)
eGrp = enum(PRI=0,RMW=1,CBR=2,JMP=3,PHS=4,PLL=5,CMP=6,STS=7,MOV=8,TXR=9,SPC=10,SMP=11,STK=12,XCH=13,TST=14,NOP=15)
eBnk = enum(P=0,D=1,Z=2,O=3)
eAdd = enum(O16=0,DPR=1,PCR=2,SPL=3,SMI=4,SPR=5)
eMod = enum(X=0,Y=1,P=2,I=3)

class Instruction:
  
  def to_string(self):
    str = ""
    #str += "{0:01b}".format(self.G_Pri) + "{0:01b}".format(self.G_Rmw) + "{0:01b}".format(self.G_Cbr) + "{0:01b}".format(self.G_Jmp) + "{0:01b}".format(self.G_Phs) + "{0:01b}".format(self.G_Pll) + "{0:01b}".format(self.G_Cmp) + "{0:01b}".format(self.G_Sts) + "{0:01b}".format(self.G_Mov) + "{0:01b}".format(self.G_Txr) + "{0:01b}".format(self.G_Spc) + "{0:01b}".format(self.G_Smp) + "{0:01b}".format(self.G_Stk) + "{0:01b}".format(self.G_Xch) + "{0:01b}".format(self.G_Tst) + "{0:016b}".format(0)
    str +=  "{0:01b}".format(self.Stk) + "{0:01b}".format(self.Lng) + "{0:01b}".format(self.Ind) + "{0:01b}".format(self.Imm) + "{0:02b}".format(self.Mod) + "{0:03b}".format(self.Add) + "{0:02b}".format(self.Bnk) + "{0:04b}".format(self.Grp) + "{0:02b}".format(self.Operands) + "{0:04b}".format(self.Latency) + "{0:02b}".format(self.Prc) + "{0:03b}".format(self.Src) + "{0:03b}".format(self.Dst) + "{0:01b}".format(self.Load) + "{0:01b}".format(self.Store) + "{0:01b}".format(self.Ctl)
    return str
  
  @staticmethod
  def defines():
    str = ''
    str += '`define GRP_PRI     0\n'
    str += '`define GRP_RMW     1\n'
    str += '`define GRP_CBR     2\n'
    str += '`define GRP_JMP     3\n'
    str += '`define GRP_PHS     4\n'
    str += '`define GRP_PLL     5\n'
    str += '`define GRP_CMP     6\n'
    str += '`define GRP_STS     7\n'
    str += '`define GRP_MOV     8\n'
    str += '`define GRP_TXR     9\n'
    str += '`define GRP_SPC     10\n'
    str += '`define GRP_SMP     11\n'
    str += '`define GRP_STK     12\n'
    str += '`define GRP_XCH     13\n'
    str += '`define GRP_TST     14\n'
    str += '\n'
    str += '`define ADD_O16     0\n'
    str += '`define ADD_DPR     1\n'
    str += '`define ADD_PCR     2\n'
    str += '`define ADD_SPL     3\n'
    str += '`define ADD_SMI     4\n'
    str += '`define ADD_SPR     5\n'
    str += '\n'
    str += '`define BNK_PBR     0\n'
    str += '`define BNK_DBR     1\n'
    str += '`define BNK_ZRO     2\n'
    str += '`define BNK_O24     3\n'
    str += '\n'
    str += '`define MOD_X16     0\n'
    str += '`define MOD_Y16     1\n'
    str += '`define MOD_YPT     2\n'
    str += '`define MOD_INV     3\n'
    str += '\n'
    str += '`define ADD_STK     31:31\n'
    str += '`define ADD_LNG     30:30\n'
    str += '`define ADD_IND     29:29\n'
    str += '`define ADD_IMM     28:28\n'
    str += '`define ADD_MOD     27:26\n'
    str += '`define ADD_ADD     25:23\n'
    str += '`define ADD_BNK     22:21\n'
    str += '`define DEC_GROUP   20:17\n'
    str += '`define DEC_SIZE    16:15\n'
    str += '`define DEC_LATENCY 14:11\n'
    str += '`define DEC_PRC     10:9\n'
    str += '`define DEC_SRC      8:6\n'
    str += '`define DEC_DST      5:3\n'
    str += '`define DEC_LOAD     2:2\n'
    str += '`define DEC_STORE    1:1\n'
    str += '`define DEC_CONTROL  0:0\n'
    str += '\n'
    str += '`define PRC_B        0\n'
    str += '`define PRC_M        1\n'
    str += '`define PRC_X        2\n'
    str += '`define PRC_W        3\n'
    str += '\n'
    str += '`define REG_Z        0\n'
    str += '`define REG_A        1\n'
    str += '`define REG_X        2\n'
    str += '`define REG_Y        3\n'
    str += '`define REG_S        4\n'
    str += '`define REG_D        5\n'
    str += '`define REG_B        6\n'
    str += '`define REG_P        7\n'
    str += '`define REG_K        4\n'
    return str
  
  def __init__(self, index, opcode, mode, operands, latency, prc, src, dst, load, store, ctl, grp, imm, bnk, add, mod, ind, lng, stk):
    self.Index = index
    self.Opcode = opcode
    self.Mode = mode
    self.Operands = operands
    self.Latency = latency
    self.Prc = prc
    self.Src = src
    self.Dst = dst
    self.Load = load
    self.Store = store
    self.Ctl = ctl
    self.Grp = grp
    self.Imm = imm
    self.Bnk = bnk
    self.Add = add
    self.Mod = mod
    self.Ind = ind
    self.Lng = lng
    self.Stk = stk

# The tables are unified   
mxTable = [
           #                       7b                  5b                                           2b          4b         2b             3b             3b             1b     1b     1b
           Instruction(index=0x00, opcode=eOpcode.BRK, mode=eMode.StackInterrupt                  , operands=1, latency=7, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=1, grp=eGrp.SPC, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x01, opcode=eOpcode.ORA, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0x02, opcode=eOpcode.COP, mode=eMode.StackInterrupt                  , operands=1, latency=7, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=1, grp=eGrp.SPC, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x03, opcode=eOpcode.ORA, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x04, opcode=eOpcode.TSB, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.TST, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x05, opcode=eOpcode.ORA, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x06, opcode=eOpcode.ASL, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x07, opcode=eOpcode.ORA, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0x08, opcode=eOpcode.PHP, mode=eMode.StackPush                       , operands=0, latency=3, prc=ePrc.B   , src=eReg.P   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x09, opcode=eOpcode.ORA, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.PRI, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x0A, opcode=eOpcode.ASL, mode=eMode.Accumulator                     , operands=0, latency=2, prc=ePrc.M   , src=eReg.A   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x0B, opcode=eOpcode.PHD, mode=eMode.StackPush                       , operands=0, latency=4, prc=ePrc.W   , src=eReg.D   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x0C, opcode=eOpcode.TSB, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.TST, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x0D, opcode=eOpcode.ORA, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x0E, opcode=eOpcode.ASL, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x0F, opcode=eOpcode.ORA, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0x10, opcode=eOpcode.BPL, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.n   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x11, opcode=eOpcode.ORA, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0x12, opcode=eOpcode.ORA, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0x13, opcode=eOpcode.ORA, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x14, opcode=eOpcode.TRB, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.TST, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x15, opcode=eOpcode.ORA, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x16, opcode=eOpcode.ASL, mode=eMode.DirectPageIndexedX              , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x17, opcode=eOpcode.ORA, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x18, opcode=eOpcode.CLC, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x19, opcode=eOpcode.ORA, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0x1A, opcode=eOpcode.INC, mode=eMode.Accumulator                     , operands=0, latency=2, prc=ePrc.M   , src=eReg.A   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.SMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x1B, opcode=eOpcode.TCS, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.W   , src=eReg.A   , dst=eReg.S   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x1C, opcode=eOpcode.TRB, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.TST, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x1D, opcode=eOpcode.ORA, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x1E, opcode=eOpcode.ASL, mode=eMode.AbsoluteIndexedX                , operands=2, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x1F, opcode=eOpcode.ORA, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0x20, opcode=eOpcode.JSR, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.P, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x21, opcode=eOpcode.AND, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0x22, opcode=eOpcode.JSL, mode=eMode.AbsoluteLong                    , operands=3, latency=8, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.O, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=1),
           Instruction(index=0x23, opcode=eOpcode.AND, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x24, opcode=eOpcode.BIT, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x25, opcode=eOpcode.AND, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x26, opcode=eOpcode.ROL, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x27, opcode=eOpcode.AND, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0x28, opcode=eOpcode.PLP, mode=eMode.StackPull                       , operands=0, latency=4, prc=ePrc.B   , src=eReg.I   , dst=eReg.P   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x29, opcode=eOpcode.AND, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.PRI, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x2A, opcode=eOpcode.ROL, mode=eMode.Accumulator                     , operands=0, latency=2, prc=ePrc.M   , src=eReg.A   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x2B, opcode=eOpcode.PLD, mode=eMode.StackPull                       , operands=0, latency=5, prc=ePrc.W   , src=eReg.I   , dst=eReg.D   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x2C, opcode=eOpcode.BIT, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x2D, opcode=eOpcode.AND, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x2E, opcode=eOpcode.ROL, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x2F, opcode=eOpcode.AND, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0x30, opcode=eOpcode.BMI, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.N   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x31, opcode=eOpcode.AND, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0x32, opcode=eOpcode.AND, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0x33, opcode=eOpcode.AND, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x34, opcode=eOpcode.BIT, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x35, opcode=eOpcode.AND, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x36, opcode=eOpcode.ROL, mode=eMode.DirectPageIndexedX              , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x37, opcode=eOpcode.AND, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x38, opcode=eOpcode.SEC, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x39, opcode=eOpcode.AND, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0x3A, opcode=eOpcode.DEC, mode=eMode.Accumulator                     , operands=0, latency=2, prc=ePrc.M   , src=eReg.A   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.SMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x3B, opcode=eOpcode.TSC, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.W   , src=eReg.S   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x3C, opcode=eOpcode.BIT, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x3D, opcode=eOpcode.AND, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x3E, opcode=eOpcode.ROL, mode=eMode.AbsoluteIndexedX                , operands=2, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x3F, opcode=eOpcode.AND, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0x40, opcode=eOpcode.RTI, mode=eMode.StackRTI                        , operands=0, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=1, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x41, opcode=eOpcode.EOR, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0x42, opcode=eOpcode.WDM, mode=eMode.Implied                         , operands=1, latency=1, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.NOP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x43, opcode=eOpcode.EOR, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x44, opcode=eOpcode.MVP, mode=eMode.Implied                         , operands=2, latency=1, prc=ePrc.X   , src=eReg.I   , dst=eReg.I   , load=1, store=0, ctl=0, grp=eGrp.MOV, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x45, opcode=eOpcode.EOR, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x46, opcode=eOpcode.LSR, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x47, opcode=eOpcode.EOR, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0x48, opcode=eOpcode.PHA, mode=eMode.StackPush                       , operands=0, latency=3, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x49, opcode=eOpcode.EOR, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.PRI, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x4A, opcode=eOpcode.LSR, mode=eMode.Accumulator                     , operands=0, latency=2, prc=ePrc.M   , src=eReg.A   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x4B, opcode=eOpcode.PHK, mode=eMode.StackPush                       , operands=0, latency=3, prc=ePrc.B   , src=eReg.K   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x4C, opcode=eOpcode.JMP, mode=eMode.Absolute                        , operands=2, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.P, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x4D, opcode=eOpcode.EOR, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x4E, opcode=eOpcode.LSR, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x4F, opcode=eOpcode.EOR, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0x50, opcode=eOpcode.BVC, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.v   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x51, opcode=eOpcode.EOR, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0x52, opcode=eOpcode.EOR, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0x53, opcode=eOpcode.EOR, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x54, opcode=eOpcode.MVN, mode=eMode.Implied                         , operands=2, latency=1, prc=ePrc.X   , src=eReg.I   , dst=eReg.I   , load=1, store=0, ctl=0, grp=eGrp.MOV, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x55, opcode=eOpcode.EOR, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x56, opcode=eOpcode.LSR, mode=eMode.DirectPageIndexedX              , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x57, opcode=eOpcode.EOR, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x58, opcode=eOpcode.CLI, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x59, opcode=eOpcode.EOR, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0x5A, opcode=eOpcode.PHY, mode=eMode.StackPush                       , operands=0, latency=3, prc=ePrc.X   , src=eReg.Y   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x5B, opcode=eOpcode.TCD, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.W   , src=eReg.A   , dst=eReg.D   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x5C, opcode=eOpcode.JMP, mode=eMode.AbsoluteLong                    , operands=3, latency=4, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.O, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),
           Instruction(index=0x5D, opcode=eOpcode.EOR, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x5E, opcode=eOpcode.LSR, mode=eMode.AbsoluteIndexedX                , operands=2, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x5F, opcode=eOpcode.EOR, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=1, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0x60, opcode=eOpcode.RTS, mode=eMode.StackRTS                        , operands=0, latency=6, prc=ePrc.W   , src=eReg.I   , dst=eReg.I   , load=1, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x61, opcode=eOpcode.ADC, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0x62, opcode=eOpcode.PER, mode=eMode.StackProgramCounterRelative     , operands=2, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.STK, imm=0, bnk=eBnk.Z, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x63, opcode=eOpcode.ADC, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x64, opcode=eOpcode.STZ, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x65, opcode=eOpcode.ADC, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x66, opcode=eOpcode.ROR, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x67, opcode=eOpcode.ADC, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0x68, opcode=eOpcode.PLA, mode=eMode.StackPull                       , operands=0, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x69, opcode=eOpcode.ADC, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.PRI, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x6A, opcode=eOpcode.ROR, mode=eMode.Accumulator                     , operands=0, latency=2, prc=ePrc.M   , src=eReg.A   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x6B, opcode=eOpcode.RTL, mode=eMode.StackRTL                        , operands=0, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=1, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=1, stk=1),
           Instruction(index=0x6C, opcode=eOpcode.JMP, mode=eMode.AbsoluteIndirect                , operands=2, latency=5, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0x6D, opcode=eOpcode.ADC, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x6E, opcode=eOpcode.ROR, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x6F, opcode=eOpcode.ADC, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0x70, opcode=eOpcode.BVS, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.V   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x71, opcode=eOpcode.ADC, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0x72, opcode=eOpcode.ADC, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0x73, opcode=eOpcode.ADC, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x74, opcode=eOpcode.STZ, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x75, opcode=eOpcode.ADC, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x76, opcode=eOpcode.ROR, mode=eMode.DirectPageIndexedX              , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x77, opcode=eOpcode.ADC, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x78, opcode=eOpcode.SEI, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x79, opcode=eOpcode.ADC, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0x7A, opcode=eOpcode.PLY, mode=eMode.StackPull                       , operands=0, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x7B, opcode=eOpcode.TDC, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.W   , src=eReg.D   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x7C, opcode=eOpcode.JMP, mode=eMode.AbsoluteIndexedIndirect         , operands=2, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.P, add=eAdd.O16, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0x7D, opcode=eOpcode.ADC, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x7E, opcode=eOpcode.ROR, mode=eMode.AbsoluteIndexedX                , operands=2, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x7F, opcode=eOpcode.ADC, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0x80, opcode=eOpcode.BRA, mode=eMode.ProgramCounterRelative          , operands=1, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x81, opcode=eOpcode.STA, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0x82, opcode=eOpcode.BRL, mode=eMode.ProgramCounterRelativeLong      , operands=2, latency=4, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=1, stk=0),
           Instruction(index=0x83, opcode=eOpcode.STA, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x84, opcode=eOpcode.STY, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.X   , src=eReg.Y   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x85, opcode=eOpcode.STA, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x86, opcode=eOpcode.STX, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.X   , src=eReg.X   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x87, opcode=eOpcode.STA, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0x88, opcode=eOpcode.DEY, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.Y   , dst=eReg.Y   , load=0, store=0, ctl=0, grp=eGrp.SMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x89, opcode=eOpcode.BIT, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.CMP, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x8A, opcode=eOpcode.TXA, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.M   , src=eReg.X   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x8B, opcode=eOpcode.PHB, mode=eMode.StackPush                       , operands=0, latency=3, prc=ePrc.B   , src=eReg.B   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0x8C, opcode=eOpcode.STY, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.X   , src=eReg.Y   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x8D, opcode=eOpcode.STA, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x8E, opcode=eOpcode.STX, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.X   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x8F, opcode=eOpcode.STA, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0x90, opcode=eOpcode.BCC, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.c   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x91, opcode=eOpcode.STA, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=6, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0x92, opcode=eOpcode.STA, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0x93, opcode=eOpcode.STA, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x94, opcode=eOpcode.STY, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.X   , src=eReg.Y   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x95, opcode=eOpcode.STA, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x96, opcode=eOpcode.STX, mode=eMode.DirectPageIndexedY              , operands=1, latency=4, prc=ePrc.X   , src=eReg.X   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0x97, opcode=eOpcode.STA, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0x98, opcode=eOpcode.TYA, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.M   , src=eReg.Y   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x99, opcode=eOpcode.STA, mode=eMode.AbsoluteIndexedY                , operands=2, latency=5, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0x9A, opcode=eOpcode.TXS, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.W   , src=eReg.X   , dst=eReg.S   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x9B, opcode=eOpcode.TXY, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.X   , dst=eReg.Y   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x9C, opcode=eOpcode.STZ, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0x9D, opcode=eOpcode.STA, mode=eMode.AbsoluteIndexedX                , operands=2, latency=5, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x9E, opcode=eOpcode.STZ, mode=eMode.AbsoluteIndexedX                , operands=2, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0x9F, opcode=eOpcode.STA, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.A   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0xA0, opcode=eOpcode.LDY, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=0, store=0, ctl=0, grp=eGrp.PLL, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA1, opcode=eOpcode.LDA, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0xA2, opcode=eOpcode.LDX, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.PLL, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA3, opcode=eOpcode.LDA, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA4, opcode=eOpcode.LDY, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA5, opcode=eOpcode.LDA, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA6, opcode=eOpcode.LDX, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA7, opcode=eOpcode.LDA, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0xA8, opcode=eOpcode.TAY, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.A   , dst=eReg.Y   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xA9, opcode=eOpcode.LDA, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.PRI, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xAA, opcode=eOpcode.TAX, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.A   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xAB, opcode=eOpcode.PLB, mode=eMode.StackPull                       , operands=0, latency=4, prc=ePrc.B   , src=eReg.I   , dst=eReg.B   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0xAC, opcode=eOpcode.LDY, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xAD, opcode=eOpcode.LDA, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xAE, opcode=eOpcode.LDX, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xAF, opcode=eOpcode.LDA, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0xB0, opcode=eOpcode.BCS, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.C   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xB1, opcode=eOpcode.LDA, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0xB2, opcode=eOpcode.LDA, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0xB3, opcode=eOpcode.LDA, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0xB4, opcode=eOpcode.LDY, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xB5, opcode=eOpcode.LDA, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xB6, opcode=eOpcode.LDX, mode=eMode.DirectPageIndexedY              , operands=1, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0xB7, opcode=eOpcode.LDA, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0xB8, opcode=eOpcode.CLV, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xB9, opcode=eOpcode.LDA, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0xBA, opcode=eOpcode.TSX, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.S   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xBB, opcode=eOpcode.TYX, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.Y   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.TXR, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xBC, opcode=eOpcode.LDY, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xBD, opcode=eOpcode.LDA, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xBE, opcode=eOpcode.LDX, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0xBF, opcode=eOpcode.LDA, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0xC0, opcode=eOpcode.CPY, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=0, store=0, ctl=0, grp=eGrp.CMP, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC1, opcode=eOpcode.CMP, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0xC2, opcode=eOpcode.REP, mode=eMode.Immediate                       , operands=1, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC3, opcode=eOpcode.CMP, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC4, opcode=eOpcode.CPY, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC5, opcode=eOpcode.CMP, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC6, opcode=eOpcode.DEC, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC7, opcode=eOpcode.CMP, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0xC8, opcode=eOpcode.INY, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.Y   , dst=eReg.Y   , load=0, store=0, ctl=0, grp=eGrp.SMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xC9, opcode=eOpcode.CMP, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.CMP, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xCA, opcode=eOpcode.DEX, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.X   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.SMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xCB, opcode=eOpcode.WAI, mode=eMode.Implied                         , operands=0, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.SPC, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xCC, opcode=eOpcode.CPY, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.Y   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xCD, opcode=eOpcode.CMP, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xCE, opcode=eOpcode.DEC, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xCF, opcode=eOpcode.CMP, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0xD0, opcode=eOpcode.BNE, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.z   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xD1, opcode=eOpcode.CMP, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0xD2, opcode=eOpcode.CMP, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0xD3, opcode=eOpcode.CMP, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0xD4, opcode=eOpcode.PEI, mode=eMode.StackDirectPageIndirect         , operands=1, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.STK, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=1),
           Instruction(index=0xD5, opcode=eOpcode.CMP, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xD6, opcode=eOpcode.DEC, mode=eMode.DirectPageIndexedX              , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xD7, opcode=eOpcode.CMP, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0xD8, opcode=eOpcode.CLD, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xD9, opcode=eOpcode.CMP, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0xDA, opcode=eOpcode.PHX, mode=eMode.StackPush                       , operands=0, latency=3, prc=ePrc.X   , src=eReg.X   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.PHS, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0xDB, opcode=eOpcode.STP, mode=eMode.Implied                         , operands=0, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.SPC, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xDC, opcode=eOpcode.JMP, mode=eMode.AbsoluteIndirectLong            , operands=2, latency=6, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0xDD, opcode=eOpcode.CMP, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xDE, opcode=eOpcode.DEC, mode=eMode.AbsoluteIndexedX                , operands=2, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xDF, opcode=eOpcode.CMP, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

           Instruction(index=0xE0, opcode=eOpcode.CPX, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.CMP, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE1, opcode=eOpcode.SBC, mode=eMode.DirectPageIndexedIndirectX      , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=1, lng=0, stk=0),
           Instruction(index=0xE2, opcode=eOpcode.SEP, mode=eMode.Immediate                       , operands=1, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE3, opcode=eOpcode.SBC, mode=eMode.StackRelative                   , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE4, opcode=eOpcode.CPX, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE5, opcode=eOpcode.SBC, mode=eMode.DirectPage                      , operands=1, latency=3, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE6, opcode=eOpcode.INC, mode=eMode.DirectPage                      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE7, opcode=eOpcode.SBC, mode=eMode.DirectPageIndirectLong          , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=1, stk=0),
           Instruction(index=0xE8, opcode=eOpcode.INX, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.X   , src=eReg.X   , dst=eReg.X   , load=0, store=0, ctl=0, grp=eGrp.SMP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xE9, opcode=eOpcode.SBC, mode=eMode.Immediate                       , operands=1, latency=2, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.PRI, imm=1, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xEA, opcode=eOpcode.NOP, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.NOP, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xEB, opcode=eOpcode.XBA, mode=eMode.Implied                         , operands=0, latency=3, prc=ePrc.B   , src=eReg.I   , dst=eReg.A   , load=0, store=0, ctl=0, grp=eGrp.XCH, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xEC, opcode=eOpcode.CPX, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.CMP, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xED, opcode=eOpcode.SBC, mode=eMode.Absolute                        , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xEE, opcode=eOpcode.INC, mode=eMode.Absolute                        , operands=2, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xEF, opcode=eOpcode.SBC, mode=eMode.AbsoluteLong                    , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=1, stk=0),

           Instruction(index=0xF0, opcode=eOpcode.BEQ, mode=eMode.ProgramCounterRelative          , operands=1, latency=2, prc=ePrc.B   , src=eReg.Z   , dst=eReg.I   , load=0, store=0, ctl=1, grp=eGrp.CBR, imm=0, bnk=eBnk.P, add=eAdd.PCR, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xF1, opcode=eOpcode.SBC, mode=eMode.DirectPageIndirectIndexedY      , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=0, stk=0),
           Instruction(index=0xF2, opcode=eOpcode.SBC, mode=eMode.DirectPageIndirect              , operands=1, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.I, ind=1, lng=0, stk=0),
           Instruction(index=0xF3, opcode=eOpcode.SBC, mode=eMode.StackRelativeIndirectIndexedY   , operands=1, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.SPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0xF4, opcode=eOpcode.PEA, mode=eMode.StackAbsolute                   , operands=2, latency=5, prc=ePrc.W   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=0, grp=eGrp.STK, imm=0, bnk=eBnk.Z, add=eAdd.SMI, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0xF5, opcode=eOpcode.SBC, mode=eMode.DirectPageIndexedX              , operands=1, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xF6, opcode=eOpcode.INC, mode=eMode.DirectPageIndexedX              , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xF7, opcode=eOpcode.SBC, mode=eMode.DirectPageIndirectLongIndexedY  , operands=1, latency=6, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.DPR, mod=eMod.P, ind=1, lng=1, stk=0),
           Instruction(index=0xF8, opcode=eOpcode.SED, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.STS, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xF9, opcode=eOpcode.SBC, mode=eMode.AbsoluteIndexedY                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.Y, ind=0, lng=0, stk=0),
           Instruction(index=0xFA, opcode=eOpcode.PLX, mode=eMode.StackPull                       , operands=0, latency=4, prc=ePrc.X   , src=eReg.I   , dst=eReg.X   , load=1, store=0, ctl=0, grp=eGrp.PLL, imm=0, bnk=eBnk.Z, add=eAdd.SPL, mod=eMod.I, ind=0, lng=0, stk=1),
           Instruction(index=0xFB, opcode=eOpcode.XCE, mode=eMode.Implied                         , operands=0, latency=2, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=0, ctl=0, grp=eGrp.XCH, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.I, ind=0, lng=0, stk=0),
           Instruction(index=0xFC, opcode=eOpcode.JSR, mode=eMode.AbsoluteIndexedIndirect         , operands=2, latency=8, prc=ePrc.B   , src=eReg.I   , dst=eReg.I   , load=0, store=1, ctl=1, grp=eGrp.JMP, imm=0, bnk=eBnk.P, add=eAdd.O16, mod=eMod.X, ind=1, lng=0, stk=1),
           Instruction(index=0xFD, opcode=eOpcode.SBC, mode=eMode.AbsoluteIndexedX                , operands=2, latency=4, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xFE, opcode=eOpcode.INC, mode=eMode.AbsoluteIndexedX                , operands=2, latency=7, prc=ePrc.M   , src=eReg.I   , dst=eReg.I   , load=1, store=1, ctl=0, grp=eGrp.RMW, imm=0, bnk=eBnk.D, add=eAdd.O16, mod=eMod.X, ind=0, lng=0, stk=0),
           Instruction(index=0xFF, opcode=eOpcode.SBC, mode=eMode.AbsoluteLongIndexedX            , operands=3, latency=5, prc=ePrc.M   , src=eReg.I   , dst=eReg.A   , load=1, store=0, ctl=0, grp=eGrp.PRI, imm=0, bnk=eBnk.Z, add=eAdd.O16, mod=eMod.X, ind=0, lng=1, stk=0),

          ]

def main():
  parser = argparse.ArgumentParser(description='Write decoder to file.')
  parser.add_argument('file', help='file to write out')
  args = parser.parse_args()      
  
  if os.path.exists(args.file):
    if os.path.isfile(args.file):
      copyfile(args.file, args.file+'.bak')
    else:
      print args.file + ' not a file.'
      sys.exit()
                  
  with open(args.file, 'w') as f: 
    f.write('; This .COE file specifies initialization values for a block \n')
    f.write('; memory of depth=256, and width=32. In this case, values are \n')
    f.write('; specified in hexadecimal format.\n')
    f.write('memory_initialization_radix=2;\n')
    f.write('memory_initialization_vector=\n')
    
    for i in xrange(0x100):
      if i != 0x00: f.write(',\n')
      if len(mxTable) <= i:
        f.write('11111111111111111111111111111111')
      else:
        f.write(mxTable[i].to_string())
        
    f.write(';\n')
    f.close()

  #  str = "{0:07b}".format(self.Opcode) + "{0:05b}".format(self.Mode) + "{0:02b}".format(self.Operands) + "{0:04b}".format(self.Latency) + "{0:02b}".format(self.Prc) + "{0:03b}".format(self.Src) + "{0:03b}".format(self.Dst) + "{0:06b}".format(0)
  with open('regs.out', 'w') as f:
    f.write(Instruction.defines())
    f.write('\n')
        
if __name__ == "__main__":
  main()
