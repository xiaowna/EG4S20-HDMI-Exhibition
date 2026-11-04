# EG4S20 HDMI 多媒体展陈终端

![作品封面](docs/images/cover.png)

基于安路 **EG4S20 FPGA** 的独立多媒体展示终端，面向展台导览、门店展示和科普教育。系统从TF卡读取图像与音频，结合中文交互界面、彩色FFT频谱和实时三维线框模型，通过HDMI同步输出画面与声音。

**关键词：视听融合 · 交互展陈 · 三维可视化**

## 功能

- 四个图片专题与一个三维入口；每个专题最多6张BMP，总计24张。
- 手动翻页、自动轮播、三类转场、底部说明与专题末页图文介绍。
- 根目录最多4首48 kHz双声道PCM WAV，支持16/24位音频与选曲。
- 中文设置、129档亮度、101档对比度、短暂音乐提示。
- 实际音频样本驱动的512点FFT、32柱彩色频谱。
- 可交互的太阳系/地月线框模型、预设视角、星球名称、公转周期与地月缩放。
- 实体按键、固定NEC红外码、DS1302实时时钟读取及校时。
- 程序固化后可断电重新启动，独立运行。

## 硬件与输入格式

|项目|配置|
|---|---|
|核心板|硬木课堂DMZ-EG4S20，EG4S20BG256|
|扩展板|M0底板，HDMI、TF卡与SDRAM|
|输出|640×480，约59.52 Hz，HDMI图像和音频|
|图片|24位非压缩BMP，640×480或320×240最近邻2倍放大|
|音频|48 kHz、双声道、16/24位小端PCM WAV|
|外设|3.3 V NEC红外接收模块、DS1302；信号必须共地|

仓库包含可直接编译的ROM数据、完整RTL、约束、工具及测试台；歌曲、原始展图、官方安装软件和签字材料不在源码中。

## 快速开始

参考环境：Windows、Tang Dynasty 6.2.1 Engineer（6.2.168.116）、Python 3.10+；仿真使用Icarus Verilog 12.0。

```powershell
python -m pip install -r requirements.txt
# 克隆后先把TD工程重定位到当前目录
python -B tools/prepare_td_project.py --root . --relocate
python -B tools/check_project.py --root .
```

随后运行根目录的“打开TD工程.cmd”。GUI入口默认使用C:/Anlogic下的上述参考版本，会备份并配置该工程所需TD流程脚本。其他安装位置可使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_td.ps1 -Action Build -TdExecutable "D:/Anlogic/TD/bin/td_commands_prompt.exe"
```

根目录HDMI_media_board_WAV.bit是已通过物理实现及上板验证的固件。Program SRAM用于临时运行，Flash固化后可断电启动。

## TF卡与操作

```text
TF卡根目录/
├─ TOPIC1/   最多6张BMP
├─ TOPIC2/   最多6张BMP
├─ TOPIC3/   最多6张BMP
├─ TOPIC4/   最多6张BMP
├─ MUSIC1.WAV
├─ MUSIC2.WAV
├─ MUSIC3.WAV
└─ MUSIC4.WAV
```

采用FAT32与兼容的8.3短文件名。素材可通过tools/prepare_topic_media.py检查，工具不会自动格式化存储卡。中文说明与字形通过电脑端工具生成ROM后重新构建，歌曲名称当前显示为音乐1～4。

|操作|按键/红外命令|
|---|---|
|首页/图册左右|KEY1、KEY3 / 0009、0007|
|确认、暂停、预设视角|KEY2 / 0015|
|设置、返回、主页|KEY4 / 0043、000D、0016|
|三维上下左右|KEY14/6/11/9 / 0040/0019/0007/0009|
|太阳系与地月切换|KEY5 / 0045|
|三维复位|KEY10|
|地月缩小/放大|KEY7/KEY8|

SW0向下复位、向上运行；SW7=0演示模式、SW7=1产品模式。红外地址为00，无需每次学习。具体引脚见board.adc与interfaces/。

## 验证与资源

|资源|使用量|器件总量|
|---|---:|---:|
|LUT|18,929|19,600|
|Slice|9,591|9,800|
|寄存器|8,821|19,600|
|RAM9K|58|64|
|RAM32K|13|16|
|DSP|13|29|
|PLL|1|4|

已验收版本的建立/保持余量为+0.325/+0.024 ns，TNS均为0；这份源码保留相同的生产RTL与约束。后续功能变化应重新核算物理资源和时序。

```powershell
python -B tools/run_display_sim.py --scope quick --tool-dir "C:/iverilog/bin"
python -B tools/run_display_sim.py --scope 3d --tool-dir "C:/iverilog/bin"
python -B -m unittest tests.test_td_project_prepare tests.test_td_project_relocate -v
```

先运行上面的路径初始化命令，再运行工具单元测试。部分完整链路仿真较耗时；原打包复测有240/300秒超时记录，不将超时视为通过。历史素材溯源QA依赖未随仓库分发的原图及字体；公开元数据中的外部个人路径已脱敏。详细范围见[使用说明](docs/USAGE.md)。reports/*/before下是实际回归基准，应保留。

## 目录

- rtl/：84份RTL与器件封装；board.adc/board.sdc为板级约束。
- assets/、interfaces/：界面、字库、模型和外设配置。
- tools/、tests/、sources.txt：检查、构建、素材工具和测试台。
- reports/*/before/：历史等价回归使用的少量基准源码。
- docs/：使用说明与封面。

## 许可证

原创代码采用[MIT许可证](LICENSE)。第三方标志、字体图形、原语库和素材不因MIT改变授权条件，详见[NOTICE](NOTICE.md)。
