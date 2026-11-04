# 原 HDMI 工程的 DMZ 板级验证

运行入口直接编译 `rtl/hdmi_media_board_top.v`，实例化原工程的
`hdmi_media_board_top`。本目录名称表示目标板卡，验证不依赖独立
`dmz_hdmi_media_top`。

```powershell
python tests/dmz_media/verify.py --tool-dir '<Icarus bin目录>'
```

- `tb_board_matrix_keys.sv`：使用 `dmz_keyboard_model.sv` 的被动开关和列上拉，
  检查KEY1..KEY4、其他全部按键、全部120种双键组合、真实鬼键通路、释放重使能、
  高阻行输出与按住KEY4复位；SCAN_CYCLES=4/17/2500各790个检查。
- `tb_hdmi_media_board_top.sv`：实际顶层、矩阵扫描、`board_key` 与四页控制器，
  COUNT=32/128检查高有效LED、四个像素下降沿释放复位、PLL丢锁、KEY1下一张、
  KEY3上一张、KEY2暂停与恢复、KEY4运行时进入设置、四页调节、松开互锁及AV/UI设置接线。
- `tb_board_key_default.sv`：检查默认 1,000,000 周期去抖、两级同步、
  短脉冲拒绝和长按单次触发。
- `tb_dmz_spi_miso.sv`：实际 `sd_spi_master` 与顶层同样的两级 MISO
  同步链；检查 80 ns SCK 半周期与返回延迟边界，详见 `MISO_MODEL.md`。

顶层控制测试使用行为模型代替 PLL、播放器、HDMI 编码与发送模块，
不证明这些模块内部算法或硬件原语正确。去抖控制用例缩短计数以加快仿真，
默认计数由单独用例验证。数字 MISO 模型不替代外部时序预算或上板测量。
仿真产物写入临时目录，结束后自动清理。

2026-10-04：顶层和默认去抖测试在启动时主动产生复位下降沿，保留全部原断言；Icarus 10.1 stable 与 12.0 devel 的三项入口均通过。完整输出见 `reports/m0_board_validation_20261004.log`。
