The FFT capture snapshot uses one `EG_PHY_BRAM32K` with an independent 16-bit
write port and read port. Its complex work snapshot uses one block with paired
16-bit addresses on both ports. Both wrappers retain one synchronous read edge
and leave RAM contents and outputs unreset. The core gates writes with reset.

Run from the repository root:

```powershell
python tests/fft_ram32k/verify.py --tool-dir PUBLIC_SOURCE/.codex/toolchains/iverilog-iccoder-2.0.10/bin
python tests/audio_spectrum/verify.py --tool-dir PUBLIC_SOURCE/.codex/toolchains/iverilog-iccoder-2.0.10/bin --unit-only
```

The first command checks every logical RAM word, 4096 randomized simultaneous
port operations, all 256 FFT bins for eight numerical vectors in both branches,
and cycle equivalence against the frozen original core. It also checks that
partial-capture, processing, and valid-output resets retain all RAM words and
suppress output validity. The structural check permits only the memory binding
replacement in the FFT core. The original fixture is copied from the pre-change
snapshot; the summary records its provenance and all input hashes.

`FFT_NATIVE_RAM_TEST` selects the native branch under Icarus. The public
true-dual-port model permits writes on both ports, validates primitive controls,
and models synchronous reads. When available, the exact installed vendor
BRAM32K declaration is also elaborated to verify its API. The model does not
replace vendor timing simulation or TD physical resource and timing reports.
Capture read/write collisions and read values on work write cycles have no
FFT consumer; the core comparison checks the actual read-consumer states.
