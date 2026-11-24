"""板级工程静态检查；不修改 TD 工程，也不代替综合和电气检查。"""
from pathlib import Path
import argparse
import re
import sys
import xml.etree.ElementTree as ET
if __package__:
    from .td_gui_profile import check_source as check_gui_profile_source
else:
    from td_gui_profile import check_source as check_gui_profile_source

PROJECT = "HDMI_media_board_WAV.al"
TOP = "hdmi_media_board_top"
GUI_SEED = "19"
TF_PORTS = frozenset({"sd_sck", "sd_mosi", "sd_miso", "sd_cs"})


def require(condition, message):
    if not condition:
        raise ValueError(message)


def without_comments(text):
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def check_project(root, *, project=PROJECT, top=TOP, adc_file="board.adc",
                  sdc_file="board.sdc", allowed_missing_ports=()):
    root = Path(root).resolve()
    raw = (root / project).read_text(encoding="utf-8-sig")
    # TD 自身会写出 UsedInP&R；仅在内存中转义，绝不改写原文件。
    xml = ET.fromstring(re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9A-Fa-f]+;)", "&amp;", raw))
    require(xml.findtext("HardWare/Device") == "EG4S20BG256", "工程器件不是 EG4S20BG256")
    require(xml.findtext("TOP_MODULE/MODULE") == top, f"顶层必须为 {top}")
    require(Path(xml.attrib["Path"]).resolve() == root, "TD 工程 Path 仍指向其他目录，请先更新工程路径")
    if project == PROJECT and top == TOP:
        physical_run = xml.find("Runs/Run[@Name='phy_1'][@Type='PhysicalDesign']")
        seed_config = xml.find("MultiSeed/Property")
        expected_seed_config = {
            "Enable": "true", "GenBit": "true", "EndStep": "route", "Random": "false",
            "Num": "1", "Init": GUI_SEED, "Jobs": "1", "Save": "1", "Step": "1",
        }
        require(physical_run is not None and seed_config is not None and
                all(seed_config.get(name) == value for name, value in expected_seed_config.items()) and
                (xml.findtext("MultiSeed/Seeds") or "").split() == [GUI_SEED] and
                seed_config.find("Filter") is not None and
                seed_config.find("Filter").get("enabled") == "false",
                f"当前 GUI 必须启用固定 seed {GUI_SEED} 的单次 MultiSeed 构建")
        # TD's GUI accepts strategies 1..5 and rewrites the base value to 5
        # when the project also specifies pr_strategy 5 in UserParams.
        # The project-owned flow applies the qualified strategy before place.
        check_gui_profile_source(root)
        require(physical_run.findtext("Strategy/PlaceProperty/pr_strategy") in {None, "1", "5"} and
                [" ".join((p.text or "").split()) for p in physical_run.findall("UserParams/param")
                 if re.search(r"\bplace\s+pr_strategy\b", p.text or "")] in [[], ["set_param place pr_strategy 5"]],
                "pr_strategy=5 必须由工程GUI脚本应用，GUI基础属性应为有效值1或5")
        require(physical_run.findtext("Strategy/RouteProperty/effort") == "routability" and
                physical_run.findtext("Strategy/RouteProperty/post_route_opt") in {None, "auto", "high"} and
                [" ".join((p.text or "").split()) for p in physical_run.findall("UserParams/param")
                 if re.search(r"\broute\s+effort\b", p.text or "")] == ["set_param route effort routability"] and
                "set_param route effort routability" in (root / "build_wav_project.tcl").read_text(encoding="utf-8-sig"),
                "当前圆球与视觉升级版本必须保留经过验证的 route effort routability 属性、more options 与命令行设置")
    files = xml.findall("Source_Files/*/File")
    seen = set()
    modules = {}
    auto_excluded = set()
    rtl_count = 0
    compile_orders = set()
    for entry in files:
        name = entry.attrib["Path"]
        path = (root / name).resolve()
        require(path.is_relative_to(root), f"工程依赖外部文件：{name}")
        require(path.is_file(), f"工程缺少文件：{name}")
        require(path not in seen, f"重复登记文件：{name}")
        seen.add(path)
        if path.suffix.lower() != ".v":
            continue
        rtl_count += 1
        attrs = {a.attrib["Name"]: a.attrib["Val"] for a in entry.findall("FileInfo/Attr")}
        if "CompileOrder" in attrs:
            require(attrs["CompileOrder"] not in compile_orders, f"Verilog CompileOrder 重复：{name}")
            compile_orders.add(attrs["CompileOrder"])
        if attrs.get("AutoExcluded") == "true" and attrs.get("UsedInSyn") != "false":
            auto_excluded.add(path)
        if attrs.get("AutoExcluded") == "true" or attrs.get("UsedInSyn") == "false":
            continue
        for module in re.findall(r"\bmodule\s+(\w+)", without_comments(path.read_text(encoding="utf-8-sig"))):
            require(module not in modules, f"重复综合模块：{module}")
            modules[module] = path
    local_definitions = {}
    for path in (root / "rtl").glob("*.v"):
        if path.is_file():
            for module in re.findall(r"\bmodule\s+(\w+)", without_comments(path.read_text(encoding="utf-8-sig"))):
                local_definitions.setdefault(module, []).append(path.relative_to(root).as_posix())
    active_text = {path: without_comments(path.read_text(encoding="utf-8-sig"))
                   for path in set(modules.values())}
    # TD marks the constant-inactive legacy waveform AutoExcluded on reload.
    # Accept that one known generate branch only while the product explicitly
    # selects FFT. Missing files/registrations and explicit UsedInSyn=false
    # still fail, as do exclusions of any enabled subtitle/FFT/helper module.
    top_text = active_text.get(modules.get(top), "")
    av_text = active_text.get(modules.get("hdmi_av_output"), "")
    inactive_wave = (project == PROJECT and top == TOP and
                    re.search(r"\.SPECTRUM_FFT\s*\(\s*1\s*\)", top_text) and
                    re.search(r"generate\s+if\(SPECTRUM_FFT\).*?end\s+else\s+begin:waveform\s+video_audio_waveform\b", av_text, re.S))
    unavailable = []
    # Limited to the current handwritten instance syntax, including #(...).
    # Unreferenced diagnostic modules may remain in their separate projects;
    # TD elaboration remains the authority for the complete Verilog grammar.
    for module in sorted(local_definitions.keys() - modules.keys()):
        if (module == "video_audio_waveform" and inactive_wave and
                (root / "rtl/video_audio_waveform.v").resolve() in auto_excluded):
            continue
        instance = r"\b" + re.escape(module) + r"\b\s*(?:#\s*\([^;]*?\)\s*)?[A-Za-z_]\w*\s*\("
        users = sorted(path.relative_to(root).as_posix() for path, text in active_text.items()
                       if re.search(instance, text, re.S))
        if users:
            unavailable.append(f"{module} (定义={sorted(local_definitions[module])}；引用={users})")
    require(not unavailable, f"本地模块依赖未参与综合：{unavailable}")
    require(top in modules, "顶层源码未参与综合")
    for constraint in (adc_file, sdc_file):
        require((root / constraint).resolve() in seen, f"工程未登记约束：{constraint}")
    sources = (root / "sources.txt").read_text(encoding="utf-8-sig").splitlines()
    sources = [s.strip() for s in sources if s.strip()]
    require(len(sources) == len(set(sources)), "sources.txt 有重复项")
    for source in sources:
        require((root / "rtl" / source).resolve() in seen, f"仿真源未登记到工程：{source}")

    # 当前顶层是 ANSI 声明、固定整数位宽；未知语法明确报错，不猜测端口。
    text = without_comments(modules[top].read_text(encoding="utf-8-sig"))
    header = re.search(r"\bmodule\s+" + re.escape(top) + r"\s*(?:#\s*\([^;]*?\)\s*)?\((.*?)\)\s*;", text, re.S)
    if top == TOP and re.search(r"\.CHINESE_SUBTITLE\s*\(\s*1\s*\)", text):
        # Keep the intended profile visible in More Options. Enforcement is
        # in the project-owned editable flow, not this GUI annotation alone.
        font_options = [" ".join((entry.text or "").split()) for entry in xml.findall(
            "Runs/Run[@Name='syn_1']/UserParams/param") if "eram_init" in (entry.text or "")]
        require(font_options == ["set_param gate eram_init on"],
                "GUI 重开后仍需 eram_init=on：syn_1 的 more options 必须保留唯一的 set_param gate eram_init on")
        if re.search(r"localparam(?:\s+integer)?\s+MAX_IMAGES\s*=\s*24\b", text):
            # The solar build fits with the measured area/packing profile.
            # Catch a GUI reopen that silently drops either setting.
            options = [" ".join((entry.text or "").split()) for entry in xml.findall(
                "Runs/Run[@Name='syn_1']/UserParams/param")]
            for key in ("opt_area", "pack_effort"):
                require([s for s in options if re.search(r"\bgate\s+" + key + r"\b", s)] ==
                        [f"set_param gate {key} high"], f"太阳系工程必须保留 gate {key}=high")
                # Keep private GUI fields at defaults to avoid the reopen
                # Revert dialog. The checked project helper applies high.
                native = {None, "medium", "high"} if key == "opt_area" else {"high"}
                require(xml.findtext(f"Runs/Run[@Name='syn_1']/Strategy/GateProperty/{key}") in native,
                        f"GUI 基础属性不受支持：{key}，实际优化由工程脚本设置")
    require(header is not None, "无法解析当前顶层端口声明")
    parts = re.split(r"\b(input|output|inout)\b", header.group(1))
    require(not parts[0].strip(), "顶层不是支持的 ANSI 端口声明")
    ports = set()
    for index in range(1, len(parts), 2):
        declaration = re.sub(r"\b(wire|reg|signed)\b", "", parts[index + 1]).strip().rstrip(",").strip()
        width = re.match(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*(.*)", declaration, re.S)
        names = width.group(3) if width else declaration
        for name in names.split(","):
            name = name.strip()
            require(re.fullmatch(r"[A-Za-z_]\w*", name), f"不支持的端口语法：{name}")
            bits = [name] if not width else [f"{name}[{i}]" for i in range(min(int(width[1]), int(width[2])), max(int(width[1]), int(width[2])) + 1)]
            for bit in bits:
                require(bit not in ports, f"重复端口：{bit}")
                ports.add(bit)
    adc = re.sub(r"#[^\n]*", "", (root / adc_file).read_text(encoding="utf-8-sig"))
    assignments = re.findall(r"set_pin_assignment\s*\{\s*([^}]+?)\s*\}\s*\{([^}]+)\}", adc)
    assigned = set()
    pads = set()
    for port, body in assignments:
        location = re.search(r"\bLOCATION\s*=\s*(\w+)\s*;", body)
        require(location is not None, f"端口缺少 LOCATION：{port}")
        require(port not in assigned, f"重复管脚约束：{port}")
        require(location[1].upper() not in pads, f"物理管脚冲突：{location[1]}")
        assigned.add(port)
        pads.add(location[1].upper())
    allowed = set(allowed_missing_ports)
    require(allowed <= ports, f"允许缺失的端口不存在：{sorted(allowed-ports)}")
    missing = ports - assigned
    require(missing <= allowed and not assigned-ports,
            f"端口与 ADC 不一致：未约束={sorted(missing)}；多余约束={sorted(assigned-ports)}")
    if not allowed:
        require(not re.search(r"(?m)^\s*error\s+\{HDMI_BOARD_HARDWARE_INCOMPLETE\b", adc),
                "HDMI_BOARD_HARDWARE_INCOMPLETE：扩展板电气、TF 映射或时序审核尚未完成")
    result = {"project_files": len(files), "rtl_files": rtl_count,
              "top_ports": len(ports), "simulation_sources": len(sources)}
    if allowed:
        result["unassigned_ports"] = sorted(missing)
    return result


def check_logic_project(root):
    """只检查原工程逻辑结构；仅允许待确认的 TF 四线没有引脚映射。"""
    return check_project(root, allowed_missing_ports=TF_PORTS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--logic-only", action="store_true", help="只检查逻辑结构，允许 TF 四线映射待确认")
    args = parser.parse_args()
    try:
        result = check_logic_project(args.root) if args.logic_only else check_project(args.root)
    except (OSError, ValueError, KeyError, ET.ParseError) as exc:
        print(f"FAIL: Project validation failed: {exc}", file=sys.stderr)
        return 1
    if args.logic_only:
        print(f"LOGIC_PROJECT_STRUCTURE_PASSED: {result}")
        print("Logic structure only; physical IO, external timing and board operation are not validated.")
    else:
        print(f"PASS: {result}")
        print("Files, top module and explicit pin mapping checked; TD must verify LVDS pairs, SDRAM pins and timing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
