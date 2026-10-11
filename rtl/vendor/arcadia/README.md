# Imported S2650 source

Imported from MiSTer-devel/Arcadia_MiSTer at
`b18a02f43b116b21b57f25e0d608e2b321a7f501`:

| Original file | Original SHA-256 |
| --- | --- |
| rtl/base/base_pack.vhd | af94042dfd027e793b89c32d7b1d42b7402f75d1048a254346b012e208803291 |
| rtl/s2650/sgs2650_pack.vhd | 181493ff74289ac3a4ef74dc1e6054d34b5e80478f9c625e635ace1f7452a306 |
| rtl/s2650/sgs2650.vhd | e35360d4e1005a5b3105ebd701b0ef64fe44d94b3d70c0f8bc76bcb704b8cb7b |

Original D.O./temlib notices remain. The package states that the design may be
used for any purpose. The upstream repository supplies GPL version 2, retained
in `LICENSES/Arcadia-GPL-2.0.txt`. Imported files are not covered by the original
project modules' BSD license. No upstream accuracy claim is automatically adopted.

Local changes: trailing-whitespace normalization, VHDL-2008 trace-name qualification, reproduced carry/borrow and
signed-compare corrections, page-preserving arithmetic, I/O qualifiers/fetch
restoration, HALT interrupt return, synchronous enable and opcode-zero reset bus.
Cold synthesized EORZ R0 now produces its architectural zero without upstream's
simulation-only general-register initialization, retaining non-CC PSL bits.
See `docs/cpu.md` for tested boundaries and outstanding coverage.
