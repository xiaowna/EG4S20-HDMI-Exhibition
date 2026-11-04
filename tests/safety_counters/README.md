# 有界保护计数器的等价验证

运行 `python tests/safety_counters/verify.py --tool-dir "Icarus bin目录"`。
只读基准位于 `reports/safety_counters_20261018/before/worktree/rtl`，应与此测试一起保留。

驱动器在临时目录生成新旧双实例和比较监控，不把监控写入生产RTL。
逐周期比较全部公开输出，要求每个已实例化监控器的比较次数非零，并核对12模块覆盖及源码摘要。
默认42次仿真；`--sd-only`只运行12种SD阈值配置。SD每种配置覆盖8个成功/异常/复位场景。

测试源码不应添加到TD板级Design Source。总回归入口已经包含本专项，测试代码不会成为FPGA硬件。
三类故障注入和较迟SPI响应的补充验证见本阶段报告中的 `mutation_check.py`；该脚本只修改临时副本。

2026-10-18 四键扩展：播放控制增加prev_pulse。原12模块对比仍完整保留，
播放控制的参考实例不接新增端口，并显式断言prev_pulse恒为0；逆向导航的
1～4张循环、暂停、加载背压和待处理方向由tests/four_key独立验证。
