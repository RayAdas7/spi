//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/18 09:16:50
// Design Name: 
// Module Name: 
// Project Name: 
// Target Devices: XC7VX690TFFG1761
// Tool Versions: VIVADO2018.3
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
/******************************************************************************
1)
spi 主机通用型控制器,tdata位宽为4字节，
最大单次传输支持4字节，即1字节地址+3字节数据，2字节地址+2字节数据，3字节地址+1字节数据,
也支持单次传输3字节，或者2字节，通过par_adr_sclknum和par_dat_sclknum端口来指定
如：spi单次传输为2字节地址+1字节数据，则par_adr_sclknum值为16，par_dat_sclknum值为8
2)根据SPI_3WIRE宏定义，产生对应的一组接口进行使用，同时另一组接口信号无效。
3)2个4字节的移位寄存器，每个sck边沿移出一位，另一个sck边沿移入一位。
输出移位寄存器从最高位开始左移位输出，输入移位寄存器从最低位开始左移位输入
*******************************************************************************/
//////////////////////////////////////////////////////////////////////////////////
`define SPI_4WIRE  
//`define ILA_EN
module spi_master
(
//sys 
input               clk             ,
input               rst_n           ,

//spi-3wire
`ifdef SPI_3WIRE
output              SPI3wire_SCK    ,
output              SPI3wire_CS_N   ,
inout               SPI3wire_SDIO   ,
`else 
//spi-4wire
output              SPI4wire_SCK    ,
output              SPI4wire_CS_N   ,
output              SPI4wire_MOSI   ,
input               SPI4wire_MISO   ,
`endif 
//parameter 
input   [15:0]      par_freq_div    ,//sck 分频比
input   [7:0]       par_adr_sclknum ,//cmd-cycle need SCLK numbers
input   [7:0]       par_dat_sclknum ,//dat-cycle need SCLK numbers
input               par_cpha        ,
input               par_cpol        ,
//stream send data interface     
input               tx_tvalid       ,
input   [31:0]      tx_tdata        ,//msb,the first send data is tx_tdata[31]
output              tx_tready       ,
//stream recive data interface      
output              rx_tvalid       ,
output  [31:0]      rx_tdata         //lsb,the last recive data is rx_tdata[0]
);
////////////////////////////////////////////////////
wire [7:0] SCLK_NUM;

reg [7:0] sck_cnt;
reg [15:0]div_cnt;
reg [3:0] state;
reg tx_tready_inte;

reg sck;
reg cs_n;
reg flag;
reg [31:0] shift_txdata;
reg [31:0] shift_rxdata;
reg rx_tvalid_inte;
reg [31:0] rx_tdata_inte;



wire shift_txdata_31;//发送移位寄存器的最高位，表示当前发送的串行数据

////////////////////////////////////////////////////
assign rx_tdata = rx_tdata_inte;
assign rx_tvalid = rx_tvalid_inte;
assign SCLK_NUM = par_adr_sclknum + par_dat_sclknum;
assign tx_tready = tx_tready_inte;
assign shift_txdata_31 = shift_txdata[31];

`ifdef SPI_3WIRE
wire SPI3wire_SDIO_in;
reg SPI3wire_SDIO_sel;
assign SPI3wire_SCK = sck;
assign SPI3wire_CS_N = cs_n;
assign SPI3wire_SDIO = SPI3wire_SDIO_sel ? 1'bz : shift_txdata_31;
assign SPI3wire_SDIO_in = SPI3wire_SDIO_sel ? SPI3wire_SDIO : 1'b0;
`else 
assign SPI4wire_SCK = sck;
assign SPI4wire_CS_N = cs_n;
assign SPI4wire_MOSI = shift_txdata_31;
`endif 
////////////////////////////////////////////////////
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
    begin
        state <= 'd0;
        div_cnt <= 'd0;
        sck_cnt <= 'd0;
    end
    else 
    begin
    case(state)
    'd0:    begin
                if(tx_tvalid && tx_tready)
                    state <= 'd1;
                else 
                    state <= 'd0;
            end
    'd1:    begin
                if(div_cnt < par_freq_div-1)
                    div_cnt <= div_cnt + 1'b1;
                else if(sck_cnt < SCLK_NUM+1)
                begin
                    div_cnt <= 'd0;
                    sck_cnt <= sck_cnt + 1'b1;
                end
                else 
                begin
                    div_cnt <= 'd0;
                    sck_cnt <= 'd0;
                    state <= 'd2;
                end
            end
    'd2:    begin
                state <= 'd0;
            end
    endcase
    end
end
////////////////////////////////////////////////////
//tvalid与tready同时拉高，表示将执行一次传输
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        tx_tready_inte <= 'd0;
    else if(state == 'd0)
    begin
        if(tx_tvalid && tx_tready)
            tx_tready_inte <= 'd0;
        else 
            tx_tready_inte <= 'd1;
    end
    else 
        tx_tready_inte <= 'd0;
end
////////////////////////////////////////////////////
//根据分频比和，sck脉冲个数产生对应的sck脉冲
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        sck <= 'd0;
    else if(state == 'd0)
        sck <= par_cpol;
    else if(((div_cnt == par_freq_div-1)||(div_cnt == (par_freq_div>>1)-1)) && (sck_cnt>=1) && (sck_cnt < SCLK_NUM+1))
        sck <= !sck;
    else 
        sck <= sck;
end
//片选信号提前1个sck脉冲拉低，滞后要给sck脉冲拉高
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        cs_n <= 'd1;
    else if((state==1) && (div_cnt==0) && (sck_cnt==0))
        cs_n <= 'd0;
    else if((state==1)&&(div_cnt == par_freq_div-1)&&(sck_cnt == SCLK_NUM+1))
        cs_n <= 'd1;
end
////////////////////////////////////////////////////
//发送移位寄存器，根据cpha取值，在对应时刻进行一次移位输出
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        shift_txdata <= 32'd0;
    else if(tx_tvalid && tx_tready)
        shift_txdata <= tx_tdata;
    else if(((div_cnt == par_freq_div-1)) && (sck_cnt>=1) && (sck_cnt < SCLK_NUM) && (par_cpha == 0))
        shift_txdata <= {shift_txdata[30:0],1'b0};
    else if(((div_cnt == (par_freq_div>>1)-1)) && (sck_cnt>=2) && (sck_cnt < SCLK_NUM+1)&& (par_cpha == 1))
        shift_txdata <= {shift_txdata[30:0],1'b0};
end
///////////////////////////////////////////////////
`ifdef SPI_3WIRE
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        SPI3wire_SDIO_sel <= 'd0;
    else if(flag == 'd1)
    begin
        if((par_cpha == 0))
        begin
            if(((div_cnt == par_freq_div-1)) && (sck_cnt==par_adr_sclknum))
                SPI3wire_SDIO_sel <= 'd1;
            else if(((div_cnt == par_freq_div-1)) && (sck_cnt==SCLK_NUM))
                SPI3wire_SDIO_sel <= 'd0;
        end
        else if((par_cpha == 1))
        begin
            if(((div_cnt == (par_freq_div>>1)-1)) && (sck_cnt==par_adr_sclknum+1))
                SPI3wire_SDIO_sel <= 'd1;
            else if(((div_cnt == (par_freq_div>>1)-1)) && (sck_cnt==SCLK_NUM+1))
                SPI3wire_SDIO_sel <= 'd0;        
        end
    end
    else 
        SPI3wire_SDIO_sel <= 'd0;
end
`endif 
////////////////////////////////////////////////////
//接收移位寄存器，根据cpha的取值，在对应时刻进行一次移位采样
`ifdef  SPI_3WIRE
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        shift_rxdata <= 32'd0;
    else if(state == 'd2)
        shift_rxdata <= 32'd0;
    else if(((div_cnt == (par_freq_div>>1)-1)) && (sck_cnt>=1) && (sck_cnt < SCLK_NUM+1)&& (par_cpha == 0))
        shift_rxdata <= {shift_rxdata[30:0],SPI3wire_SDIO_in};
    else if(((div_cnt == par_freq_div-1)) && (sck_cnt>=1) && (sck_cnt < SCLK_NUM+1)&& (par_cpha == 1))
        shift_rxdata <= {shift_rxdata[30:0],SPI3wire_SDIO_in};
end
`else 
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        shift_rxdata <= 32'd0;
    else if(state == 'd2)
        shift_rxdata <= 32'd0;
    else if(((div_cnt == (par_freq_div>>1)-1)) && (sck_cnt>=1) && (sck_cnt < SCLK_NUM+1)&& (par_cpha == 0))
        shift_rxdata <= {shift_rxdata[30:0],SPI4wire_MISO};
    else if(((div_cnt == par_freq_div-1)) && (sck_cnt>=1) && (sck_cnt < SCLK_NUM+1)&& (par_cpha == 1))
        shift_rxdata <= {shift_rxdata[30:0],SPI4wire_MISO};
end
`endif 
////////////////////////////////////////////////////
//根据spi通用协议，地址周期的第1个bit为0表示写，为1表示读
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
        flag <= 'd1;
    else if(tx_tvalid && tx_tready)
        flag <= tx_tdata[31];   
end

////////////////////////////////////////////////////
always@(posedge clk or negedge rst_n)
begin
    if(rst_n == 1'b0)
    begin
        rx_tvalid_inte <= 1'b0;
        rx_tdata_inte <= 32'd0;
    end
    else if(state == 'd2 && flag)
    begin
        rx_tvalid_inte <= 'd1;
        rx_tdata_inte <= shift_rxdata;
    end
    else 
        rx_tvalid_inte <= 'd0;
end

`ifdef ILA_EN
ila_128w ila_128w_u0 (
	.clk(clk), // input wire clk
	.probe0({
    SPI4wire_SCK,
    SPI4wire_CS_N,
    SPI4wire_MOSI,
    SPI4wire_MISO,
    tx_tvalid,
    tx_tdata,
    tx_tready,
    rx_tvalid,
    rx_tdata,
    flag
    }) // input wire [127:0] probe0
);
`endif 

endmodule

