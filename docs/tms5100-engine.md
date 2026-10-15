# Connected normalized speech engine

## Expectations recorded before implementation

Assemble the actual normalized controller, frame parser, pinned TMC0281
numeric ROM, logical-sample sequencer and serial lattice. CTL reads must come
from the controller's direction state with TALK status from the sequencer,
never a fixed external fixture or unconditional busy bit. Preserve the pinned
software fast-start/numeric profile and its physical timing/rounding limitations.

Use one outstanding external ROM request. Controller command reads have
priority over frame reads when no request is outstanding. Remember the owner
until its response and route ready/valid only to that consumer. CPU pointer
write backpressure remains external and cannot drop or duplicate a request.
RESET clears the engine's parser/target conversion/sequencer/filter/response
owner, without modifying the external CVS CPU's ROM pointer. The next engine
request must not consume a cancelled response. Global reset clears the whole
connected assembly; neither reset initializes downloaded ROM bytes.

A complete raw frame is converted through the actual coefficient ROM, one
K per master edge, retaining raw indices/UV mask and assembling an atomic
target for the sequencer. No second frame request may overwrite conversion.
The sequencer then emits captured parameters/excitation for the actual filter.
Active PCM completion follows that filter; idle logical samples emit signed
-1 without modifying filter history. Both produce one sample_valid pulse.
No new sample_tick may overtake a pending frame, conversion or filter job.
Parameter/timing/overlap diagnostics remain visible and block qualification.

Synthetic integrated tests must issue real falling-PDC commands, provide
independently encoded serial bits under stalls, check CTL direction/status,
frame bit counts and complete PCM against an independent logical-sample plus
wide-integer lattice model. Include voiced/unvoiced/repeat/silence/stop frames,
normal/slow drain, input holds, reset and cancelled responses. Frozen unchanged
CVS firmware/serial data observation is additional evidence, not a numerical
or physical game voice oracle. External sample ticks still require a separate
nominal-clock check before production integration. Three-CPU/MiSTer/analog/
native-runtime/Quartus blockers remain until meaningful executed coverage.
