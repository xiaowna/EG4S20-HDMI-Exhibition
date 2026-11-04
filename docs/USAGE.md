# 工程使用与验证说明

代码提交包，整理日期：2026-11-01。硬件为硬木课堂 DMZ-EG4S20（EG4S20BG256）核心板与 M0 底板。主工程是 `HDMI_media_board_WAV.al`，顶层是 `hdmi_media_board_top`。

本包采用已经完成上板验证的最终源码及位流，包含红外 0045 切换太阳系/地月模型，以及亮度、对比度实际作用于照片的修复。整理过程中没有修改生产 RTL、管脚约束、时序约束或现有位流。

## 首次使用

1. 完整解压，再操作工程；不要直接在压缩包内打开文件。建议路径为 `C:/FPGA/EG4S20_HDMI_Source`。
2. 安装 Python 3.10 或以上，并确保 `python` 在 PATH 中。参考开发环境为 Tang Dynasty 6.2.1 Engineer（6.2.168.116）。
3. 双击 `打开TD工程.cmd`。此入口先将工程根路径重定位到当前解压目录，再校验源码、管脚和已验证的构建参数，最后打开 TD。
4. 下载现成程序时，使用根目录 `HDMI_media_board_WAV.bit`；Program SRAM 用于临时运行，Flash 固化用于断电重启。
5. 需要重新生成位流时，双击 `重新生成位流.cmd`，等待综合、布局布线、保持修复及时序检查通过。负时序不会被忽略。

工程没有附带 TD、Python 或 Icarus 安装程序。GUI 启动入口默认适配上述参考版本及默认安装目录。TD 安装在其他位置时，优先使用下列命令行构建入口；GUI 还需要同步配置流程工具中的 TD 根目录，仅修改 `hdmiTd` 不够。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_td.ps1 -Action Build -TdExecutable "D:/Anlogic/TD/bin/td_commands_prompt.exe"
```

GUI 构建入口会检查 TD 的 MultiSeed 路径，并安装本工程的 GUI 配置分发脚本；安装前会在 `reports` 中备份相关 TD 脚本。默认入口对应上述参考版本。若工具版本不同，请先核对相关脚本兼容性；命令行 Build 使用包内明确的构建流程。

## 已完成的功能

- HDMI 640×480 图像和声音输出，四个图册专题与一个三维展示入口。
- TF 卡 FAT32 读取：`TOPIC1` 至 `TOPIC4` 各最多 6 张 BMP，总计最多 24 张；音乐共用根目录，最多 4 首 WAV。
- 手动浏览、自动轮播、三种转场、底部图片说明、专题末页图文布局、中文设置、音乐提示和滚动标语。
- 129 档亮度与 101 档对比度；彩色 32 柱、512 点 FFT 音频频谱。
- 太阳系与地月几何线框模型、方向旋转、预设视角、星球名称跟随、公转周期显示及地月缩放。
- 实体按键与固定红外码控制；DS1302 实时时钟读取和中文菜单校时。
- 最终镜像已完成固化、断电启动、媒体播放、交互、图像调节、三维及校时的实机验证。

输入图片支持 24 位、非压缩 BMP：640×480 原尺寸，或 320×240 最近邻 2 倍放大。音频支持 48 kHz、双声道、16/24 位有符号小端 PCM WAV；不把 MP3 改扩展名当作 WAV 使用。

本包是代码与复现资料包，不包含 TF 卡歌曲、24 张展图、原始照片和安装软件。现有字库及界面 ROM 已内嵌在 RTL，编译不需要访问原电脑的素材目录。重新制作素材可使用 `tools/prepare_topic_media.py` 等工具；修改中文说明并重新生成 ROM 时，通过 `generate_intro_assets.py --delivery` 指定自己的素材来源。

## 运行与遥控

SW0 向下为复位、向上运行；SW7=0 为演示模式，SW7=1 为产品模式。产品模式先进入首页，选入图册后开始浏览，可在菜单关闭轮播或通过确认键暂停。

|操作|实体按键|红外四位显示码|
|---|---|---|
|向右 / 向左|KEY1 / KEY3（首页、图册）|0009 / 0007|
|确认、暂停/继续；三维预设视角|KEY2|0015|
|设置|KEY4|0043|
|逐级返回|按页面提示|000D|
|主页|KEY0（产品模式）|0016|
|三维向上 / 向下|KEY14 / KEY6|0040 / 0019|
|三维向左 / 向右|KEY11 / KEY9|0007 / 0009|
|三维复位|KEY10|通过预设视角调整|
|太阳系 / 地月切换|KEY5|0045|
|地月缩小 / 放大|KEY7 / KEY8|本版没有独立红外缩放键|

红外固定地址为 00，指令码已固化，不需要每次上电学习。外设按 `interfaces/product_io_pins.json`、`interfaces/infrared_fixed_keys.json` 和 `board.adc` 核对；信号使用 3.3 V 电平并共地，不按杜邦线颜色判断信号。

## 仿真与检查

安装 Icarus Verilog（参考版本 12.0），将其 bin 目录加入 PATH，或设置环境变量 `IVERILOG_BIN`。Python 图像相关回归需要 Pillow，可执行 `python -m pip install -r requirements.txt`。

```powershell
# 初始化前检查解压内容的完整性（重定位会有意修改 .al）
python -B tools/verify_package.py

# 解压后先重定位及严格检查，不打开 GUI
python -B tools/prepare_td_project.py --root . --relocate

# 默认三组回归：字幕、专题目录和首页/菜单控制
python -B tools/run_display_sim.py --scope quick --tool-dir "D:/iverilog/bin"

# 三维及红外回归
python -B tools/run_display_sim.py --scope 3d --tool-dir "D:/iverilog/bin"

# 亮度/对比度实际输出像素回归
python -B tests/fine_adjust/verify_pixel_path.py --tool-dir "D:/iverilog/bin"

# TD 顶层展开，不执行完整物理构建
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_td.ps1 -Action Check

```

双击 `运行功能仿真.cmd` 也可运行默认三组回归。它是功能仿真，不是 TD 的 phy_1/bitgen；bitgen 失败应检查物理构建日志。

本次整理的工程静态检查、TD 顶层展开及 12 项迁移/选项恢复测试通过。默认回归中的字幕组通过，专题目录子测试已完成，但其最终整链路音视频用例触及 240 秒时限；另一次最终照片像素回归触及 300 秒时限。这两项本次没有记为通过，详情见 `reports/package_validation/summary.json`。本次没有修改生产 RTL 或以未完成仿真替换此前的验收结论。

`tools/run_regression.py` 保留原完整开发回归入口。部分历史素材质量检查（尤其 `tests/intro_text/verify.py`）还要求原始照片、展图与原字体的来源哈希，因此本代码包不声称能在未提供原素材的电脑上完成全部历史回归。包内保留 30 份实际被测试引用的历史 RTL 基准，不携带重复的历史工作树和大型构建数据库。

## 目录说明

|位置|内容|
|---|---|
|`HDMI_media_board_WAV.al`、`build_wav_project.tcl`|主 TD 工程与构建入口|
|`rtl/`、`board.adc`、`board.sdc`|84 份 RTL、引脚与时序约束|
|`HDMI_media_board_WAV.bit`|已经验证的最终位流|
|`assets/`、`interfaces/`、`constraints/`|离线界面资源、外设定义和约束依据|
|`tools/`、`tests/`、`sources.txt`|工程检查、素材工具和仿真测试|
|`reports/route_completion_20261028/accepted/`|最终资源、时序与回读报告|
|`reports/*/before/`|少量历史等价回归基准，不参与生产综合|
|`reports/package_validation/`|本次上传包的实际检查记录|
|`docs/`|开发历史、接线与使用记录；带日期的“待验收”等标题属于当时的历史状态，最终完成情况以本 README 为准|
|`DMZ_*`、`dmz_*`、`build_dmz_*`|保留的小型数码管、彩条等诊断辅助工程，不是主播放器入口|
|`PACKAGE_MANIFEST.json`|提交文件及 SHA256 清单|

最终物理实现使用 18,929/19,600 LUT、9,591/9,800 Slice；Setup/Hold 余量分别为 +0.325/+0.024 ns，TNS 为 0。现有位流直接复制自该已验证版本；本次整理不重新运行长时间物理构建。

本包排除了 Git 元数据、TD Runs 缓存、`.db` 数据库、旧位流副本、临时波形、日志缓存、归档试验及歌曲素材。解压后重新构建会自行产生 Runs 和报告；不要从历史报告所记载的原电脑绝对路径寻找工程。
