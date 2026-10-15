# Main/video, digital audio and speech CPU assembly

## Independent expectations before implementation

Preserve the actual tested main/video/audio wrapper and connect the actual
speech CPU/engine/nominal clock alongside it. Share global master/reset and
image downloader. Pass only audio_command bits 6:0 to speech; bit 7 retains
its separate rising-edge digital audio IRQ role. Each CPU has independent
ready, with nominal main /96 and audio/speech /192 machine-step strobes.
Both audio SENSE inputs remain external pending physical oscillator audit.

Retain the original dual-CPU fixture's five main WRTC command updates under
both FLAG states, two IRQ/RETE audio command/RAM/DAC signatures, /96 and /192,
independent main/audio ready stalls and 48k raw DAC samples. Let the synchronous
speech program ROM prime opcode zero during reset, then hold speech ready low
while those execute. Load actual speech synthetic code through its image
window, then release its independent ready. It must read real 1D80 command
status as C6 (last main command C6, low payload 46, CTL input bit zero), and
write C6 through the actual CPU to 1D00. Its pointer becomes 0630 and CPU
halts. Engine samples continue while the speech CPU is stalled; without SPEAK,
they are idle signed -1. No mock CPU, hierarchical RAM or fixed TALK substitute
is permitted. Program/data image windows remain isolated across all three CPUs.

This synthetic three-CPU assembly is not an unchanged full-game or MiSTer
integration reference. Physical clocks/CDC/input/video phases, analog mix and
discrete/PVI audio, native broad diagnostics, complete game/voice references
and Quartus gates remain explicit blockers.
