# FreeCAD Post Processors for nxt

Two posts ship here. The **legacy** post is the original argparse-driven one and is unchanged in behaviour. The **machine** post is a port onto the CAM machine-post API introduced in FreeCAD 26.3, where output options come from a machine definition instead of command-line arguments.

Both can be installed at the same time, so you can post the same job through each and compare.

Targets the **nxt v0.7.0** line.

## Files

| File | Post name in FreeCAD | Purpose |
|---|---|---|
| `nxt_legacy_post.py` | `nxt-<version>` | the original post, unchanged behaviour |
| `nxt_machine_post.py` | `nxt_machine` | machine-flow port |
| `machines/Milo_V1.5.fcm` | — | Milo V1.5 machine definition |
| `machines/Milo_V2.fcm` | — | Milo V2.0 machine definition |
| `machines/Miley_V2.fcm` | — | Miley V2.0 machine definition |
| `tools/compare_gcode.py` | — | semantic diff between the two posts' output |

---

## Installing the legacy post

1. Download `nxt-<version>_post.py` from the [GitHub Release](https://github.com/MillenniumMachines/MOS-nxt/releases) on the same **major.minor** line as installed nxt (e.g. any 0.7.x post with 0.7 firmware; `M4005` ignores beta/rc/patch).
2. Copy it into your FreeCAD **macro directory** (the same folder used for `.FCMacro` files).
3. Restart FreeCAD or refresh the CAM post list if needed.
4. In the CAM workbench, select the post processor whose name matches the file prefix (e.g. `nxt-v0.7.0` for `nxt-v0.7.0_post.py`).

FreeCAD expects post processors to follow the `<prefix>_post.py` naming convention (`_post.py` must be lowercase). See the [FreeCAD CAM post customization guide](https://github.com/FreeCAD/FreeCAD-documentation/blob/main/wiki/CAM_Postprocessor_Customization.md#naming-convention).

## Installing the machine post

1. **Post processor** → copy `nxt_machine_post.py` onto FreeCAD's post search path; the macro directory is the usual choice (`~/.local/share/FreeCAD/v<version>/Macro/`).

   **Do not rename this file.** `PostProcessorFactory.get_post_processor()` resolves the class as the filename minus `_post.py`, title-cased — `nxt_machine` → `Nxt_Machine`. A versioned filename would not be a valid identifier, the factory would silently fall back to `WrapperPost`, and posting fails with *"The script does not have an 'export' function"*. This is why the release ships it unversioned while the legacy post keeps its `nxt-<version>_post.py` name.

   The search order is FreeCAD's `defaultFilePath()`, then `macroFilePath()`, then addon post directories, then FreeCAD's own `Path/Post/scripts/`. **The first match wins**, so an older copy in the CAM default file path can silently shadow the one you just installed. To check which file actually loads, run this in FreeCAD's Python console:

   ```python
   import os, Path.Preferences as PP
   print("\n".join(("WINS " if os.path.exists(os.path.join(p, "nxt_machine_post.py")) else "  -  ")
                   + os.path.join(p, "nxt_machine_post.py") for p in PP.searchPathsPost()))
   ```

2. **Machine definitions** → copy the `.fcm` files into `<CAM asset path>/Machines/`. The default asset path is `FreeCAD.getUserAppDataDir()/CamAssets`; check yours with `Path.Preferences.getAssetPath()`.

3. **Restart FreeCAD.** Confirm the post is classified correctly (Python console):

   ```python
   import Path.Preferences as P
   P.classifyPostProcessor("nxt_machine")   # -> 'machine'
   ```

   If it reports `unknown`, the module raised on import and the classifier swallowed the traceback. The 26.3 machine post API is a moving target, so FreeCAD changes during its development cycle can break this.

4. **In the CAM Job**, set Machine to `Milo V1.5`, `Milo V2.0` or `Miley V2.0`. The postprocessor comes from the machine definition, not from the job.

5. **Check `nxt_version`** in the machine definition matches your firmware line. The machine post reads it from there, not from `RELEASE.VERSION`. Since v0.7.0, `M4005` compares **major.minor only** (`macros/utilities/M4005.g`), so the shipped `v0.7.0` value covers `v0.7.0-beta.N`, `v0.7.0-rcN` and `v0.7.x` firmware without re-exporting — but crossing a line (0.6 → 0.7) still aborts. The post refuses to post at all if the value is still the `%%NXT_VERSION%%` build placeholder, rather than emitting a bad `M4005`.

---

## nxt-specific divergence from the MillenniumOS post

This post tracks `millennium_os_machine_post.py` in the MillenniumOS repo so the two stay diffable. On the v0.7.0 line there is exactly **one** behavioural divergence.

| Feature | Code | Status in nxt | Handling |
|---|---|---|---|
| Canned-cycle modals | `G80` / `G98` / `G99` | **implemented** (`macros/canned/`), unlike RRF/MillenniumOS | still dropped, for parity with `nxt_legacy_post.py`, which carries `_UNSUPPORTED = [98, 99]` and never emits G80 |

nxt's `G80.g` / `G98.g` / `G99.g` maintain real modal state (`global.nxtCannedCycle`, `global.nxtCannedRetractMode`), so emitting them may well be correct — but it is a behaviour change from what nxt users get today, and it needs validating against a drilling job on real hardware first. See `UNSUPPORTED_MODAL` in `nxt_machine_post.py`.

> **Earlier v0.6.0 divergences, now resolved.** The v0.6.0 port defaulted VSSC off and added a `rotation_compensation` property, because that line shipped no `M7000`/`M7001`/`M5011`. The v0.7.0 line implements all three (`macros/spindle/M7000.g`, `M7001.g`, `nxt-run-vssc.g`, `macros/utilities/M5011.g`), so both special cases are gone and the post matches MillenniumOS again.

> **Still absent on v0.7.0:** `M3000`. The legacy post's `oncomment()` emits `M3000 R"FreeCAD" S"..."` for an operation Comment, which has no macro and will abort. The machine post emits nothing for comments. Pre-existing, untouched by this port.

---

## Parity with the legacy post's v0.7.0 fixes

Both fixes the legacy post gained on this line are carried here:

- **Explicit G1 to arc start after a plane change** (upstream `32d18b0`). RRF takes an arc's start point from the live machine pose rather than from the command, so after a plane change a modal axis word suppressed as unchanged can leave an out-of-plane axis stale and the arc starts from the wrong point. Implemented in `_force_arc_start_after_plane_change()`, porting legacy's `onplane()` / `_forceArcStartPose()` pair: X and Y are restated (never Z, covering the G18→G17 scallop lead-in), once per plane change.

  **It runs at text level, after suppression, and that ordering is load-bearing.** The restated pose is by definition the current position, so `suppress_redundant_axes_words()` would strip every axis word and leave a bare `G1`. Both `_optimize_gcode()` branches therefore call it after their own suppression pass, and the base is then invoked with suppression disabled. If you refactor `_optimize_gcode()`, preserve that order.
- **4-decimal axis output** (upstream `42cc6d0`, `AXIS_DECIMALS = 4`, "to satisfy RRF G2/G3 arc tolerance"). Handled via `output.precision.axis: 4` in all three machine definitions — `dist/verify-post-processor-naming.sh` asserts it, since reverting to 3 reintroduces the defect.

---

## What the base class does now

Removed from the port because the base `PostProcessor` handles it, driven by the machine definition:

| Legacy behaviour | Now controlled by |
|---|---|
| argparse options | property schema, edited in the Machine editor |
| header block | `output.header.*` |
| comment formatting | `output.comments.*` |
| coordinate / feed / spindle precision | `output.precision.*` |
| modal deduplication | `output.duplicates.*` |
| canned cycle expansion | `processing.translate_drill_cycles` |
| G21/G90/G94 | `postprocessor.properties.preamble` |
| park and stop at end | `postprocessor.properties.postamble` |

## What the port overrides, and why

nxt-specific:

- **`_expand_prefix`** — M4005 version check, M4000 tool table, G6511 reference probe, G6600 WCS probing, M7000 VSSC. Job-dependent — it needs the tool list and the set of used WCSs — so it cannot be a static preamble string. Also appends the closing sequence so ordering matches legacy: `M9`, `G27`, `M7001`, `M9`, `M5.9`.
- **`_convert_tool_change`** — emits a bare `T` word; nxt services the change in firmware, so `M6` is suppressed.
- **`_convert_spindle_command`** — appends the `.9` wait suffix (`M3.9`, `M5.9`) so RRF blocks until the spindle is at speed.
- **`_convert_fixture`** — park before a WCS change, optional probe, M5011.
- **`_convert_coolant_command`** — adds the descriptive comment. The M-codes themselves come from `Path/Op/Base.py`, not from the post (see below).
- **`get_sanity_checks`** — warns on rotary axes, multiple spindles and a disabled version check.

Compatibility and correctness fixes, each traced to a specific base-class behaviour:

- **`format_parameter`** — strips trailing zeros and normalises `-0` to `0`, so output reads `X141.5` / `F1096` rather than `X141.5000` / `F1096.0`. Also tolerates the base method existing with or without the `command_name` argument, which differs between 26.x builds.
- **`_expand_prefix`** — sets `PARAMETER_ORDER` alphabetically to match legacy; the base default reorders every motion line. Set there rather than in `init_values()` because `apply_configuration_bundle()` resets `self.values` wholesale in Stage 0.
- **`_convert_rapid_move`** — strips `F` from `G0`, and drops a rapid whose axis words were all removed as unchanged. The base's `F_FOR_RAPID_MOVES` check sits in the `elif` of the duplicate-parameter test, so it is unreachable when `output.duplicates.parameters` is false.
- **`_convert_arc_move`** — drops zero-valued `I`/`J`/`K`. The legacy post marked arc offsets `Control.NONZERO`; without this every G17-plane arc carries a spurious `K0`.
- **`_convert_modal_command`** — drops `G80`, `G98`, `G99` (see the divergence table above), and labels `G17`/`G18`/`G19` the way the legacy post does.
- **`_convert_item_commands` / `_optimize_gcode`** — defers the leading Z-only approach move until after the first XY move, and applies per-operation axis-word suppression. The deferral matters most after a tool change: nxt has parked, so the machine sits high and over the toolsetter, and descending to clearance *before* traversing would put the traverse at clearance height straight through whatever is between — the toolsetter included.

---

## Two upstream FreeCAD issues worth being aware of

### 1. Suppressing M6 disables the only modal reset

FreeCAD's `GcodeProcessingUtils.suppress_redundant_axes_words()` tracks position across the whole G-code body and resets **only** on a line starting with `M6`/`M06`:

```python
if any(stripped.startswith(cmd) for cmd in ["M6", "M06"]):
    current_pos = {k: None for k in current_pos}
```

This post suppresses `M6` because nxt services tool changes in firmware from a bare `T` word. So the reset never fires, position is tracked straight through a park and tool change, and a retract such as `G0 Z5` at the start of an operation is dropped as redundant — leaving a bare `G0` and **no retract before the following XY rapid**. It affects any post that delegates tool changes to firmware, and it is invisible in the output.

Worked around here by emitting a sentinel comment at each operation, tool-change and fixture boundary, splitting the body on it, suppressing each segment independently, then calling the base with suppression disabled. A proper upstream fix would reset on a bare `T` word too, or expose an overridable reset hook.

The legacy post avoids this entirely by calling `_forceAll()` in `onoperation()`, `ontoolchange()` and `onfixture()`.

### 2. Coolant M-codes are hardcoded

FreeCAD's `Constants.py` hardcodes the coolant on/off commands:

```python
MCODE_COOLANT_MIST  = ["M7", "M07"]
MCODE_COOLANT_FLOOD = ["M8", "M08"]
MCODE_COOLANT_OFF   = ["M9", "M09"]
```

A non-standard mode such as nxt's `M7.1` air blast (`macros/coolant/M7.1.g`) will not dispatch to `_convert_coolant_command()` and will not be seen by `_expand_coolant_delay()`. Widening those constants, or making them post-overridable, would help any post with a non-standard coolant mode.

---

## Things that are not what they look like

Worth knowing before changing anything here.

- **Coolant M-codes come from FreeCAD, not the post.** `Path/Op/Base.py` inserts `M7`/`M8`/`M9` into the operation's Path around the first and last `GCODE_MOVE`, based on `obj.CoolantMode`. The post only labels them. This is why the machine post contains no coolant emission code at all and still produces correct coolant output.
- **Most machine-definition fields are descriptive only.** Nothing in the CAM module outside the model class and the Machine editor reads axis `limits`, `max_velocity`, `role`, `parent`, `coolant_flood` or `coolant_mist` for a 3-axis machine. The rotary path generators are the only consumers. Fill them in accurately anyway — a future release may start using them.
- **The spindle `min_rpm`/`max_rpm` are not descriptive.** `Path/Tool/FeedsSpeeds/resolver.py` clamps the calculated speed into that range and scales feeds by the same ratio to hold chipload constant. Raising `min_rpm` therefore raises feeds for anything that lands on the floor.
- **`_make_postable(label, [])` is not a dedup barrier.** It builds an item with a non-`None` but empty `Path`, so `_edit_command_list()` takes the `if item.path` branch, iterates zero commands and never calls `edit_fn`.
- **`supported_commands` is substring-matched.** `convert_command_to_gcode()` does `command.Name not in supported` where `supported` is a newline-joined *string*, so `M3` matches inside `M30`.

---

## Machine definition settings

These are not FreeCAD defaults; each was arrived at by comparing output against the legacy post.

| Setting | Value | Why |
|---|---|---|
| `processing.filter_inefficient_moves` | `false` | `collapse_g0()` removed ~1500 rapids on a test job, including the XY approach before every operation |
| `processing.translate_drill_cycles` | `false` | nxt implements G73/G81/G83 natively |
| `processing.f_for_rapid_moves` | `false` | legacy emits no `F` on `G0` |
| `output.duplicates.commands` | `true` | means "emit the command word every line"; `false` suppressed the `M4000` prefix on repeated lines, producing bare parameter lines RRF would reject |
| `output.duplicates.parameters` | `false` | suppress unchanged axis words, as legacy does |
| `output.comments.symbol` | `"("` | `;` produces a file mixing both styles |
| `output.precision.feed` | `0` | legacy truncates feed to whole mm/min |
| `output.precision.axis` | `4` | matches the legacy post's `AXIS_DECIMALS = 4`, required for RRF G2/G3 arc tolerance |
| `toolheads[0].toolhead_wait` | `0.0` | `M3.9` already blocks; a `G4` dwell would double the wait |

Axis limits and feedrates come from RRF `M208` and `M203`. Miley is set to the configured soft limits (305 X, 200 Y, 120 Z), not nominal travel. Milo carries nominal travel (348 X, 210 Y) and **should be replaced with real `M208` values** before use.

Only Milo V1.5, Milo V2.0 and Miley V2.0 have definitions here. `macros/nxt-config/machine/` also carries configs for `v1.6`, `v1.6_v2` and `atlas` — add `.fcm` files for those if you need them.

---

## Verifying against the legacy post

Post the same job through both, then:

```sh
tools/compare_gcode.py legacy.gcode machine.gcode
```

It normalises line numbers, comments, whitespace, parameter order and numeric precision, then compares command by command, so a clean run means behavioural equivalence rather than textual equivalence.

### Known remaining differences

Verified in the MillenniumOS port across three jobs (5-tool profiling, a 107k-line adaptive job, and a drilling job). All benign:

- **Feed rounding.** Legacy does `int(qty.getValueAs('mm/min'))`; the base rounds. `F919` vs `F920`, about 0.1% on one feed.
- **Feed placement.** The machine post may emit `G1 F920` on its own line where legacy folds the feed into the following move. Both legal.
- **Modal axis words.** The machine post omits an axis word whose value has not changed (`G3 I-1 X29.626`); legacy re-asserts it via `_forceArcParams` / `_forceLinearParams`. Verified equivalent — same motion.
- **One extra `M9`** before `G27`. Legacy's pre-park coolant-off is conditional on coolant being on; this one is unconditional. A no-op when coolant is already off. Remove `M9` from `postprocessor.properties.postamble` for an exact match.
- **Approach ordering.** No longer a difference. `_delay_leading_z()` defers a leading Z-only move until after the first XY move, matching legacy (`G0 X.. Y..` then `G0 Z5`). One refinement over legacy: only *pure*-Z moves are deferred, so a combined XYZ move is left alone, where legacy deferred any move whose Z changed.

The `G17`/`G18`/`G19` arc-start restatement is implemented, so plane-changing jobs should now match legacy on that point — but see the coverage note below.

### Not yet covered

**Nothing in this port has been verified against nxt firmware on real hardware.** The equivalence above was established for MillenniumOS, not nxt.

`_force_arc_start_after_plane_change()` has unit coverage for its text handling (pose tracking across suppressed axis words, once-per-plane-change firing, X/Y-only restatement, multi-line entries) but **has never run inside FreeCAD**. Post a plane-changing job — a 3D surface or scallop operation, which is what produces `G18`/`G19` — and confirm each first arc after a plane change is preceded by a `G1` carrying real X/Y values and not a bare `G1`.

Additionally, no test job has exercised **multiple fixtures/WCSs** or **probing operations** in either repo. `_convert_fixture()`'s park-before-change branch and its multiline return have never run.

---

## Before you cut

Dry-run the first real job above the work.
