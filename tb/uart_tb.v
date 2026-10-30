//==============================================================================
// uart_tb.v - самоперевірний тестбенч UART (Tx + Rx), 8N1, 115200 бод, 50 МГц
//
// Тест 1: Tx -> Rx (loopback): 8 тестових байтів, перевірка прийнятих даних.
// Тест 2: незалежний монітор перевіряє форму кадру на лінії TxD
//         (старт = 0, 8 бітів LSB першим, стоп = 1).
// Тест 3: імітація зовнішнього пристрою -> окремий приймач (перевірка Rx).
// Тест 4: кадр з хибним стоп-бітом -> frame_err = 1.
// Тест 5: короткий хибний імпульс на rx (завада) не дає прийнятого байта.
//==============================================================================
`timescale 1ns/1ps

module uart_tb;

    localparam CLK_PERIOD   = 20;                       // 50 МГц
    localparam CLKS_PER_BIT = 434;                      // 50e6 / 115200
    localparam BIT_NS       = CLKS_PER_BIT * CLK_PERIOD; // 8680 нс

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #(CLK_PERIOD/2) clk = ~clk;

    //---------------- DUT: передавач ----------------
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'd0;
    wire       tx_line, tx_busy, tx_done;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(tx_line), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    //---------------- DUT: приймач у loopback ----------------
    wire [7:0] lb_data;
    wire       lb_valid, lb_ferr;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx_lb (
        .clk(clk), .rst(rst), .rx(tx_line),
        .rx_data(lb_data), .rx_valid(lb_valid), .frame_err(lb_ferr)
    );

    //---------------- DUT: приймач від "зовнішнього пристрою" ----------------
    reg        ext_rx = 1'b1;
    wire [7:0] ext_data;
    wire       ext_valid, ext_ferr;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx_ext (
        .clk(clk), .rst(rst), .rx(ext_rx),
        .rx_data(ext_data), .rx_valid(ext_valid), .frame_err(ext_ferr)
    );

    //---------------- службові змінні ----------------
    integer errors = 0;
    integer checks = 0;
    reg [7:0] vec [0:7];
    integer   i;

    // Захоплення результату приймача "ext"
    reg [7:0] got_data = 8'd0;
    reg       got_ferr = 1'b0;
    reg       got_flag = 1'b0;
    always @(posedge ext_valid) begin
        got_data = ext_data;
        got_ferr = ext_ferr;
        got_flag = 1'b1;
    end

    //---------------- Тест 1: передача байта і перевірка loopback ----------------
    task send_and_check_loopback(input [7:0] d);
        begin
            @(negedge clk);
            tx_data  = d;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;
            @(posedge lb_valid);
            #1;
            checks = checks + 1;
            if (lb_data !== d || lb_ferr !== 1'b0) begin
                errors = errors + 1;
                $display("[%0t] FAIL loopback: sent %h, received %h, ferr=%b", $time, d, lb_data, lb_ferr);
            end else
                $display("[%0t] PASS loopback: sent %h, received %h", $time, d, lb_data);
            wait (!tx_busy);
            repeat (5) @(posedge clk);
        end
    endtask

    //---------------- Тест 2: монітор форми кадру на TxD ----------------
    reg [7:0] mon_data;
    integer   mi;
    always @(negedge tx_line) begin
        #(BIT_NS/2);                                     // середина старт-біта
        checks = checks + 1;
        if (tx_line !== 1'b0) begin
            errors = errors + 1; $display("[%0t] FAIL monitor: start bit != 0", $time);
        end
        for (mi = 0; mi < 8; mi = mi + 1) begin
            #(BIT_NS);
            mon_data[mi] = tx_line;                      // LSB першим
        end
        #(BIT_NS);                                       // середина стоп-біта
        checks = checks + 1;
        if (tx_line !== 1'b1) begin
            errors = errors + 1; $display("[%0t] FAIL monitor: stop bit != 1", $time);
        end
        checks = checks + 1;
        if (mon_data !== tx_data) begin
            errors = errors + 1;
            $display("[%0t] FAIL monitor: line carries %h, expected %h", $time, mon_data, tx_data);
        end else
            $display("[%0t] PASS monitor: TxD frame = %h", $time, mon_data);
    end

    //---------------- Тест 3/4: імітація зовнішнього передавача ----------------
    task ext_send(input [7:0] d, input stop_bit);
        integer k;
        begin
            got_flag = 1'b0;
            ext_rx = 1'b0;            #(BIT_NS);         // старт-біт
            for (k = 0; k < 8; k = k + 1) begin
                ext_rx = d[k];        #(BIT_NS);         // біти даних, LSB першим
            end
            ext_rx = stop_bit;        #(BIT_NS);         // стоп-біт
            ext_rx = 1'b1;
            #(BIT_NS);                                   // пауза між кадрами
        end
    endtask

    task check_ext(input [7:0] d, input exp_ferr);
        begin
            checks = checks + 1;
            if (!got_flag || got_data !== d || got_ferr !== exp_ferr) begin
                errors = errors + 1;
                $display("[%0t] FAIL ext Rx: expected %h/ferr=%b, got flag=%b data=%h ferr=%b",
                         $time, d, exp_ferr, got_flag, got_data, got_ferr);
            end else
                $display("[%0t] PASS ext Rx: received %h, frame_err=%b", $time, got_data, got_ferr);
        end
    endtask

    //---------------- Головний сценарій ----------------
    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb);

        vec[0] = 8'h55; vec[1] = 8'hAA; vec[2] = 8'h00; vec[3] = 8'hFF;
        vec[4] = 8'hA5; vec[5] = 8'h3C; vec[6] = 8'h81; vec[7] = 8'h4B;

        // Скидання
        rst = 1'b1;
        repeat (10) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        repeat (10) @(posedge clk);

        $display("=== Test 1/2: Tx -> Rx loopback + TxD monitor ===");
        for (i = 0; i < 8; i = i + 1)
            send_and_check_loopback(vec[i]);

        $display("=== Test 3: external device -> Rx ===");
        ext_send(8'h55, 1'b1); check_ext(8'h55, 1'b0);
        ext_send(8'hC3, 1'b1); check_ext(8'hC3, 1'b0);
        ext_send(8'h7E, 1'b1); check_ext(8'h7E, 1'b0);

        $display("=== Test 4: framing error (stop bit = 0) ===");
        ext_send(8'h96, 1'b0); check_ext(8'h96, 1'b1);

        $display("=== Test 5: glitch on rx (shorter than half a bit) ===");
        got_flag = 1'b0;
        ext_rx = 1'b0; #(BIT_NS/4); ext_rx = 1'b1;
        #(BIT_NS*12);
        checks = checks + 1;
        if (got_flag) begin
            errors = errors + 1; $display("[%0t] FAIL glitch: false byte received", $time);
        end else
            $display("[%0t] PASS glitch ignored", $time);

        $display("==============================================");
        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
        else             $display("TESTS FAILED: %0d errors of %0d checks", errors, checks);
        $display("==============================================");
        $finish;
    end

    // Захист від зависання симуляції
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
