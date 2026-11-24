# 几何三维太阳系独立验收

运行：

```powershell
python -B tests/solar_scene/verify.py --tool-dir PUBLIC_SOURCE/.codex/toolchains/iverilog-iccoder-2.0.10/bin
```

本目录验证 `video_scene3d.v` 和 `media_3d_control.v`。投影后的球体使用三档明暗填充，土星环按远侧、球体、近侧的顺序绘制。球体尺寸、轨道间距和初始相位按展陈画面安排。放大档的八颗行星及其轨道均变大，海王星的画布半径由 5 增至 9。

- 60 组太阳系画布逐像素比较，共 983040 个像素。独立 Python 参考按圆的方程求像素颜色，核对遮挡、土星环、八档速度、相机极限、三档缩放与边界。
- 核对 640×480 的完整 RGB 扫描、随星球移动的中文标签和右下角倍率。地月的 81 组画布与完整扫描另由 `tests/earth_moon/verify.py` 验证。
- 行为 RAM 与 EG4 BRAM32K 接口模型各执行一次画布和扫描验证。扫描过早或超过 45000 拍时，渲染器拒绝发布不完整画布。
- 控制测试覆盖按键调速、八档限幅、预设视角、方向长按、归位及设置状态。遥控调速与其他页面的按键隔离由 `tests/infrared/verify.py` 验证。
- 逐像素渲染的最大耗时见 `summary.json` 的 `render_sys_clocks`。实际器件资源和时序见整机 TD 报告。

公转相对速度按恒星公转周期设置。1× 下一个模拟日约 0.1 秒，地球约 36.5 秒一圈，海王星约 100 分钟一圈。归位将倍率恢复到 1×，公转相位继续推进。

数据核对：

- [NASA/GSFC 水星事实表](https://nssdc.gsfc.nasa.gov/planetary/factsheet/mercuryfact.html)：恒星公转周期约 87.969 天。
- [NASA/GSFC 海王星事实表](https://nssdc.gsfc.nasa.gov/planetary/factsheet/neptunefact.html)：约 60189.018 天，约 164.79 个地球年。
- [NASA/JPL 行星物理参数](https://ssd.jpl.nasa.gov/planets/phys_par.html)：恒星公转周期的定义与行星参数。
