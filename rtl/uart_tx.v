//==============================================================================
// uart_tx.v - UART-передавач (формат 8N1: 1 старт, 8 даних LSB першим, 1 стоп)
// Лабораторна робота №3, варіант 10: UART, Verilog
//
// Параметри:
//   CLKS_PER_BIT - кількість тактів clk на один біт (= F_clk / baud),
//                  50 МГц / 115200 = 434
// Порти:
//   clk      - системний тактовий сигнал
//   rst      - синхронне скидання (активний рівень 1)
//   tx_start - імпульс 1 такт: почати передачу байта (ігнорується, якщо tx_busy)
//   tx_data  - байт для передачі (фіксується в момент tx_start)
//   tx       - послідовний вихід (у стані спокою = 1)
//   tx_busy  - 1, поки триває передача кадру
//   tx_done  - імпульс 1 такт після завершення стоп-біта
//==============================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output wire       tx_busy,
    output reg        tx_done
);

    // Розрядність лічильника тактів всередині одного біта
    localparam CNT_W = $clog2(CLKS_PER_BIT);

    // Кодування станів FSM
    localparam [1:0] S_IDLE  = 2'd0,   // очікування, tx = 1
                     S_START = 2'd1,   // стартовий біт, tx = 0
                     S_DATA  = 2'd2,   // 8 бітів даних
                     S_STOP  = 2'd3;   // стоп-біт, tx = 1

    reg [1:0]       state;     // поточний стан автомата
    reg [CNT_W-1:0] clk_cnt;   // лічильник тактів у межах біта (дільник частоти)
    reg [2:0]       bit_idx;   // номер переданого біта даних 0..7
    reg [7:0]       shreg;     // зсувний регістр даних

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            clk_cnt <= {CNT_W{1'b0}};
            bit_idx <= 3'd0;
            shreg   <= 8'd0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;                       // за замовчуванням імпульс = 0

            case (state)
                //----------------------------------------------------------
                S_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= {CNT_W{1'b0}};
                    bit_idx <= 3'd0;
                    if (tx_start) begin
                        shreg <= tx_data;          // фіксуємо дані
                        tx    <= 1'b0;             // початок стартового біта
                        state <= S_START;
                    end
                end
                //----------------------------------------------------------
                S_START: begin                     // tx = 0 протягом CLKS_PER_BIT тактів
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        tx      <= shreg[0];       // виставляємо D0
                        shreg   <= {1'b0, shreg[7:1]};
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                //----------------------------------------------------------
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        if (bit_idx == 3'd7) begin // останній біт даних завершено
                            tx    <= 1'b1;         // стоп-біт
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            tx      <= shreg[0];   // наступний біт
                            shreg   <= {1'b0, shreg[7:1]};
                        end
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                //----------------------------------------------------------
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= {CNT_W{1'b0}};
                        tx_done <= 1'b1;
                        state   <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                //----------------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
