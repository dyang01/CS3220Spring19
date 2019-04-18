module Project(
  input        CLOCK_50,
  input        RESET_N,
  input  [3:0] KEY,
  input  [9:0] SW,
  output [6:0] HEX0,
  output [6:0] HEX1,
  output [6:0] HEX2,
  output [6:0] HEX3,
  output [6:0] HEX4,
  output [6:0] HEX5,
  output [9:0] LEDR
);

  parameter DBITS    = 32;
  parameter INSTSIZE = 32'd4;
  parameter INSTBITS = 32;
  parameter REGNOBITS = 4;
  parameter REGWORDS = (1 << REGNOBITS);
  parameter SYSREGNOBITS = 2;
  parameter SYSREGWORDS = (1 << SYSREGNOBITS);
  parameter IMMBITS  = 16;
  parameter INTRPC	 = 32'h10;
  parameter STARTPC  = 32'h100;
  parameter ADDRHEX  = 32'hFFFFF000;
  parameter ADDRLEDR = 32'hFFFFF020;
  parameter ADDRKEY  = 32'hFFFFF080;
  parameter ADDRSW   = 32'hFFFFF090;
  parameter ADDRTIMER = 32'hFFFFF100;

  // Change this to fmedian2.mif before submitting
  parameter IMEMINITFILE = "fmedian2.mif";
  // parameter IMEMINITFILE = "fmedian2.mif";
  
  parameter IMEMADDRBITS = 16;
  parameter IMEMWORDBITS = 2;
  parameter IMEMWORDS  = (1 << (IMEMADDRBITS - IMEMWORDBITS));
  parameter DMEMADDRBITS = 16;
  parameter DMEMWORDBITS = 2;
  parameter DMEMWORDS  = (1 << (DMEMADDRBITS - DMEMWORDBITS));
   
  parameter OP1BITS  = 6;
  parameter OP1_ALUR = 6'b000000;
  parameter OP1_BEQ  = 6'b001000;
  parameter OP1_BLT  = 6'b001001;
  parameter OP1_BLE  = 6'b001010;
  parameter OP1_BNE  = 6'b001011;
  parameter OP1_JAL  = 6'b001100;
  parameter OP1_LW   = 6'b010010;
  parameter OP1_SW   = 6'b011010;
  parameter OP1_ADDI = 6'b100000;
  parameter OP1_ANDI = 6'b100100;
  parameter OP1_ORI  = 6'b100101;
  parameter OP1_XORI = 6'b100110;
  parameter OP1_SYS  = 6'b111111;
  
  // Add parameters for secondary opcode values 
  /* OP2 */
  parameter OP2BITS  = 8;
  parameter OP2_EQ   = 8'b00001000;
  parameter OP2_LT   = 8'b00001001;
  parameter OP2_LE   = 8'b00001010;
  parameter OP2_NE   = 8'b00001011;
  parameter OP2_ADD  = 8'b00100000;
  parameter OP2_AND  = 8'b00100100;
  parameter OP2_OR   = 8'b00100101;
  parameter OP2_XOR  = 8'b00100110;
  parameter OP2_SUB  = 8'b00101000;
  parameter OP2_NAND = 8'b00101100;
  parameter OP2_NOR  = 8'b00101101;
  parameter OP2_NXOR = 8'b00101110;
  parameter OP2_RSHF = 8'b00110000;
  parameter OP2_LSHF = 8'b00110001;
  parameter OP2_RETI = 8'b00000001;
  parameter OP2_RSR  = 8'b00000010;
  parameter OP2_WRS  = 8'b00000011;
  
  parameter HEXBITS  = 24;
  parameter LEDRBITS = 10;
  parameter KEYBITS = 4;

  parameter TIMER_ID  = 32'd0;
  parameter KEY_ID    = 32'd1;
  parameter SWITCH_ID = 32'd2;
 
  //*** PLL ***//
  // The reset signal comes from the reset button on the DE0-CV board
  // RESET_N is active-low, so we flip its value ("reset" is active-high)
  // The PLL is wired to produce clk and locked signals for our logic
  wire clk;
  wire locked;
  wire reset;

  Pll myPll(
    .refclk (CLOCK_50),
    .rst      (!RESET_N),
    .outclk_0   (clk),
    .locked     (locked)
  );

  assign reset = !locked;

  wire intr_key, intr_sw, intr_timer;

  //*** FETCH STAGE ***//
  // The PC register and update logic
  wire [DBITS-1:0] pcplus_FE;   //PC+4
  wire [DBITS-1:0] pcpred_FE;   //PC+4 also for p3
  wire [DBITS-1:0] inst_FE_w;   //instruction wire that goes to ID/RR
  wire stall_pipe;
  wire mispred_EX_w;
  wire reti;
  
  reg [DBITS-1:0] pcgood_EX;
  reg [DBITS-1:0] PC_FE;
  reg [INSTBITS-1:0] inst_FE;   //the actual instruction reg
  // I-MEM
  (* ram_init_file = IMEMINITFILE *)
  reg [DBITS-1:0] imem [IMEMWORDS-1:0];
  reg mispred_EX;
  
  // System register file
  wire [DBITS-1:0] intr_ret_addr; // Interrupt return address
  reg [DBITS-1:0] sys_regs [SYSREGWORDS-1:0]; // 4 registers of width 32
  reg NOP_ID;
  reg NOP_EX;
  reg NOP_MEM;
  reg [DBITS-1:0] PC_EX;
  reg [DBITS-1:0] PC_MEM;

  // This statement is used to initialize the I-MEM
  // during simulation using Model-Sim
  initial begin
   $readmemh("fmedian2.hex", imem);
  end
    
  assign inst_FE_w = imem[PC_FE[IMEMADDRBITS-1:IMEMWORDBITS]];  //imem[upper bits of PC_FE]
  
  always @ (posedge clk or posedge reset) begin
    if(reset)
      PC_FE <= STARTPC;
    else if (IRQ)
    	PC_FE <= INTRPC; 			//PC_FE is 0x10.
    else if(mispred_EX)
      PC_FE <= pcgood_EX;   //pcgood set to place that branch would go to
    else if(!stall_pipe)
      PC_FE <= pcpred_FE; //for normal execution
    else if(reti)
      PC_FE <= sys_regs[2];
    else
      PC_FE <= PC_FE;	//for bubbles
  end

  // This is the value of "incremented PC", computed in the FE stage
  assign pcplus_FE = PC_FE + INSTSIZE;
  // This is the predicted value of the PC that we use to fetch the next instruction
  assign pcpred_FE = pcplus_FE;

  // FE_latch
  always @ (posedge clk or posedge reset) begin
    if(reset)
      inst_FE <= {INSTBITS{1'b0}};
    else if (IRQ)
      inst_FE <= {INSTBITS{1'b0}};
    else if (mispred_EX)
    	inst_FE <= {INSTBITS{1'b0}};
    else if (stall_pipe)
    	inst_FE <= inst_FE;
    else
    	inst_FE <= inst_FE_w; //idk
  end


  //*** DECODE STAGE ***//
  wire [OP1BITS-1:0] op1_ID_w;
  wire [OP2BITS-1:0] op2_ID_w;
  wire [IMMBITS-1:0] imm_ID_w;
  wire [REGNOBITS-1:0] rd_ID_w;
  wire [REGNOBITS-1:0] rs_ID_w;
  wire [REGNOBITS-1:0] rt_ID_w;
  wire [SYSREGNOBITS-1:0] srd_ID_w;
  wire [SYSREGNOBITS-1:0] srs_ID_w;
  // Two read ports, always using rs and rt for register numbers
  wire [DBITS-1:0] regval1_ID_w;
  wire [DBITS-1:0] regval2_ID_w;
  // wire [DBITS-1:0] sysregval1_ID_w;
  wire [DBITS-1:0] sysregval2_ID_w;
  wire [DBITS-1:0] sxt_imm_ID_w;  //same as imm_ID_w but sext'd
  wire is_br_ID_w;
  wire is_jmp_ID_w;
  wire rd_mem_ID_w;
  wire wr_mem_ID_w;
  wire wr_reg_ID_w;
  wire is_sys_inst_ID_w;
  wire wr_sys_rd_ID_w;
  wire [4:0] ctrlsig_ID_w;
  wire [REGNOBITS-1:0] wregno_ID_w;
  wire wr_reg_EX_w;
  wire wr_reg_MEM_w;
  
  // Register file
  reg [DBITS-1:0] PC_ID;
  reg [DBITS-1:0] regs [REGWORDS-1:0];  //16 registers of width 32
  reg signed [DBITS-1:0] regval1_ID;
  reg signed [DBITS-1:0] regval2_ID;
  reg signed [DBITS-1:0] sysregval_ID;
  reg signed [DBITS-1:0] immval_ID;
  reg [OP1BITS-1:0] op1_ID;
  reg [OP2BITS-1:0] op2_ID;
  reg [4:0] ctrlsig_ID;
  reg [REGNOBITS-1:0] wregno_ID;
  // Declared here for stall check
  reg [REGNOBITS-1:0] wregno_EX;
  reg [REGNOBITS-1:0] wregno_MEM;
  reg [INSTBITS-1:0] inst_ID;
  reg ctrlsig_MEM;

  // DONE: Specify signals such as op*_ID_w, imm_ID_w, r*_ID_w
  assign op1_ID_w = inst_FE[31:26];
  assign op2_ID_w = inst_FE[25:18];
  assign imm_ID_w = inst_FE[23:8];
  assign rd_ID_w = inst_FE[11:8];
  assign rs_ID_w = inst_FE[7:4];
  assign rt_ID_w = inst_FE[3:0];
  assign srd_ID_w = inst_FE[19:18];
  assign srs_ID_w = inst_FE[17:16];

  // Read register values
  assign regval1_ID_w = regs[rs_ID_w];
  assign regval2_ID_w = regs[rt_ID_w];
  // assign sysregval1_ID_w = sys_regs[srd_ID_w];
  assign sysregval2_ID_w = sys_regs[srs_ID_w];



  // Sign extension
  SXT mysxt (.IN(imm_ID_w), .OUT(sxt_imm_ID_w));

  // DONE: Specify control signals such as is_br_ID_w, is_jmp_ID_w, rd_mem_ID_w, etc.
  // You may add or change control signals if needed
  assign is_br_ID_w = (op1_ID_w[5:2] == 4'b0010); //see lecture 2 slide 24
  assign is_jmp_ID_w = (op1_ID_w == 6'b001100); //assuming this means JMP == JAL
  assign rd_mem_ID_w = (op1_ID_w[5:3] == 3'b010); //see lecture 2 slide 24
  assign wr_mem_ID_w = (op1_ID_w[5:3] == 3'b011); //see lec 2 slide 24
  assign wr_reg_ID_w = (op1_ID_w == 6'b000000) || (op1_ID_w == 6'b001100) ||
    (op1_ID_w == 6'b010010) || (op1_ID_w[5:3] == 3'b100); //includes EXT, JAL, LW, ALUI
  assign is_sys_inst_ID_w = (op1_ID_w == 6'b111111);
  assign wr_sys_rd_ID_w = (op2_ID_w == OP2_RSR);

  assign ctrlsig_ID_w = {is_br_ID_w, is_jmp_ID_w, rd_mem_ID_w, wr_mem_ID_w, wr_reg_ID_w};
  
  // TODO: Specify stall condition
  // assign stall_pipe = ... ;

  reg [INSTBITS-1:0] inst_MEM; /* This is for debugging */
  reg [INSTBITS-1:0] inst_EX; /* This is for debugging */
  reg is_sys_inst_ID;
  reg is_reti_ID;
  reg is_reti_EX;

  wire ext_inst = op1_ID_w[5:3] == 3'b000;
  wire br_inst = op1_ID_w[5:2] == 4'b0010;
  wire sw_inst = op1_ID_w[5:2] == 4'b0110;

  wire [5:0] op_mem = inst_MEM[31:26];
  wire rt_write_mem = (op_mem == OP1_JAL) || (op_mem == OP1_LW) || (op_mem[5:3] == 3'b100);
  wire [3:0] rt_write_mem_regno = inst_MEM[3:0];
  wire rd_write_mem = op_mem[5:3] == 3'b000;
  wire [3:0] rd_write_mem_regno = inst_MEM[11:8];
  wire stall_from_MEM2 = (rt_write_mem &&
  		(rt_write_mem_regno == rs_ID_w || (rt_write_mem_regno == rt_ID_w && (ext_inst || br_inst || sw_inst)))) ||
  	(rd_write_mem &&
  	(rd_write_mem_regno == rs_ID_w || (rd_write_mem_regno == rt_ID_w && (ext_inst || br_inst || sw_inst)))) &&
  	rt_write_mem_regno != 0 && rd_write_mem_regno != 0;

  wire [5:0] op_ex = inst_EX[31:26];
  wire rt_write_ex = op_ex == OP1_JAL || op_ex == OP1_LW || op_ex[5:3] == 3'b100;
  wire [3:0] rt_write_ex_regno = inst_EX[3:0];
  wire rd_write_ex = op_ex[5:3] == 3'b000;
  wire [3:0] rd_write_ex_regno = inst_EX[11:8];
  wire stall_from_EX2 = (rt_write_ex &&
  		(rt_write_ex_regno == rs_ID_w || (rt_write_ex_regno == rt_ID_w && (ext_inst || br_inst || sw_inst)))) ||
  	(rd_write_ex &&
  	(rd_write_ex_regno == rs_ID_w || (rd_write_ex_regno == rt_ID_w && (ext_inst || br_inst || sw_inst)))) &&
  	rt_write_ex_regno != 0 && rd_write_ex_regno != 0;

  wire [5:0] op_id = inst_ID[31:26];
  wire rt_write_id = op_id == OP1_JAL || op_id == OP1_LW || op_id[5:3] == 3'b100;
  wire [3:0] rt_write_id_regno = inst_ID[3:0];
  wire rd_write_id = op_id[5:3] == 3'b000;
  wire [3:0] rd_write_id_regno = inst_ID[11:8];
  wire stall_from_ID2 = (rt_write_id &&
  		(rt_write_id_regno == rs_ID_w || (rt_write_id_regno == rt_ID_w && (ext_inst || br_inst || sw_inst)))) ||
  	(rd_write_id &&
  	(rd_write_id_regno == rs_ID_w || (rd_write_id_regno == rt_ID_w && (ext_inst || br_inst || sw_inst)))) &&
  	rt_write_id_regno != 0 && rd_write_id_regno != 0;

  wire ignore_stall_MEM;
  wire ignore_stall_EX;
  wire ignore_stall_ID;
  wire take_fwd_regval1_w;
  wire take_fwd_regval2_w;
  wire [DBITS-1:0] fwd_regval1_w;
  wire [DBITS-1:0] fwd_regval2_w;
  wire is_reti_ID_w;

  assign stall_pipe = (stall_from_MEM2 && !ignore_stall_MEM) || (stall_from_EX2 && !ignore_stall_EX)
    || (stall_from_ID2 && !ignore_stall_ID) || is_reti_EX;
  assign wregno_ID_w = is_sys_inst_ID_w ? (wr_sys_rd_ID_w ? rd_ID_w : srd_ID_w) : (
  (op1_ID_w[5:3] == 3'b000) ? rd_ID_w : rt_ID_w); //assume only EXT has wregno == rd.
  assign is_reti_ID_w = (op1_ID_w == OP1_SYS) && (op2_ID_w == OP2_RETI);


  // ID_latch
  always @ (posedge clk or posedge reset) begin
    if(reset) begin
      PC_ID  <= {DBITS{1'b0}};
      inst_ID  <= {INSTBITS{1'b0}};
      op1_ID   <= {OP1BITS{1'b0}};
      op2_ID   <= {OP2BITS{1'b0}};
      regval1_ID  <= {DBITS{1'b0}};
      regval2_ID  <= {DBITS{1'b0}};
      sysregval_ID <= {DBITS{1'b0}};
      wregno_ID  <= {REGNOBITS{1'b0}};
      ctrlsig_ID <= 5'h0;
      immval_ID <= {DBITS{1'b0}}; //added
      NOP_ID <= 1'b1;
      is_sys_inst_ID <= 1'b0;
      is_reti_ID <= 1'b0;
    end else if(IRQ) begin
      PC_ID  <= {DBITS{1'b0}};
      inst_ID  <= {INSTBITS{1'b0}};
      op1_ID   <= {OP1BITS{1'b0}};
      op2_ID   <= {OP2BITS{1'b0}};
      regval1_ID  <= {DBITS{1'b0}};
      regval2_ID  <= {DBITS{1'b0}};
      sysregval_ID <= {DBITS{1'b0}};
      wregno_ID  <= {REGNOBITS{1'b0}};
      ctrlsig_ID <= 5'h0;
      immval_ID <= {DBITS{1'b0}}; //added
      NOP_ID <= 1'b1;
      is_sys_inst_ID <= 1'b0;
      is_reti_ID <= 1'b0;
    end else if(mispred_EX) begin
    	PC_ID  <= {DBITS{1'b0}};
      inst_ID  <= {INSTBITS{1'b0}};
      op1_ID   <= {OP1BITS{1'b0}};
      op2_ID   <= {OP2BITS{1'b0}};
      regval1_ID  <= {DBITS{1'b0}};
      regval2_ID  <= {DBITS{1'b0}};
      sysregval_ID <= {DBITS{1'b0}};
      wregno_ID  <= {REGNOBITS{1'b0}};
      ctrlsig_ID <= 5'h0;
      immval_ID <= {DBITS{1'b0}}; //added
      NOP_ID <= 1'b1;
      is_sys_inst_ID <= 1'b0;
      is_reti_ID <= 1'b0;
    end else if(stall_pipe) begin
    	PC_ID  <= {DBITS{1'b0}};
      inst_ID  <= {INSTBITS{1'b0}};
      op1_ID   <= {OP1BITS{1'b0}};
      op2_ID   <= {OP2BITS{1'b0}};
      regval1_ID  <= {DBITS{1'b0}};
      regval2_ID  <= {DBITS{1'b0}};
      sysregval_ID <= {DBITS{1'b0}};
      wregno_ID  <= {REGNOBITS{1'b0}};
      ctrlsig_ID <= 5'h0;
      immval_ID <= {DBITS{1'b0}}; //added
      NOP_ID <= 1'b1;
      is_sys_inst_ID <= 1'b0;
      is_reti_ID <= 1'b0;
    end else begin
      PC_ID  <= PC_FE;
      inst_ID <= inst_FE;
      op1_ID   <= op1_ID_w;
      op2_ID   <= op2_ID_w;
      regval1_ID <= take_fwd_regval1_w ? fwd_regval1_w : regval1_ID_w;
      regval2_ID <= take_fwd_regval2_w ? fwd_regval2_w : regval2_ID_w;
      sysregval_ID <= wr_sys_rd_ID_w ? sysregval2_ID_w : regval1_ID_w;
      wregno_ID  <= wregno_ID_w;
      ctrlsig_ID <= ctrlsig_ID_w;
      immval_ID <= sxt_imm_ID_w;
      NOP_ID <= 1'b0;
      is_sys_inst_ID <= is_sys_inst_ID_w;
      is_reti_ID <= is_reti_ID_w;
    end
  end

  // ----------------------------------------------------------------------------------
  // START PHILIP'S WORK --------------------------------------------------------------
  // ----------------------------------------------------------------------------------


  //*** AGEN/EXEC STAGE ***//

  wire is_br_EX_w;
  wire is_jmp_EX_w;
  wire rd_mem_EX_w; //added wire
  wire wr_mem_EX_w; //added wire
  wire [DBITS-1:0] pcgood_EX_w;
  wire [2:0] ctrlsig_EX_w;  //added wire

  // reg [INSTBITS-1:0] inst_EX; /* This is for debugging */
  reg br_cond_EX;
  reg [2:0] ctrlsig_EX;
  // Note that aluout_EX_r is declared as reg, but it is output signal from combi logic
  reg signed [DBITS-1:0] aluout_EX_r;
  reg [DBITS-1:0] aluout_EX;
  reg [DBITS-1:0] regval2_EX;
  reg [DBITS-1:0] sysregval_EX;
  reg rd_sys_EX_r;
  reg wr_sys_EX_r;
  reg rd_sys_EX;
  reg wr_sys_EX;
  reg is_sys_inst_EX;

  always @ (op1_ID or regval1_ID or regval2_ID) begin
    case (op1_ID)
      OP1_BEQ : br_cond_EX <= (regval1_ID == regval2_ID);
      OP1_BLT : br_cond_EX <= (regval1_ID < regval2_ID);
      OP1_BLE : br_cond_EX <= (regval1_ID <= regval2_ID);
      OP1_BNE : br_cond_EX <= (regval1_ID != regval2_ID);
      default : br_cond_EX <= 1'b0;
    endcase
  end

  always @ (op1_ID or op2_ID or regval1_ID or regval2_ID or immval_ID) begin
    if(op1_ID == OP1_ALUR)
      case (op2_ID)
        OP2_EQ    : aluout_EX_r = {31'b0, regval1_ID == regval2_ID};
        OP2_LT    : aluout_EX_r = {31'b0, regval1_ID < regval2_ID};
        OP2_LE    : aluout_EX_r = {31'b0, regval1_ID <= regval2_ID};
        OP2_NE    : aluout_EX_r = {31'b0, regval1_ID != regval2_ID};
        OP2_ADD   : aluout_EX_r = regval1_ID + regval2_ID;
        OP2_AND   : aluout_EX_r = regval1_ID & regval2_ID;
        OP2_OR    : aluout_EX_r = regval1_ID | regval2_ID;
        OP2_XOR   : aluout_EX_r = regval1_ID ^ regval2_ID;
        OP2_SUB   : aluout_EX_r = regval1_ID - regval2_ID;
        OP2_NAND  : aluout_EX_r = ~(regval1_ID & regval2_ID);
        OP2_NOR   : aluout_EX_r = ~(regval1_ID | regval2_ID);
        OP2_NXOR  : aluout_EX_r = ~(regval1_ID ^ regval2_ID);
        OP2_RSHF  : aluout_EX_r = regval1_ID >>> regval2_ID;
        OP2_LSHF  : aluout_EX_r = regval1_ID << regval2_ID;
        default   : aluout_EX_r = {DBITS{1'b0}};
      endcase
    else if(op1_ID == OP1_LW || op1_ID == OP1_SW || op1_ID == OP1_ADDI)
      aluout_EX_r = regval1_ID + immval_ID;
    else if(op1_ID == OP1_ANDI)
      aluout_EX_r = regval1_ID & immval_ID;
    else if(op1_ID == OP1_ORI)
      aluout_EX_r = regval1_ID | immval_ID;
    else if(op1_ID == OP1_XORI)
      aluout_EX_r = regval1_ID ^ immval_ID;
    else if(op1_ID == OP1_JAL)
    	aluout_EX_r = PC_ID;
    else if(op1_ID == OP1_SYS) begin
      case (op2_ID)
        OP2_RETI  : begin
                      // sys_regs[0][0] <= sys_regs[0][1];
                      // reti <= 1;
                    end
        OP2_RSR   : begin
                      rd_sys_EX_r = 1;
                    end
        OP2_WRS   : begin
                      wr_sys_EX_r = 1;
                    end
      endcase
    end else
      aluout_EX_r = {DBITS{1'b0}};
  end

  // assign reti = (op1_ID_w == OP1_SYS) && (op2_ID_w == OP2_RETI);

  assign is_br_EX_w = ctrlsig_ID[4];
  assign is_jmp_EX_w = ctrlsig_ID[3];
  assign rd_mem_EX_w = ctrlsig_ID[2];
  assign wr_reg_EX_w = ctrlsig_ID[0];

  assign ctrlsig_EX_w = { ctrlsig_ID[2], ctrlsig_ID[1], ctrlsig_ID[0] };
  
  // TODO: Specify signals such as mispred_EX_w, pcgood_EX_w
  assign mispred_EX_w = is_jmp_EX_w || (is_br_EX_w && br_cond_EX);
  assign pcgood_EX_w = (op1_ID == OP1_JAL) ? (regval1_ID + 4*immval_ID) : (PC_ID + 4*immval_ID);

  // EX_latch
  always @ (posedge clk or posedge reset) begin
    if(reset) begin
      inst_EX  <= {INSTBITS{1'b0}};
      aluout_EX  <= {DBITS{1'b0}};
      wregno_EX  <= {REGNOBITS{1'b0}};
      ctrlsig_EX <= 3'h0;
      mispred_EX <= 1'b0;
      pcgood_EX  <= {DBITS{1'b0}};
      regval2_EX  <= {DBITS{1'b0}};
      sysregval_EX <= {DBITS{1'b0}};
      NOP_EX <= 1'b1;
      PC_EX <= {DBITS{1'b0}};
      wr_sys_EX <= 1'b0;
      rd_sys_EX <= 1'b0;
      is_sys_inst_EX <= 1'b0;
      is_reti_EX <= 1'b0;
    end else if(IRQ) begin
      inst_EX  <= {INSTBITS{1'b0}};
      aluout_EX  <= {DBITS{1'b0}};
      wregno_EX  <= {REGNOBITS{1'b0}};
      ctrlsig_EX <= 3'h0;
      mispred_EX <= 1'b0;
      pcgood_EX  <= {DBITS{1'b0}};
      regval2_EX  <= {DBITS{1'b0}};
      sysregval_EX <= {DBITS{1'b0}};
      NOP_EX <= 1'b1;
      PC_EX <= {DBITS{1'b0}};
      wr_sys_EX <= 1'b0;
      rd_sys_EX <= 1'b0;
      is_sys_inst_EX <= 1'b0;
      is_reti_EX <= 1'b0;
    end else if(mispred_EX) begin
      inst_EX  <= {INSTBITS{1'b0}};
      aluout_EX  <= {DBITS{1'b0}};
      wregno_EX  <= {REGNOBITS{1'b0}};
      ctrlsig_EX <= 3'h0;
      mispred_EX <= 1'b0;
      pcgood_EX  <= {DBITS{1'b0}};
      regval2_EX  <= {DBITS{1'b0}};
      sysregval_EX <= {DBITS{1'b0}};
      NOP_EX <= 1'b1;
      PC_EX <= {DBITS{1'b0}};
      wr_sys_EX <= 1'b0;
      rd_sys_EX <= 1'b0;
      is_sys_inst_EX <= 1'b0;
      is_reti_EX <= 1'b0;
    end else begin
    // TODO: Specify EX latches
      inst_EX <= inst_ID;
      aluout_EX <= aluout_EX_r;
      wregno_EX <= wregno_ID;
      ctrlsig_EX <= ctrlsig_EX_w;
      mispred_EX <= mispred_EX_w;
      pcgood_EX <= pcgood_EX_w;
      regval2_EX <= regval2_ID;
      sysregval_EX <= sysregval_ID;
      NOP_EX <= 1'b0;
      PC_EX <= PC_ID;
      wr_sys_EX <= wr_sys_EX_r;
      rd_sys_EX <= rd_sys_EX_r;
      is_sys_inst_EX <= is_sys_inst_ID;
      is_reti_EX <= is_reti_ID;
    end
  end
  

  //*** MEM STAGE ***//

  wire rd_mem_MEM_w;
  wire wr_mem_MEM_w;
  
  wire [DBITS-1:0] memaddr_MEM_w;
  wire [DBITS-1:0] rd_val_MEM_w;

  reg [DBITS-1:0] regval_MEM;
  // D-MEM
  (* ram_init_file = IMEMINITFILE *)
  reg [DBITS-1:0] dmem[DMEMWORDS-1:0];

  wire IRQ = (intr_key || intr_sw || intr_timer) && sys_regs[0][0];
  assign intr_ret_addr = 
    !NOP_MEM ? PC_MEM : (
    !NOP_EX ? PC_EX : (
    !NOP_ID ? (mispred_EX_w ? pcgood_EX_w : PC_ID) : PC_FE));
  always @(posedge clk or posedge reset) begin
  	if (reset) begin
  		sys_regs[0] <= {DBITS{1'b0}};
      sys_regs[1] <= {DBITS{1'b0}};
      sys_regs[2] <= {DBITS{1'b0}};
      sys_regs[3] <= {DBITS{1'b0}};
  	end else if (IRQ) begin
  		/*
        Deal with system regs
        00 PCS - Disable interrupts
        01 IHA - Save interrupt handler address (0x10)
        10 IRA - Save return address
        11 IDN - Save interrupting device ID number
      */
      sys_regs[0][0] <= 0;
      sys_regs[0][1] <= sys_regs[0][0];
      sys_regs[1] <= INTRPC;
      sys_regs[2] <= intr_ret_addr;
      sys_regs[3] <=  intr_timer ? TIMER_ID :
                      intr_key ? KEY_ID :
                      intr_sw ? SWITCH_ID : {DBITS{1'bz}};
  	end else if (is_sys_inst_EX) begin
     if (wr_sys_EX)
      sys_regs[wregno_EX] = sysregval_EX;
     // else if (rd_sys_EX)
     //  regs[wregno_EX] = sysregval_EX;
    end else if (is_reti_EX) begin
      sys_regs[0][0] <= sys_regs[0][1];
    end
  end
  assign reti = is_reti_EX;

  assign memaddr_MEM_w = aluout_EX;
  assign rd_mem_MEM_w = ctrlsig_EX[2];
  assign wr_mem_MEM_w = ctrlsig_EX[1];
  assign wr_reg_MEM_w = ctrlsig_EX[0];
  // Read from D-MEM
  // assign rd_val_MEM_w = (memaddr_MEM_w == ADDRKEY) ? {{(DBITS-KEYBITS){1'b0}}, ~KEY} :
  //                 dmem[memaddr_MEM_w[DMEMADDRBITS-1:DMEMWORDBITS]];
  assign rd_val_MEM_w = dmem[memaddr_MEM_w[DMEMADDRBITS-1:DMEMWORDBITS]];

  // Write to D-MEM
  always @ (posedge clk) begin
    if(wr_mem_MEM_w)
      dmem[memaddr_MEM_w[DMEMADDRBITS-1:DMEMWORDBITS]] <= regval2_EX;
  end

  always @ (posedge clk or posedge reset) begin
    if(reset) begin
      inst_MEM   <= {INSTBITS{1'b0}};
      regval_MEM  <= {DBITS{1'b0}};
      wregno_MEM  <= {REGNOBITS{1'b0}};
      ctrlsig_MEM <= 1'b0;
      NOP_MEM <= 1'b1;
      PC_MEM <= {DBITS{1'b0}};
    end else if(IRQ) begin
      inst_MEM   <= {INSTBITS{1'b0}};
      regval_MEM  <= {DBITS{1'b0}};
      wregno_MEM  <= {REGNOBITS{1'b0}};
      ctrlsig_MEM <= 1'b0;
      NOP_MEM <= 1'b1;
      PC_MEM <= {DBITS{1'b0}};
    end else begin
      inst_MEM    <= inst_EX;
      regval_MEM  <= rd_mem_MEM_w ? rd_val_MEM_w : aluout_EX;
      wregno_MEM  <= wregno_EX;
      ctrlsig_MEM <= ctrlsig_EX[0];
      NOP_MEM <= NOP_EX;
      PC_MEM <= PC_EX;
    end
  end


  /*** WRITE BACK STAGE ***/ 

  wire wr_reg_WB_w;
  // regs is already declared in the ID stage

  assign wr_reg_WB_w = ctrlsig_MEM;
  
  always @ (negedge clk or posedge reset) begin
    if(reset) begin
      regs[0] <= {DBITS{1'b0}};
      regs[1] <= {DBITS{1'b0}};
      regs[2] <= {DBITS{1'b0}};
      regs[3] <= {DBITS{1'b0}};
      regs[4] <= {DBITS{1'b0}};
      regs[5] <= {DBITS{1'b0}};
      regs[6] <= {DBITS{1'b0}};
      regs[7] <= {DBITS{1'b0}};
      regs[8] <= {DBITS{1'b0}};
      regs[9] <= {DBITS{1'b0}};
      regs[10] <= {DBITS{1'b0}};
      regs[11] <= {DBITS{1'b0}};
      regs[12] <= {DBITS{1'b0}};
      regs[13] <= {DBITS{1'b0}};
      regs[14] <= {DBITS{1'b0}};
      regs[15] <= {DBITS{1'b0}};
    end else if(wr_reg_WB_w) begin
      regs[wregno_MEM] <= regval_MEM;
   end
  end

  wire can_fwd_rs_MEM = (rs_ID_w == wregno_MEM) && wr_reg_WB_w && (wregno_MEM != 0);
  wire can_fwd_rt_MEM = (rt_ID_w == wregno_MEM) && wr_reg_WB_w && (wregno_MEM != 0);

  wire can_fwd_rs_EX = (rs_ID_w == wregno_EX) && wr_reg_MEM_w && (wregno_EX != 0);
  wire can_fwd_rt_EX = (rt_ID_w == wregno_EX) && wr_reg_MEM_w && (wregno_EX != 0);

  wire can_fwd_rs_ID = (rs_ID_w == wregno_ID) && wr_reg_EX_w && (!rd_mem_EX_w) && (wregno_ID != 0);
  wire can_fwd_rt_ID = (rt_ID_w == wregno_ID) && wr_reg_EX_w && (!rd_mem_EX_w) && (wregno_ID != 0);

  assign fwd_regval1_w = can_fwd_rs_ID ? aluout_EX_r : (can_fwd_rs_EX
    ? (rd_mem_MEM_w ? rd_val_MEM_w : aluout_EX) : (can_fwd_rs_MEM ? regval_MEM : 0));
  assign fwd_regval2_w = can_fwd_rt_ID ? aluout_EX_r : (can_fwd_rt_EX
    ? (rd_mem_MEM_w ? rd_val_MEM_w : aluout_EX) : (can_fwd_rt_MEM ? regval_MEM : 0));

  assign take_fwd_regval1_w = can_fwd_rs_MEM || can_fwd_rs_EX || can_fwd_rs_ID;
  assign take_fwd_regval2_w = can_fwd_rt_MEM || can_fwd_rt_EX || can_fwd_rt_ID;

  assign ignore_stall_MEM = can_fwd_rs_MEM || can_fwd_rt_MEM;
  assign ignore_stall_EX = can_fwd_rs_EX || can_fwd_rt_EX;
  assign ignore_stall_ID = can_fwd_rs_ID || can_fwd_rt_ID;
  
  /*** I/O ***/
  
  wire [31:0] regval2_MEM_w;

  assign regval2_MEM_w = (wr_mem_MEM_w) ? regval2_EX : {DBITS{1'bz}};

  KEY_DEVICE #(.BITS(DBITS), .BASE(ADDRKEY)) KEY_d(
    .KEY(KEY),
    .ABUS(memaddr_MEM_w),
    .DBUS(regval2_MEM_w),
    .WE(wr_mem_MEM_w),
    .INTR(intr_key),
    .CLK(clk),.RESET(reset),.INIT(),
    .DEBUG()
  );

  SW_DEVICE #(.BITS(DBITS), .BASE(ADDRSW)) SW_d(
    .SW(SW),
    .ABUS(memaddr_MEM_w),
    .DBUS(regval2_MEM_w),
    .WE(wr_mem_MEM_w),
    .INTR(intr_sw),
    .CLK(clk),.RESET(reset),.INIT(),
    .DEBUG()
  );
  
  LED_DEVICE #(.BITS(DBITS), .BASE(ADDRLEDR)) LED_d(
    .LEDR(LEDR),
    .ABUS(memaddr_MEM_w),
    .DBUS(regval2_MEM_w),
    .WE(wr_mem_MEM_w),
    .CLK(clk),.RESET(reset),.INIT(),
    .DEBUG()
  );

  HEX_DEVICE #(.BITS(DBITS), .BASE(ADDRHEX)) HEX_d(
    .HEX({HEX5, HEX4, HEX3, HEX2, HEX1, HEX0}),
    .ABUS(memaddr_MEM_w),
    .DBUS(regval2_MEM_w),
    .WE(wr_mem_MEM_w),
    .CLK(clk),.RESET(reset),.INIT(),
    .DEBUG()
  );
  

  TIMER_DEVICE #(.BITS(DBITS), .BASE(ADDRTIMER)) TIMER_d(
    .ABUS(memaddr_MEM_w),
    .DBUS(regval2_MEM_w),
    .WE(wr_mem_MEM_w),
    .INTR(intr_timer),
    .CLK(clk),.RESET(reset),.INIT(),
    .DEBUG()
  );

endmodule

module SXT(IN, OUT);
  parameter IBITS = 16;
  parameter OBITS = 32;

  input  [IBITS-1:0] IN;
  output [OBITS-1:0] OUT;

  assign OUT = {{(OBITS-IBITS){IN[IBITS-1]}}, IN};
endmodule

module KEY_DEVICE(KEY, ABUS, DBUS, WE, INTR, CLK, RESET, INIT, DEBUG);
  parameter BITS;
  parameter BASE;

  input wire [3:0] KEY;
  input wire [BITS-1:0] ABUS;
  inout wire [BITS-1:0] DBUS;
  input wire WE,CLK,RESET,INIT;
  output wire DEBUG;
  output wire INTR;

  reg [BITS-1:0] KDATA;
  reg [BITS-1:0] KCTRL;

  wire sel_data = ABUS == BASE;             //address of KDATA
  wire rd_data = !WE && sel_data;

  wire sel_ctrl = ABUS == (BASE + 32'd4);   //address of KCTRL (control/status)
  wire wr_ctrl = WE && sel_ctrl;
  wire rd_ctrl = !WE && sel_ctrl;

  //Writes
  always @(posedge CLK or posedge RESET) begin
  	if (RESET) begin
  		KCTRL <= 32'b0;
  		KDATA <= 32'b0;
    end
  	else if (KDATA != KEY) begin   //if change in KDATA detected
  		if (KCTRL[0])
        KCTRL[1] <= 1;             //overrun bit set
      KCTRL[0] <= 1;               //ready bit set
  	end
  	else if (rd_data)              //if reading KDATA
  		KCTRL[0] <= 0;
    else if (wr_ctrl)
      KCTRL <= {(DBUS[4:2] << 1) | (DBUS[1] & KCTRL[1]), KCTRL[0]};
    KDATA <= KEY;                  //sets KDATA.
  end

	//Reads
  assign DBUS = rd_data ? KDATA :
  							rd_ctrl ? KCTRL :
  							{BITS{1'bz}};	

  assign INTR = KCTRL[0] && KCTRL[4];
endmodule

module SW_DEVICE(SW, ABUS, DBUS, WE, INTR, CLK, RESET, INIT, DEBUG);
  parameter BITS;
  parameter BASE;

  parameter TEN_MS = 900000;

  input wire [3:0] SW;
  input wire [BITS-1:0] ABUS;
  inout wire [BITS-1:0] DBUS;
  input wire WE,CLK,RESET,INIT;
  output wire DEBUG;
  output wire INTR;

  reg [BITS-1:0] SDATA;
  reg [BITS-1:0] SCTRL;
  reg [3:0] temp;
  reg [BITS-1:0] counter;

  wire sel_data = ABUS == BASE;             //address of SDATA
  wire rd_data = !WE && sel_data;

  wire sel_ctrl = ABUS == (BASE + 32'd4);   //address of SCTRL (control/status)
  wire wr_ctrl = WE && sel_ctrl;
  wire rd_ctrl = !WE && sel_ctrl;

  //Debouncing switch. There will be an interrupt at the beginning even without switch press.
  always @(posedge CLK or posedge RESET) begin
  	if (RESET) begin
      temp <= 4'b0;
      counter <= {BITS{1'b0}};
      SDATA <= {BITS{1'b0}};
      SCTRL <= {BITS{1'b0}};
  	end else begin 
      if (temp == SW)
    		counter <= counter + 1;
    	else begin
    		counter <= {BITS{1'b0}};
        temp <= SW;
      end

    	if (counter == TEN_MS) begin			//10 ms elapsed, an actual switch!
    		SDATA <= temp;									//switch change detected
    		 if (SCTRL[0])
          SCTRL[1] <= 1;          //overrun bit set
        SCTRL[0] <= 1;
        counter <= {BITS{1'b0}};
    	end else if (rd_data)
    		SCTRL[0] <= 0;
    	else if (wr_ctrl)
    		SCTRL <= {(DBUS[4:2] << 1) | (DBUS[1] & SCTRL[1]), SCTRL[0]};
    end
  end

  //Reads
  assign DBUS = rd_data ? SDATA :
                rd_ctrl ? SCTRL :
                {BITS{1'bz}};

  assign INTR = SCTRL[0] && SCTRL[4];
endmodule

module TIMER_DEVICE(ABUS, DBUS, WE, INTR, CLK, RESET, INIT, DEBUG);
  parameter BITS;
  parameter BASE;

  input wire [BITS-1:0] ABUS;
  inout wire [BITS-1:0] DBUS;
  input wire WE,CLK,RESET,INIT;
  output wire DEBUG;
  output wire INTR;

  reg [BITS-1:0] TCNT, TLIM, TCTL, CLK_COUNT;

  wire sel_tcnt = ABUS == BASE;             //address of TCNT
  wire wr_tcnt = WE && sel_tcnt;
  wire rd_tcnt = !WE && sel_tcnt;

  wire sel_tlim = ABUS == (BASE + 32'd4);   //address of TLIM
  wire wr_tlim = WE && sel_tlim;
  wire rd_tlim = !WE && sel_tlim;

  wire sel_ctrl = ABUS == (BASE + 32'd8);   //address of TCTL (control/status)
  wire wr_ctrl = WE && sel_ctrl;
  wire rd_ctrl = !WE && sel_ctrl;

  //Writes
  always @(posedge CLK or posedge RESET) begin
    if (RESET) begin
      TCNT <= 32'b0;
      TLIM <= 32'b0;
      TCTL <= 32'b0;
      CLK_COUNT <= 32'b0;
    end else if (CLK_COUNT >= 90000) begin     //number of clocks in 1 ms
      CLK_COUNT <= 0;
      TCNT <= TCNT + 1;
    end else if ((TCNT >= TLIM -1) && (TLIM != 0)) begin //if counter reached
      TCNT <= 0;
      if (TCTL[0])    //if ready == 1 already then overflow
        TCTL[1] <= 1;
      TCTL[0] <= 1;
    end else if (wr_tcnt)   //if writing to tcnt
      TCNT <= DBUS;
    else if (wr_tlim)       //if writing to tlim
      TLIM <= DBUS;
    else if (wr_ctrl)       //if writing to tctl
      TCTL <= {(DBUS[4:2] << 1) | (DBUS[1] && TCTL[1]), TCTL[0]};
    else 
    	CLK_COUNT <= CLK_COUNT + 1;
  end

  //Reads
  assign DBUS = rd_tcnt ? TCNT :
                rd_tlim ? TLIM :
                rd_ctrl ? TCTL :
                {BITS{1'bz}}; 

  assign INTR = TCTL[0] && TCTL[4];
endmodule

module HEX_DEVICE(HEX, ABUS, DBUS, WE, CLK, RESET, INIT, DEBUG);
  parameter BITS;
  parameter BASE;

  input wire [35:0] HEX;
  input wire [BITS-1:0] ABUS;
  inout wire [BITS-1:0] DBUS;
  input wire WE,CLK,RESET,INIT;
  output wire DEBUG;

  reg [23:0] HEX_out;

  wire sel_data = ABUS == BASE;             //address of HEX
  wire wr_data = WE && sel_data;
  wire rd_data = !WE && sel_data;

  always @(posedge CLK or posedge RESET) begin
  	if (RESET)
  		HEX_out <= {24{1'b0}};
  	else if (wr_data)
  		HEX_out <= DBUS[23:0];
	end

	SevenSeg ss5(.OUT(HEX[35:30]), .IN(HEX_out[23:20]), .OFF(1'b0));
  SevenSeg ss4(.OUT(HEX[29:24]), .IN(HEX_out[19:16]), .OFF(1'b0));
  SevenSeg ss3(.OUT(HEX[23:18]), .IN(HEX_out[15:12]), .OFF(1'b0));
  SevenSeg ss2(.OUT(HEX[17:12]), .IN(HEX_out[11:8]), .OFF(1'b0));
  SevenSeg ss1(.OUT(HEX[11:6]), .IN(HEX_out[7:4]), .OFF(1'b0));
  SevenSeg ss0(.OUT(HEX[5:0]), .IN(HEX_out[3:0]), .OFF(1'b0));

  assign DBUS = (rd_data) ? {{8{1'b0}}, HEX_out} : {BITS{1'bz}};
endmodule

module LED_DEVICE(LEDR, ABUS, DBUS, WE, CLK, RESET, INIT, DEBUG);
  parameter BITS;
  parameter BASE;

  input wire [9:0] LEDR;
  input wire [BITS-1:0] ABUS;
  inout wire [BITS-1:0] DBUS;
  input wire WE,CLK,RESET,INIT;
  output wire DEBUG;

  reg [9:0] LED_register;

  wire sel_data = ABUS == BASE;             //address of LEDR
  wire wr_data = WE && sel_data;
  wire rd_data = !WE && sel_data;

  always @(posedge CLK or posedge RESET) begin
  	if (RESET)
  		LED_register <= {10{1'b0}};
  	else if (wr_data)
  		LED_register <= DBUS[9:0];
  	else
  		LED_register <= LEDR;
  end

  assign DBUS = (rd_data) ? {{22{1'b0}}, LED_register} : {BITS{1'bz}};
endmodule