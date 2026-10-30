# Лабораторна робота №3 — UART (Verilog), варіант 10

- `rtl/uart_tx.v`, `rtl/uart_rx.v` — передавач і приймач (8N1, 115200 бод, 50 МГц, CLKS_PER_BIT=434)
- `tb/uart_tb.v` — самоперевірний тестбенч (top: `uart_tb`)
- `docs/` — діаграми станів та формат кадру
- `.docx` — звіт (жовті поля заповнити: скріншоти, ресурси, Fmax)

Симуляція (приклад, Icarus Verilog): `iverilog -o sim rtl/*.v tb/uart_tb.v && vvp sim`
Для ModelSim/Vivado: додати три .v файли, top = uart_tb.
