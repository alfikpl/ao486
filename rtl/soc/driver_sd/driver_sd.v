/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module driver_sd(
    
    input           clk,
    input           rst_n,
    
    input       [1:0]   avs_address,
    output              avs_waitrequest,
    input               avs_read,
    output      [31:0]  avs_readdata,
    input               avs_write,
    input       [31:0]  avs_writedata,
    
    output reg  [31:0]  avm_address,
    input               avm_waitrequest,
    output reg          avm_read,
    input       [31:0]  avm_readdata,
    input               avm_readdatavalid,
    output reg          avm_write,
    output reg  [31:0]  avm_writedata,
    
    output reg      sd_clk,
    inout           sd_cmd,
    inout   [3:0]   sd_dat
);

//------------------------------------------------------------------------------

//------------------------------------------------------------------------------ Avalon master

reg data_read;
reg data_write;
reg [31:0] data_part_contents;
reg wait_for_readdatavalid;

always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
	    avm_address             <= 32'd0;
		avm_read                <= 1'b0;
        avm_write               <= 1'b0;
        avm_writedata           <= 32'b0;
        
		data_read               <= 1'b0;
		data_write              <= 1'b0;
		data_part_contents      <= 32'd0;
        wait_for_readdatavalid  <= 1'b0;
	end
	else if(data_state == S_DATA_READ_READY_PART && data_read == 1'b0) begin
		if(avm_write && avm_waitrequest == 1'b0) begin
			avm_write <= 1'b0;
			
			data_read <= 1'b1;
		end
		else begin
		    avm_address   <= avalon_address_base + { 23'b0, part_counter, 2'b0 };
            avm_write     <= 1'b1;
            avm_writedata <= { data_part[7:0], data_part[15:8], data_part[23:16], data_part[31:24] };
		end
	end
	else if(data_state == S_DATA_WRITE_READY_PART && data_write == 1'b0) begin
		if(avm_read && avm_waitrequest == 1'b0) begin
            avm_read <= 1'b0;
        end
        else if(wait_for_readdatavalid && avm_readdatavalid) begin
            avm_read <= 1'b0;
            wait_for_readdatavalid <= 1'b0;
			data_part_contents <= { avm_readdata[7:0], avm_readdata[15:8], avm_readdata[23:16], avm_readdata[31:24] };
			
			data_write <= 1'b1;
		end
		else begin
		    avm_address             <= avalon_address_base + { 23'b0, part_counter, 2'b0 };
			avm_read                <= 1'b1;
            wait_for_readdatavalid  <= 1'b1;
		end
	end
	else if(data_state != S_DATA_READ_READY_PART && data_state != S_DATA_WRITE_READY_PART) begin
		data_read <= 1'b0;
		data_write <= 1'b0;
	end
end

//------------------------------------------------------------------------------ Avalon slave

//read mutex

assign avs_readdata = (avs_address == 2'd0)? {29'd0, status[2:0]} : { 29'd0, mutex };
    
reg [2:0] mutex;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)                                                               mutex <= 3'd0;
    else if(mutex == 3'd0 && avs_address == 2'd1 && avs_read && ~(avs_waitrequest)) mutex <= 3'd1;
    else if(mutex == 3'd0 && avs_address == 2'd2 && avs_read && ~(avs_waitrequest)) mutex <= 2'd2;
    else if(mutex == 3'd0 && avs_address == 2'd3 && avs_read && ~(avs_waitrequest)) mutex <= 3'd3;
    else if(mutex < 3'd4 && (status == STATUS_READ || status == STATUS_WRITE))      mutex <= 3'd4;
    else if(status == STATUS_IDLE && status_last != STATUS_IDLE)                    mutex <= 3'd0;
end

assign avs_waitrequest = control_state == S_CTRL_PRE_IDLE;

// write only
reg [31:0] sd_address;
reg [31:0] sd_block_count;
reg [1:0]  control;
reg [31:0] avalon_address_base;

localparam [1:0] CONTROL_IDLE   = 2'd0;
localparam [1:0] CONTROL_REINIT = 2'd1;
localparam [1:0] CONTROL_READ	= 2'd2;
localparam [1:0] CONTROL_WRITE	= 2'd3;

always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		avalon_address_base <= 32'd0;
		sd_address          <= 32'd0;
		sd_block_count      <= 32'd0;
		control             <= 2'd0;
	end
	else begin
		if(control_state == S_CTRL_PRE_IDLE) begin
			sd_block_count      <= sd_block_count - 32'd1;
			sd_address          <= sd_address + 32'd1;
			avalon_address_base <= avalon_address_base + 32'd512;
			
			if(sd_block_count == 32'd1) control <= CONTROL_IDLE;
		end
		else if(avs_write) begin
	        if(avs_address == 2'd0)         avalon_address_base <= avs_writedata;
	        else if(avs_address == 2'd1)    sd_address          <= avs_writedata;
	        else if(avs_address == 2'd2)    sd_block_count      <= avs_writedata;
	        else if(avs_address == 2'd3)    control             <= avs_writedata[1:0];
        end
	end
	
end

//------------------------------------------------------------------------------ Control state machine

reg [3:0]  control_state;
reg [15:0] error_count;
reg [2:0]  status;
reg [37:0] cmd_send_contents;

reg start_cmd;
reg start_read;
reg start_write;

reg [2:0] status_last;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0)   status_last <= STATUS_INIT;
    else                status_last <= status;
end

`define CRC7_REVERSE crc7[0],crc7[1],crc7[2],crc7[3],crc7[4],crc7[5],crc7[6]

localparam [3:0] S_CTRL_INIT        = 4'd0;
localparam [3:0] S_CTRL_CMD0        = 4'd1;
localparam [3:0] S_CTRL_CMD8        = 4'd2;
localparam [3:0] S_CTRL_CMD55       = 4'd3;
localparam [3:0] S_CTRL_ACMD41      = 4'd4;
localparam [3:0] S_CTRL_CMD2        = 4'd5;
localparam [3:0] S_CTRL_CMD3        = 4'd6;
localparam [3:0] S_CTRL_CMD7        = 4'd7;
localparam [3:0] S_CTRL_PRE_IDLE    = 4'd8;
localparam [3:0] S_CTRL_IDLE        = 4'd9;
localparam [3:0] S_CTRL_CMD17_READ  = 4'd10;
localparam [3:0] S_CTRL_CMD24_WRITE = 4'd11;

localparam [2:0] STATUS_INIT        = 3'd0;
localparam [2:0] STATUS_INIT_ERROR  = 3'd1;
localparam [2:0] STATUS_IDLE        = 3'd2;
localparam [2:0] STATUS_READ        = 3'd3;
localparam [2:0] STATUS_WRITE       = 3'd4;
localparam [2:0] STATUS_ERROR       = 3'd5;
	
always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		control_state <= S_CTRL_INIT;
		status <= STATUS_INIT;
		cmd_send_contents <= 38'd0;
		start_cmd <= 1'b0;
		start_read <= 1'b0;
		start_write <= 1'b0;
		error_count <= 16'd0;
	end
	else if(control_state == S_CTRL_INIT && error_count == 16'd65535) begin
		status <= STATUS_INIT_ERROR;
		
		if(control == CONTROL_REINIT) begin
			error_count <= 16'd0;
			control_state <= S_CTRL_INIT;
		end
	end
	else if(control_state == S_CTRL_INIT) begin
		status <= STATUS_INIT;
		
		if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
		    start_cmd <= 1'b1;
			//CMD0, no arguments
			cmd_send_contents <= { 6'd0, 32'd0 };
			control_state <= S_CTRL_CMD0;
		end
	end
	else if(control_state == S_CTRL_CMD0) begin
		
		if(cmd_state == S_CMD_REPLY_ERROR) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_INIT;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
			start_cmd <= 1'b1;
			//CMD8, supply voltage, check pattern
			cmd_send_contents <= { 6'd8, 20'd0, 4'b0001, 8'b10101010 };
			control_state <= S_CTRL_CMD8;
		end
		else start_cmd <= 1'b0;
	end
	else if(control_state == S_CTRL_CMD8) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE && cmd_reply != { 1'b0, 1'b0, 6'd8, 20'd0, 4'b0001, 8'b10101010, `CRC7_REVERSE, 1'b1 })
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_INIT;
		end
		else if(cmd_state == S_CMD_IDLE) begin
			start_cmd <= 1'b1;
			//CMD55, RCA
			cmd_send_contents <= { 6'd55, 16'd0, 16'd0};
			control_state <= S_CTRL_CMD55;
		end
	end
	else if(control_state == S_CTRL_CMD55) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE &&
				(cmd_reply[47:40] != { 1'b0, 1'b0, 6'd55 } || cmd_reply[39:27] != 13'b0 || cmd_reply[24:21] != 4'b0 ||
				 cmd_reply[13] != 1'b1 || cmd_reply[11] != 1'b0 || cmd_reply[7:0] != { `CRC7_REVERSE, 1'b1 }
				)
			)
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_INIT;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
			start_cmd <= 1'b1;
			//ACMD41, 
			cmd_send_contents <= { 	6'd41, 								//command index
									1'b0, 								//reserved bit
									1'b1,								//host capacity support HCS(OCR[30])
									6'b0,								//reserved bits
									24'b0001_0000_0000_0000_0000_0000	//VDD voltage window OCR[23:0]
			};
			control_state <= S_CTRL_ACMD41;
		end
	end
	else if(control_state == S_CTRL_ACMD41) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE && (cmd_reply[47:40] != { 1'b0, 1'b0, 6'b111111 } || 
				cmd_reply[39:38] != 2'b11 || cmd_reply[7:0] != {7'b1111111, 1'b1 })
			)
		) begin
			if(error_count == 16'd65535) begin
				control_state <= S_CTRL_INIT;
			end
			else begin
				error_count <= error_count + 16'd1;
				start_cmd <= 1'b1;
				//CMD55, RCA
				cmd_send_contents <= { 6'd55, 16'd0, 16'd0};
				control_state <= S_CTRL_CMD55;
			end
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
			start_cmd <= 1'b1;
			//CMD2, no arguments
			cmd_send_contents <= { 6'd2, 32'd0 };
			control_state <= S_CTRL_CMD2;
		end
	end
	else if(control_state == S_CTRL_CMD2) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE && cmd_reply[0] != 1'b1)
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_INIT;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
			start_cmd <= 1'b1;
			//CMD3, no arguments
			cmd_send_contents <= { 6'd3, 32'd0 };
			control_state <= S_CTRL_CMD3;
		end
	end
	else if(control_state == S_CTRL_CMD3) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE &&
				(cmd_reply[47:40] != { 1'b0, 1'b0, 6'd3 } || 
				 /*23:8= 23,22,19,12:0 from card status*/
				 cmd_reply[23:21] != 3'b0 || cmd_reply[13] != 1'b0 || cmd_reply[11] != 1'b0 || 
				 cmd_reply[7:0] != { `CRC7_REVERSE, 1'b1 }
				)
			)
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_INIT;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
			
			start_cmd <= 1'b1;
			//CMD7, no arguments
			cmd_send_contents <= { 	6'd7,				//command index
									cmd_reply[39:24], 	//RCA
									16'd0				//stuff bits
			};
			control_state <= S_CTRL_CMD7;
		end
	end
	else if(control_state == S_CTRL_CMD7) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE &&
				(cmd_reply[47:40] != { 1'b0, 1'b0, 6'd7 } || cmd_reply[39:27] != 13'b0 || cmd_reply[24:21] != 4'b0 ||
				 cmd_reply[13] != 1'b0 || cmd_reply[11] != 1'b0 || cmd_reply[7:0] != { `CRC7_REVERSE, 1'b1 }
				)
			)
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_INIT;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0) begin
			start_cmd <= 1'b0;
			
			error_count <= 16'd0;
			control_state <= S_CTRL_IDLE;
		end
	end
	else if(control_state == S_CTRL_PRE_IDLE) begin
		control_state <= S_CTRL_IDLE;
	end
	else if(control_state == S_CTRL_IDLE && error_count != 16'd0) begin
		status <= STATUS_ERROR;
		
		if(control == CONTROL_IDLE) begin
			control_state <= S_CTRL_IDLE;
			error_count <= 16'd0;
		end
		else if(control == CONTROL_REINIT) begin
			control_state <= S_CTRL_INIT;
			error_count <= 16'd0;
		end
	end
	else if(control_state == S_CTRL_IDLE) begin
		if(control == CONTROL_READ && sd_block_count != 32'd0) begin
			status <= STATUS_READ;
			start_cmd <= 1'b1;
			start_read <= 1'b1;
			//CMD17, sector address
			cmd_send_contents <= { 	6'd17,				//command index
									sd_address[31:0]	//sector address
			};
			control_state <= S_CTRL_CMD17_READ;
		end
		else if(control == CONTROL_WRITE && sd_block_count != 32'd0) begin
			status <= STATUS_WRITE;
			start_cmd <= 1'b1;
			start_write <= 1'b1;
			//CMD24, sector address
			cmd_send_contents <= { 	6'd24,				//command index
									sd_address[31:0] 	//sector address
			};
			control_state <= S_CTRL_CMD24_WRITE;
		end
		else begin
			status <= STATUS_IDLE;
		end
	end
	else if(control_state == S_CTRL_CMD17_READ) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE &&
				(cmd_reply[47:40] != { 1'b0, 1'b0, 6'd17 } || cmd_reply[39:27] != 13'b0 || cmd_reply[24:21] != 4'b0 ||
				 cmd_reply[13] != 1'b0 || cmd_reply[11] != 1'b0 || cmd_reply[7:0] != { `CRC7_REVERSE, 1'b1 }
				)
			)
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_IDLE;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0 && start_read == 1'b1) begin
			start_read <= 1'b0;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0 && start_read == 1'b0 && data_state == S_DATA_READ_ERROR) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_IDLE;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0 && start_read == 1'b0 && data_state == S_DATA_IDLE) begin
			error_count <= 16'd0;
			control_state <= S_CTRL_PRE_IDLE;
		end
	end
	else if(control_state == S_CTRL_CMD24_WRITE) begin
		if(start_cmd == 1'b1) begin
			start_cmd <= 1'b0;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR ||
			(cmd_state == S_CMD_IDLE &&
				(cmd_reply[47:40] != { 1'b0, 1'b0, 6'd24 } || cmd_reply[39:27] != 13'b0 || cmd_reply[24:21] != 4'b0 ||
				 cmd_reply[13] != 1'b0 || cmd_reply[11] != 1'b0 || cmd_reply[7:0] != { `CRC7_REVERSE, 1'b1 }
				)
			)
		) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_IDLE;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0 && start_write == 1'b1) begin
			start_write <= 1'b0;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0 && start_write == 1'b0 && data_state == S_DATA_WRITE_ERROR) begin
			error_count <= error_count + 16'd1;
			control_state <= S_CTRL_IDLE;
		end
		else if(cmd_state == S_CMD_IDLE && start_cmd == 1'b0 && start_write == 1'b0 && data_state == S_DATA_IDLE) begin
			error_count <= 16'd0;
			control_state <= S_CTRL_PRE_IDLE;
		end
	end
end

//------------------------------------------------------------------------------ SD interface

reg sd_cmd_reg = 1'b1;
reg sd_dat_reg = 1'b1;

assign sd_cmd = (sd_cmd_enable == 1'b1) ?  sd_cmd_reg : 1'bZ;
assign sd_dat[0] = (sd_data_enable == 1'b1) ? sd_dat_reg : 1'bZ;

assign sd_dat[3:1] = 3'bZ;

//CID register not interpreted: CRC7 not checked, always accepted

//---------------------------------------------------- SD data

reg         sd_data_enable;
reg [3:0]   data_state;
reg [23:0]  data_counter;
reg [6:0]   part_counter;
reg [15:0]  crc16;
reg [31:0]  data_part;

reg         clk_data_ena;
reg         clk_master_ena;


localparam [3:0]	S_DATA_IDLE 								= 4'd0;
localparam [3:0]	S_DATA_READ_START_BIT 						= 4'd1;
localparam [3:0]	S_DATA_READ_CONTENTS 						= 4'd2;
localparam [3:0]	S_DATA_READ_READY_PART 						= 4'd3;
localparam [3:0]	S_DATA_READ_READY_PART_CONTINUE				= 4'd4;
localparam [3:0]	S_DATA_READ_CRC16_END_BIT 					= 4'd5;
localparam [3:0]	S_DATA_READ_ERROR 							= 4'd6;
localparam [3:0]	S_DATA_WRITE_START_BIT 						= 4'd7;
localparam [3:0]	S_DATA_WRITE_READY_PART 					= 4'd8;
localparam [3:0]	S_DATA_WRITE_CONTENTS 						= 4'd9;
localparam [3:0]	S_DATA_WRITE_CRC16_END_BIT 					= 4'd10;
localparam [3:0]	S_DATA_WRITE_CRC_STATUS_START 				= 4'd11;
localparam [3:0]	S_DATA_WRITE_CRC_STATUS_CONTENTS_END_BIT 	= 4'd12;
localparam [3:0]	S_DATA_WRITE_BUSY_START 					= 4'd13;
localparam [3:0]	S_DATA_WRITE_BUSY_WAIT 						= 4'd14;
localparam [3:0]	S_DATA_WRITE_ERROR 							= 4'd15;
	

always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		sd_data_enable 	<= 1'b0;
		data_state 		<= S_DATA_IDLE;
		data_counter 	<= 24'd0;
		part_counter 	<= 7'd0;
		crc16 			<= 16'd0;
		data_part 		<= 32'd0;
		clk_data_ena	<= 1'b0;
		clk_master_ena 	<= 1'b1;
		sd_dat_reg		<= 1'b1;
	end
	else if(data_state == S_DATA_IDLE) begin
		//do not wait for read command and reply
		if(start_read == 1'b1) begin
			data_state <= S_DATA_READ_START_BIT;
		end
		//wait for write command and reply
		else if(start_write == 1'b1 && start_cmd == 1'b0 && cmd_state == S_CMD_IDLE) begin
			data_state <= S_DATA_WRITE_START_BIT;
		end
	end
	else if(clk_counter == 2'd0) begin
		
		//wait for response and data simultaneously (data read)
		if(data_state == S_DATA_READ_START_BIT) begin
			clk_data_ena <= 1'b1;
			
			if(sd_dat[0] == 1'b0) begin
				crc16 <= { sd_dat[0] ^ crc16[0], crc16[15:12], sd_dat[0] ^ crc16[11] ^ crc16[0], crc16[10:5],
					sd_dat[0] ^ crc16[4] ^ crc16[0], crc16[3:1] };
				
				data_state <= S_DATA_READ_CONTENTS;
				data_counter <= 24'd0;
			end
			else if(data_counter == 24'd65535) begin
				data_state <= S_DATA_READ_ERROR;
				data_counter <= 24'd0;
			end
			else data_counter <= data_counter + 24'd1;
		end
		else if(data_state == S_DATA_READ_CONTENTS) begin
			crc16 <= { sd_dat[0] ^ crc16[0], crc16[15:12], sd_dat[0] ^ crc16[11] ^ crc16[0],
				crc16[10:5], sd_dat[0] ^ crc16[4] ^ crc16[0], crc16[3:1] };
			data_part <= { data_part[30:0], sd_dat[0] };
			
			if(data_counter == 24'd30) begin
				clk_master_ena <= 1'b0;
				data_counter <= data_counter + 24'd1;
			end
			else if(data_counter == 24'd31) begin
				data_state <= S_DATA_READ_READY_PART;
				data_counter <= 24'd0;
			end
			else data_counter <= data_counter + 24'd1;
		end
		else if(data_state == S_DATA_READ_READY_PART) begin
			if(data_read == 1'b1) begin
				clk_master_ena <= 1'b1;
				data_state <= S_DATA_READ_READY_PART_CONTINUE;
			end
		end
		else if(data_state == S_DATA_READ_READY_PART_CONTINUE) begin
			if(part_counter == 7'd127) begin
				data_state <= S_DATA_READ_CRC16_END_BIT;
				part_counter <= 7'd0;
			end
			else begin
				data_state <= S_DATA_READ_CONTENTS;
				part_counter <= part_counter + 7'd1;
			end
		end
		else if(data_state == S_DATA_READ_CRC16_END_BIT) begin
			data_part <= { sd_dat[0], data_part[31:1] };
			
			if(data_counter == 24'd16) begin
				if(data_part[31:16] != crc16[15:0] || sd_dat[0] != 1'b1) begin
					data_state <= S_DATA_READ_ERROR;
					data_counter <= 24'd0;
				end
				else begin
					clk_data_ena <= 1'b0;
					data_state <= S_DATA_IDLE;
					data_counter <= 24'd0;
					crc16 <= 16'd0;
				end
			end
			else data_counter <= data_counter + 24'd1;
		end
		else if(data_state == S_DATA_READ_ERROR) begin
			clk_data_ena <= 1'b0;
			data_state <= S_DATA_IDLE;
			data_counter <= 24'd0;
			crc16 <= 16'd0;
		end
		
		//send data on data line, wait for crc status, wait while busy on data line (data write)
		else if(data_state == S_DATA_WRITE_START_BIT) begin
			sd_dat_reg <= 1'b0;
			crc16 <= { 1'b0 ^ crc16[0], crc16[15:12], 1'b0 ^ crc16[11] ^ crc16[0], crc16[10:5],
				1'b0 ^ crc16[4] ^ crc16[0], crc16[3:1] };
			
			sd_data_enable <= 1'b1;
			clk_data_ena <= 1'b1;
			data_counter <= 24'd0;
			data_state <= S_DATA_WRITE_READY_PART;
		end
		else if(data_state == S_DATA_WRITE_READY_PART) begin
		    
			if(data_write == 1'b1) begin
			    clk_data_ena <= 1'b1;
				data_state <= S_DATA_WRITE_CONTENTS;
				data_part <= data_part_contents;
			end
			else begin
			    clk_data_ena <= 1'b0;
			end
		end
		else if(data_state == S_DATA_WRITE_CONTENTS) begin
			sd_dat_reg <= data_part[31];
			crc16 <= { data_part[31] ^ crc16[0], crc16[15:12], data_part[31] ^ crc16[11] ^ crc16[0], crc16[10:5],
				data_part[31] ^ crc16[4] ^ crc16[0], crc16[3:1] };
			data_part <= { data_part[30:0], 1'b0 };
			
			if(data_counter == 24'd31) begin
				data_counter <= 24'd0;
				
				if(part_counter == 7'd127) begin
					part_counter <= 7'd0;
					data_state <= S_DATA_WRITE_CRC16_END_BIT;
				end
				else begin
				    clk_data_ena <= 1'b0;
					part_counter <= part_counter + 7'd1;
					data_state <= S_DATA_WRITE_READY_PART;
				end
			end
			else data_counter <= data_counter + 24'd1;
		end
		
		else if(data_state == S_DATA_WRITE_CRC16_END_BIT) begin
			sd_dat_reg <= crc16[0];
			
			if(data_counter == 24'd16) begin
			    data_counter <= 24'd0;
			    crc16 <= 16'd0;
				data_state <= S_DATA_WRITE_CRC_STATUS_START;
			end
			else begin
				crc16 <= { 1'b1, crc16[15:1] };
				data_counter <= data_counter + 24'd1;
			end
			
		end
		else if(data_state == S_DATA_WRITE_CRC_STATUS_START) begin
			sd_data_enable <= 1'b0;
			
			if(sd_dat[0] == 1'b0) begin
				data_state <= S_DATA_WRITE_CRC_STATUS_CONTENTS_END_BIT;
				data_counter <= 24'b0;
			end
			else if(data_counter == 24'd65535) begin
				data_state <= S_DATA_WRITE_ERROR;
				data_counter <= 24'b0;
			end
			else data_counter <= data_counter + 24'd1;
		end
		
		else if(data_state == S_DATA_WRITE_CRC_STATUS_CONTENTS_END_BIT) begin
			data_part <= { data_part[30:0], sd_dat[0] };
			
			if(data_counter == 24'd3) begin
				data_state <= S_DATA_WRITE_BUSY_START;
				data_counter <= 24'b0;
			end
			else data_counter <= data_counter + 24'd1;
		end
		else if(data_state == S_DATA_WRITE_BUSY_START) begin
			
			if(sd_dat[0] == 1'b0) begin
				data_state <= S_DATA_WRITE_BUSY_WAIT;
				data_counter <= 24'b0;
			end
			else if(data_counter == 24'd65535) begin
				data_state <= S_DATA_WRITE_ERROR;
				data_counter <= 24'b0;
			end
			else data_counter <= data_counter + 24'd1;
		end
		else if(data_state == S_DATA_WRITE_BUSY_WAIT) begin
			if(sd_dat[0] == 1'b1 && data_part[3:0] != 4'b0101) begin
				data_state <= S_DATA_WRITE_ERROR;
				data_counter <= 24'd0;
			end
			else if(sd_dat[0] == 1'b1) begin
				clk_data_ena <= 1'b0;
				data_state <= S_DATA_IDLE;
				data_counter <= 24'd0;
			end
			else if(data_counter == 24'hFFFFFF) begin
				data_state <= S_DATA_WRITE_ERROR;
				data_counter <= 24'd0;
			end
			else data_counter <= data_counter + 24'd1;
		end
		else if(data_state == S_DATA_WRITE_ERROR) begin
			clk_data_ena <= 1'b0;
			data_state <= S_DATA_IDLE;
			data_counter <= 24'd0;
		end
	end
end

//------------------------------------------------------------------------------ SD command

reg 		sd_cmd_enable;
reg [37:0] 	cmd_send;
reg [47:0] 	cmd_reply;
reg [3:0] 	cmd_state;
reg [7:0] 	cmd_counter;
reg [6:0] 	crc7;
reg 		clk_cmd_ena;

localparam [3:0]	S_CMD_IDLE 					= 4'd0;
localparam [3:0]	S_CMD_SEND_START_ONES 		= 4'd1;
localparam [3:0]	S_CMD_SEND_START_BIT 		= 4'd2;
localparam [3:0]	S_CMD_SEND_START_HOST 		= 4'd3;
localparam [3:0]	S_CMD_SEND_CONTENTS 		= 4'd4;
localparam [3:0]	S_CMD_SEND_CRC7 			= 4'd5;
localparam [3:0]	S_CMD_SEND_END_BIT 			= 4'd6;
localparam [3:0]	S_CMD_SEND_END_ONES 		= 4'd7;
localparam [3:0]	S_CMD_REPLY_START_BIT 		= 4'd8;
localparam [3:0]	S_CMD_REPLY_CONTENTS 		= 4'd9;
localparam [3:0]	S_CMD_REPLY_CRC7_END_BIT 	= 4'd10;
localparam [3:0]	S_CMD_REPLY_FINISH_ONES 	= 4'd11;
localparam [3:0]	S_CMD_REPLY_ERROR 			= 4'd12;

always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		sd_cmd_enable 	<= 1'b0;
		cmd_send 		<= 38'd0;
		cmd_reply 		<= 48'd0;
		cmd_state 		<= S_CMD_IDLE;
		cmd_counter 	<= 8'd0;
		crc7 			<= 7'd0;
		clk_cmd_ena 	<= 1'b0;
		sd_cmd_reg		<= 1'b1;
	end
	else if(cmd_state == S_CMD_IDLE) begin
		if(start_cmd == 1'b1) begin
			cmd_state <= S_CMD_SEND_START_ONES;
		end
	end
	else if(clk_counter == 2'd0 && clk_master_ena == 1'b1) begin
		
		//send command
		if(cmd_state == S_CMD_SEND_START_ONES) begin
			sd_cmd_enable <= 1'b1;
			sd_cmd_reg <= 1'b1;
			clk_cmd_ena <= 1'b1;
			crc7 <= 7'd0;
			
			if(cmd_counter == 8'd7) begin
				cmd_state <= S_CMD_SEND_START_BIT;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		else if(cmd_state == S_CMD_SEND_START_BIT) begin
			sd_cmd_reg <= 1'b0;
			crc7 <= { 1'b0 ^ crc7[0], crc7[6:5], 1'b0 ^ crc7[4] ^ crc7[0], crc7[3:1] };
			
			cmd_state <= S_CMD_SEND_START_HOST;
		end
		else if(cmd_state == S_CMD_SEND_START_HOST) begin
			sd_cmd_reg <= 1'b1;
			crc7 <= { 1'b1 ^ crc7[0], crc7[6:5], 1'b1 ^ crc7[4] ^ crc7[0], crc7[3:1] };
			
			cmd_send <= cmd_send_contents;
			cmd_state <= S_CMD_SEND_CONTENTS;
		end
		else if(cmd_state == S_CMD_SEND_CONTENTS) begin
			sd_cmd_reg <= cmd_send[37];
			crc7 <= { cmd_send[37] ^ crc7[0], crc7[6:5], cmd_send[37] ^ crc7[4] ^ crc7[0], crc7[3:1] };
			cmd_send <= { cmd_send[36:0], 1'b0 };
			
			if(cmd_counter == 8'd37) begin
				cmd_state <= S_CMD_SEND_CRC7;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		else if(cmd_state == S_CMD_SEND_CRC7) begin
			sd_cmd_reg <= crc7[0];
			crc7 <= { 1'b0, crc7[6:1] };
			
			if(cmd_counter == 8'd6) begin
				cmd_state <= S_CMD_SEND_END_BIT;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		else if(cmd_state == S_CMD_SEND_END_BIT) begin
			sd_cmd_reg <= 1'b1;
			
			// if CMD0: send ones
			if(control_state == S_CTRL_CMD0) begin
				cmd_state <= S_CMD_SEND_END_ONES;
			end
			else begin
				crc7 <= 7'd0;
				cmd_state <= S_CMD_REPLY_START_BIT;
			end
		end
		else if(cmd_state == S_CMD_SEND_END_ONES) begin
			sd_cmd_enable <= 1'b0;
			sd_cmd_reg <= 1'b1;
			
			if(cmd_counter == 8'd7) begin
				clk_cmd_ena <= 1'b0;
				cmd_state <= S_CMD_IDLE;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		
		//wait for response: 48-bits with CRC7
		//wait for response: 48-bits without CRC7
		//wait for response: 136-bits (CMD2/R2)
		//wait for response and busy on data line simultaneously: (CMD7/R1b)
		else if(cmd_state == S_CMD_REPLY_START_BIT) begin
			sd_cmd_enable <= 1'b0;
			
			if(sd_cmd == 1'b0) begin
				crc7 <= { sd_cmd ^ crc7[0], crc7[6:5], sd_cmd ^ crc7[4] ^ crc7[0], crc7[3:1] };
				cmd_reply <= { cmd_reply[46:0], sd_cmd };
				
				cmd_state <= S_CMD_REPLY_CONTENTS;
				cmd_counter <= 8'd0;
			end
			else if(cmd_counter == 8'd255) begin
				crc7 <= 7'd0;
				cmd_state <= S_CMD_REPLY_ERROR;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		else if(cmd_state == S_CMD_REPLY_CONTENTS) begin
			crc7 <= { sd_cmd ^ crc7[0], crc7[6:5], sd_cmd ^ crc7[4] ^ crc7[0], crc7[3:1] };
			cmd_reply <= { cmd_reply[46:0], sd_cmd };
			
			if(	(control_state != S_CTRL_CMD2 && cmd_counter == 8'd38) ||
				(control_state == S_CTRL_CMD2 && cmd_counter == 8'd126)
			) begin
				cmd_state <= S_CMD_REPLY_CRC7_END_BIT;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		else if(cmd_state == S_CMD_REPLY_CRC7_END_BIT) begin
			cmd_reply <= { cmd_reply[46:0], sd_cmd };
			
			if(cmd_counter == 8'd7) begin
				cmd_state <= S_CMD_REPLY_FINISH_ONES;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		//at least 2 clock cycles required for data write
		else if(cmd_state == S_CMD_REPLY_FINISH_ONES) begin
			//check is sd_dat[0] busy for CMD7
			if(cmd_counter >= 8'd7 && (control_state != S_CTRL_CMD7 || sd_dat[0] == 1'b1)) begin
				clk_cmd_ena <= 1'b0;
				cmd_state <= S_CMD_IDLE;
				cmd_counter <= 8'd0;
			end
			else if(cmd_counter == 8'd255) begin
				cmd_state <= S_CMD_REPLY_ERROR;
				cmd_counter <= 8'd0;
			end
			else cmd_counter <= cmd_counter + 8'd1;
		end
		else if(cmd_state == S_CMD_REPLY_ERROR) begin
			clk_cmd_ena <= 1'b0;
			cmd_state <= S_CMD_IDLE;
			cmd_counter <= 8'd0;
		end	
	end
end

//------------------------------------------------------------------------------ SD clock

reg [1:0] clk_counter;

always @(posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		sd_clk      <= 1'b0;
		clk_counter <= 2'd0;
	end
	else if(clk_counter == 2'd0) begin
		if(clk_master_ena == 1'b1 && (clk_cmd_ena == 1'b1 || clk_data_ena == 1'b1)) begin
			clk_counter <= clk_counter + 2'd1;
		end
	end
	else if(clk_counter == 2'd1) begin
		sd_clk      <= 1'b1;
		clk_counter <= clk_counter + 2'd1;
	end
	else if(clk_counter == 2'd2) begin
	    clk_counter <= clk_counter + 2'd1;
	end
	else if(clk_counter == 2'd3) begin
		sd_clk      <= 1'b0;
		clk_counter <= clk_counter + 2'd1;
	end
end

endmodule

