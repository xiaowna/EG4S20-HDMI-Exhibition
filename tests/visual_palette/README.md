# 全流程配色专项验收

首页、中文设置、音乐提示、准备进度与滚动字幕统一为深海蓝底、石板面板、薄荷焦点与暖白文字；少量琥珀色用于强调。原始比赛标识、挑战杯标识、烟花配色、IR 彩蛋字形和全部字体 ROM 保持原样。

生产改动仅为五个模块中的 `24'hRRGGBB` 常量。将这些常量正规化后，前后源码逐字相同；没有增加比较器、状态机、乘法器、RAM 或 DSP 实例。颜色位型会影响综合打包，最终 LUT、Slice 与时序仍需以整工程 TD 报告为准。

运行：

```powershell
python -B tests/visual_palette/verify.py --tool-dir PUBLIC_SOURCE/.codex/toolchains/iverilog-iccoder-2.0.10/bin
python -B tests/music_toast/verify.py --tool-dir PUBLIC_SOURCE/.codex/toolchains/iverilog-iccoder-2.0.10/bin
python -B tests/osd_lookup/verify.py --tool-dir PUBLIC_SOURCE/.codex/toolchains/iverilog-iccoder-2.0.10/bin
```

专项结果：3,345,424 个独立 RGB 像素向量通过，旧 OSD 的 9,999,624 次公共输出比较通过；音乐提示的 315 项时序检查通过，仍为 238 帧完整显示、60 帧渐隐。覆盖首页五卡与双向轮播、中文设置、准备/完成/错误状态、字幕全部 17 档边缘透明度、RTC 输入框与保存状态，以及四首音乐/八个音符姿态/全部渐隐档位。

旧 OSD 参考代码只在测试临时目录中按公开颜色映射转换，其逻辑、字体与历史快照不修改。原先“黄色”测试的近似 RGB 阈值改为新琥珀色精确比较，避免将正常换色误判成字幕丢失。

`palette_overview.png`、`home.png`、`settings.png` 和 `clock_settings.png` 是 Icarus 实际 RTL 输出的软仿真像素；`progress.png` 是与实际 RTL 逐像素一致的独立参考图。总览中进度条和音乐提示只裁剪展示已验证像素，没有新增产品界面。

正文、次级文字、薄荷焦点与面板的静态亮度对比分别为 13.02、6.22、8.72。照片、屏幕设置和 HDMI 实际观感仍需上板验收。本专项未运行 TD、未发布桌面包、未写 TF 卡，也未下载开发板。
