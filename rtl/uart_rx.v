//==============================================================================
// uart_rx.v - UART-приймач (формат 8N1), вибірка в середині біта
// Лабораторна робота №3, варіант 10: UART, Verilog
//
// Параметри:
//   CLKS_PER_BIT - тактів clk на один біт (= F_clk / baud), 50 МГц/115200 = 434
// Порти:
//   clk       - системний тактовий сигнал
//   rst       - синхронне скидання (активний рівень 1)
//   rx        - послідовний вхід (асинхронний відносно clk)
//   rx_data   - прийнятий байт (дійсний, коли rx_valid = 1)
//   rx_valid  - імпульс 1 такт: байт прийнято
//   frame_err - 1, якщо стоп-біт виявився нульовим (помилка кадру);
//               оновлюється разом з rx_valid
//==============================================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        frame_err
);

    localparam CNT_W = $clog2(CLKS_PER_BIT);
    localparam [CNT_W-1:0] HALF_BIT = (CLKS_PER_BIT - 1) / 2;   // до середини біта

    localparam [1:0] S_IDLE  = 2'd0,   // очікування спаду rx
                     S_START = 2'd1,   // підтвердження старт-біта в його середині
                     S_DATA  = 2'd2,   // прийом 8 бітів, вибірка в середині кожного
                     S_STOP  = 2'd3;   // перевірка стоп-біта

    // Дворівневий синхронізатор: усуває метастабільність асинхронного входу
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    reg [1:0]       state;
    reg [CNT_W-1:0] clk_cnt;   // лічильник тактів (дільник частоти)
    reg [2:0]       bit_idx;
    reg [7:0]       shreg;     // зсувний регістр приймання (LSB приходить першим)

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_cnt   <= {CNT_W{1'b0}};
            bit_idx   <= 3'd0;
            shreg     <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                //----------------------------------------------------------
                S_IDLE: begin
                    clk_cnt <= {CNT_W{1'b0}};
                    bit_idx <= 3'd0;
                    if (rx_sync == 1'b0)           // виявлено спад -> можливий старт-біт
                        state <= S_START;
                end
                //----------------------------------------------------------
                S_START: begin
                    if (clk_cnt == HALF_BIT) begin // середина старт-біта
                        clk_cnt <= {CNT_W{1'b0}};
                        if (rx_sync == 1'b0)       // старт підтверджено
                            state <= S_DATA;
                        else                       // хибний імпульс (завада)
                            state <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                //----------------------------------------------------------
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin   // середина біта даних
                        clk_cnt <= {CNT_W{1'b0}};
                        shreg   <= {rx_sync, shreg[7:1]};    // LSB першим
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                //----------------------------------------------------------
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin   // середина стоп-біта
                        clk_cnt   <= {CNT_W{1'b0}};
                        rx_data   <= shreg;
                        rx_valid  <= 1'b1;
                        frame_err <= ~rx_sync;               // стоп має бути 1
                        state     <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                //----------------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
