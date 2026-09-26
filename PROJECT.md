# AutoLeadAssist: Project Documentation

## 1. Overview

**AutoLeadAssist** is a client-side ballistics preview, aiming, freecam, and enemy-marking script for *[MTC] Multicrew Tank Combat* (Roblox Luau).

It reads local vehicle, weapon, ammunition, and physics data to predict launch direction and impact. The preview is an estimate: map collisions, game-side projectile behavior, and server authority can make a fired shot differ from the displayed path. It does not give projectiles terrain or object noclip.

---

## 2. Core Architecture

The codebase (`attribute.lua`) has these main data paths:

```mermaid
flowchart TD
    A[Vehicle and weapon state] --> B[Mouse or camera target]
    B --> C[Launch-direction solver]
    C --> D[Aim cache and firing hooks]
    C --> J[Artillery turret target control]
    C --> E[Collision-aware trajectory trace]
    E --> F[World-space beams, filled impact zone, HUD]
    G[Freecam and input] --> B
    G --> D
    H[Enemy scans] --> I[Tank Highlights and player Drawing markers]
```

### Subsystems Breakdown

1. **Input isolation and freecam**
   - Uses a scriptable camera and a late `BindToRenderStep` priority (`2,000,000`) so the normal vehicle camera does not overwrite freecam movement.
   - Sinks freecam movement keys with `ContextActionService:BindActionAtPriority` to avoid simultaneously steering the vehicle. It makes best-effort streaming requests around the camera; the game still controls what is replicated and rendered.

2. **Target acquisition (`getAimTarget`)**
   - Uses a fresh viewport ray from the current mouse pixel or the camera look vector. Freecam forces mouse aiming. Cursor aiming and zoom share the same viewport coordinate convention.
   - Outside freecam, first tests other vehicles and characters, then the visible world. In freecam, the first visible world surface wins so an obscured tank does not steal a ground aim point. Raycasts cover a 100,000-stud sightline in chunks. If nothing is hit, the sightline remains a direction rather than a finite ground target.
   - Nearby surface hits remain finite targets. The old under-150-stud rule that silently replaced a close ground hit with a barrel-elevation bearing has been removed.

3. **Launch-direction solver (`solveBallistic`, `getLaunchDirection`)**
   - For a finite target in normal auto-lead mode, uses the minus-sign (lower-angle) no-drag ballistic root:
     $$\tan(\theta) = \frac{v^2 \pm \sqrt{v^4 - g_{\text{mag}}(g_{\text{mag}} x^2 + 2 y v^2)}}{g_{\text{mag}} x}$$
   - Auto-lead uses the same automatic arc selection in normal view and freecam: choose a legal, clear low root first, then a legal, clear high root if the low path is blocked. `AutoBallistic` explicitly prefers a clear high root. Distance alone does not force a high arc or extend maximum range. With horizontal drag, the solver searches the legal elevation interval numerically. A blocked path, unreachable elevation, or out-of-range target is reported.
   - When the player occupies the matching gunner seat, freecam artillery can feed the chosen direction to an FCS-equipped turret through the game's `Gunner.Weapons.Data.TargetPos` control. It yields to another nonzero target owner and clears its own value on exit or unload. Guns without FCS—including the tested 2S19 and M109—are not automatically slewed. High-arc assistance requires the barrel within about 3° of the chosen direction in either camera mode. Low-arc correction uses the same forward-bearing guard in both modes.
   - An unreachable finite target has no assisted solution; there is **no automatic 45-degree fallback**. Open sky preserves the barrel elevation and uses the cursor bearing. Direct firing falls back to the actual bore when assistance is unavailable, matching native gunner fire. Near-backward assisted directions are rejected.

4. **Collision-aware trajectory trace (`traceTrajectory`)**
   - For shells without drag, uses the analytic parabolic position at each preview sample to avoid integration drift. Dragged shells retain stepwise integration. Raycasts are batched across the path using the `Projectile` collision group where available.
   - The preview now updates on rendered frames after the freecam camera step. It reuses raycast settings and skips unchanged traces for up to 0.2 seconds; cursor, barrel, or target movement invalidates that cache immediately. It uses 8–120 simulation steps and can look ahead up to 60 seconds in barrel-lob mode.
   - It stops at the first raycast hit, including queryable map colliders. A planned path can remain visible without an impact in the preview window; the HUD and red impact cue distinguish that case from a confirmed hit.
   - The displayed beam is a cubic approximation between the simulated launch and endpoint, not a guarantee of the server projectile's full path.

5. **Visuals and ESP**
   - Two reusable, engine-rendered world-space `Beam` objects show the actual bore path and the planned assisted path. The selected path starts at the muzzle and terminates at the filled impact cue, including when freecam is active. Its color follows the cue; an optional secondary bore path remains purple.
   - An unreachable finite cursor target retains a red marker at that point and shows `NO VALID ARC TO CURSOR`. When an otherwise legal arc is obstructed, a display-only red trajectory stops at the obstruction and reports `PATH BLOCKED`; that candidate is never supplied as a valid firing direction. Neither case automatically switches to the bore trajectory. The explicit Barrel Path toggle can still show the bore. A compact distance label beside the zone gives muzzle-to-marker distance in metres, controlled by Show Distance.
   - One thin, non-colliding cylinder displays a compact **filled** impact zone. Blue requires a clear path and local firing readiness; green additionally means a person or other vehicle is within the estimated blast radius. Red includes blocked/unreachable paths, required high-arc alignment, empty ammunition, unavailable firing control, damaged gun parts, barrel clipping, or spawn protection. Local readiness does not confirm server acceptance; actual launch status is displayed separately.
   - Own-shell tracking passively observes pooled projectile Parts and Attachments. It associates a dispatched local shot with a matching model, spawn time, muzzle position, and direction; this is a visual association, not a server shot-ID match. There are no repeated garbage-collector searches. At most four shots and 24 discovery candidates are retained, with bounded discovery windows and disconnected callbacks on cleanup.
   - Each observed shot keeps a frozen forecast and target marker when the cursor moves. One beam fills cyan-to-lavender against a muted pending section as the observed shell advances along that path; a dark outline improves contrast. The text-only target label shows distance, estimated remaining time, and percentage. Label content/fill updates are capped at 20 Hz; camera-relative label sizing updates every frame independently of the trajectory cache. Text ranges from 11 to 18 pixels, with a dark shadow-like outline and no card, border, or separate progress bar.
   - Finished shot visuals are removed in the same render update, not retained for five seconds. Arrival can be observed by the shell's sampled movement crossing within eight studs of a predicted collision endpoint after at least half its estimated flight time. Pool return/despawn also ends tracking. No movement for 1.5 seconds ends tracking as lost, not as a confirmed arrival; lifetime expiry is bounded. The bottom-left terminal status lasts two seconds. The separate live aiming preview remains visible.
   - Own-shell ESP uses a small elongated ForceField-material cosmetic Part that follows the observed projectile, whether the native projectile is a Part or Attachment. It is anchored, non-colliding, non-touching, non-queryable, and removed with the shot. It neither changes the native projectile nor adds a ForceField gameplay effect.
   - The bottom-left readout distinguishes `INPUT RECEIVED`, `SHOT SENT`, `SHELL LAUNCHED`, and `NOT FIRED`. Dispatch without a matched object reports `FLIGHT UNOBSERVED`. Progress follows observed position, not just a timer. A visual projectile ending near the predicted target reports `ARRIVAL OBSERVED`; early disappearance or stalled tracking is reported separately. Visual arrival does not prove a server hit or damage. ETA is an estimate and becomes unavailable when tracking stalls.
   - A fixed bottom-left HUD shows impact distance/elevation and flight time or cursor offset. It is not a cursor-following billboard.
   - Enemy tanks use subtle Roblox `Highlight` outlines/fill, without labels. Enemy players use only a `Drawing` username above the character and a slim vertical health bar beside them—no card, box, distance, weapon, or numeric HP text.

---

## 3. Mathematical Models & Formulae

### Ballistic drop and launch-vector resolution

- $x = \text{distXZ} = \sqrt{\Delta X^2 + \Delta Z^2}$
- $y = \Delta Y$
- $v = \text{MuzzleSpeed}$ (studs/s)
- $g$ comes from the shell or MTC constants when available; the fallback is $-49\text{ studs/s}^2$.
- The closed-form root ignores drag; indirect aim with dragged shells uses a bounded numeric pitch search. The dragged-shell preview applies horizontal drag with $\vec v_{t+\Delta t}=\vec v_t+(0,g,0)\Delta t-d\Delta t(v_x,0,v_z)$ and $\vec p_{t+\Delta t}=\vec p_t+\vec v_{t+\Delta t}\Delta t$.

### Blast-radius estimate and compact cue

The script prefers `GlobalConstants.GetExplosionDiameter(shellData)`. Its fallback diameter is:

$$D = \min\left(\frac{10}{c}\left(\frac{m}{\rho}\right)^{1/3},\;500\,\text{ExpCapMult}\right)\text{blastradiusmult}$$

where $c$ defaults to $0.07$, $\rho$ to $1.2$, and $m$ is `ExplosiveMass`. The actual radius estimate is $D/2$ after shell modifiers. The **displayed** disc radius is capped at 24 studs (minimum 6) to reduce clutter; it is a status cue, not a scale-accurate blast footprint. Occupancy checks still use the uncapped radius.

- HESH multiplies the diameter by `0.8`; HEAT multiplies it by `0.66`.
- Shells without positive `ExplosiveMass` get no blast cue.

---

## 4. Configuration & User Interface

The settings menu uses [VibeUI](https://sirmemegithub.com/RealSlimShady2000/VibeUI), loaded from its published single-file Luau source at runtime. Features are grouped into **Aim**, **Trajectory**, **Freecam**, **ESP**, and **Armor** tabs; VibeUI also adds an interface/theme/configuration tab. The bottom-left impact readout remains a separate lightweight overlay. If the library cannot be fetched or built, the aiming and visual logic still runs, but the settings menu is unavailable until a successful reload.

### Theme Palette

| Element | RGB | Hex |
| :--- | :--- | :--- |
| Background | `20, 22, 26` | `#14161A` |
| Card Background | `28, 30, 36` | `#1C1E24` |
| Accent / Toggle Active | `135, 110, 255` | `#876EFF` |
| Bore Trajectory | `155, 48, 255` | `#9B30FF` |
| Planned Trajectory / Clear Zone | `65, 210, 255` | `#41D2FF` |
| Occupied Zone | `70, 235, 165` | `#46EBA5` |
| Invalid Shot / Zone | `255, 90, 125` | `#FF5A7D` |
| Flight Fill Start | `65, 225, 255` | `#41E1FF` |
| Flight Fill End | `177, 135, 255` | `#B187FF` |
| Contrast Outline | `12, 16, 26` | `#0C101A` |

Impact and shot-readout labels use bright text with a dark stroke over a faint dark backing (72% transparent) and no border. World-label backgrounds automatically fit their text with only three pixels of horizontal padding, one pixel of vertical padding, and two-pixel corners; they do not fill the billboard canvas. The surrounding containers stay transparent. World labels shrink with camera depth and grow with zoom, bounded for readability. The settings menu is unchanged; the trajectory retains its cyan-to-lavender fill.

### Settings

- `DisableExplosionShake` defaults on and is remembered. **Freecam → Camera → Disable Explosion Shake** suppresses named/default explosion camera shake and the mass-based camera-shake helper shared by shell impacts and flybys. It does not suppress damage, sounds, particles, physical recoil or alter the camera directly. The muzzle-recoil toggle remains separate. Original effect functions are restored on disable/unload, without overwriting later replacements by other code. Effects already scheduled before enabling may finish their existing decay.

- `DisableFiringShake` defaults on and is remembered across reloads. The **Freecam → Camera → Disable Firing Shake** toggle zeros only the three client-side cannon muzzle-shake presets (`RecoilShake`, `RecoilShake2`, `RecoilShake3`). This also suppresses nearby cannon muzzle shake using those presets, but leaves explosion shake, physical recoil, firing, and camera controls unchanged. Original values are restored on disable/unload unless another owner changed them. No render loop or new firing hook is added. Diagnostics expose availability and errors; unsupported preset layouts fail without repeatedly retrying.

- `EnableAutoLead`, `Trajectory`, `AutoLead`, `ShowBallistic`, and `AutoBallistic` control the aiming assist and bore/lead previews. `AutoBallistic` defaults off; the others default on except `ShowBallistic`.
- `ExplosionRadius` toggles the compact filled impact-zone cue; `ShowDistance` controls both the zone distance label and bottom-left distance readout. `FlightTimer` controls flight-time information.
- `OwnShellHighlight`, `ShotProgress`, and `ShotStatus` independently toggle own-projectile highlighting, the flight completion path, and shot confirmation. They default on and are remembered across reloads.
- `EnemyTankESP`, `PlayerESP`, `ESPNames`, `ESPHealth`, and `ESPBoxes` are separately toggleable and default on. Player ESP draws a projected body-size outline, name, and narrow health bar; enemy tanks use engine Highlights. Enemy filtering excludes the local player's team and neutral players. The scanners cap active markers at 16 nearby tanks and 24 nearby players.
- `ESPColorIndex` selects red, cyan, yellow, or purple. `ESPMaxDistance` is a VibeUI slider with an editable value box: any whole-stud distance from `0` to `50,000`, rather than four presets. There is no ESP distance-label toggle.
- `AimSource` starts as `"Mouse"` and can be changed to `"Camera"`; active freecam forces mouse aiming.
- `Freecam` starts off. `FreecamSpeed` starts at `3.5` and is adjustable from `0.5` to `20`. Freecam and zoom keys can be rebound in the Freecam tab. Zoom follows the cursor while preserving the world ray under it; the previous camera adjustment is removed before the next camera update to prevent drift. Zoom starts off; its field of view defaults to `25°` and can be adjusted from `10°` to `70°`.
- `ZeroEnemyArmor` defaults on. It sets the client-visible `ArmourValue` and related composite/HEAT/slat resistance attributes to zero for enemy tanks only, tracks newly spawned plates, and restores original local values when disabled or unloaded. Server-side hit and damage rules may ignore these local changes.
- ESP, armor, keybind, freecam-speed, zoom-FOV, and `AutoBallistic` choices are remembered across script reloads in `_G.AutoLeadAssistRemembered`.

---

## 5. Controls & Keybinds

| Key / Input | Action |
| :--- | :--- |
| `Right Shift` / `Insert` | Toggle the VibeUI settings menu |
| `V` (rebindable) or freecam toggle in settings | Toggle freecam navigation |
| `Z` (rebindable) or zoom toggle in settings | Toggle camera zoom |
| `W, A, S, D` (Freecam) | Move Camera (Isolated from chassis) |
| `Space` / `E` | Elevate Camera Up |
| `Left Control` / `Q` | Lower Camera Down |
| `Right Mouse Button` (Freecam) | Hold to rotate the camera; release to move the cursor freely and choose a shot location. Enabling freecam closes the menu. |
| Arrow keys (Freecam) | Alternate look control |
| `Left Mouse Button` / `F` | Native gunner click; `F` or driver click can use direct fire when a valid shot code was previously observed for that vehicle |
| `Left Shift` | Boost Freecam Speed ($\times 2.5$) |
| `Left Alt` | Slow Freecam Speed ($\times 0.3$) |

---

## 6. Firing and limitations

The firing hook updates replicated shot directions from a frame-synchronized aim cache when alignment is safe. Camera mode does not change the arc-selection or firing gates. High lobs still need barrel alignment; if assistance is unavailable, direct fire preserves the bore direction instead of rejecting the input. The preview labels an unavailable assisted target red. Driver-seat direct fire remains conditional on a valid shot code already observed for the **same vehicle**. It does not automatically grant a gunner role or provide the driver's turret-slaving input. Server-side ammunition and firing rules remain authoritative.

The preview deliberately honors terrain and map collider hits. A line ending before the cursor can therefore mean the predicted projectile hit an obstruction. When no legal path exists to a finite target, the red cue remains at the requested target and no valid assisted trajectory is drawn; it is not a predicted impact. The script cannot promise that a projectile passes through buildings or terrain.

The 2S19 gun tested here allows roughly $-3^\circ$ to $52^\circ$ of elevation. With `3OF45 Proxy High Charge` at about 2,000 studs, the mathematical high root is near $89^\circ$ and cannot be reached by that turret. The solver should then use a legal clear low arc if one exists; it cannot make a high arc over an intervening building without a suitable charge, range, or weapon elevation.

## 7. Live test status (2026-09-24)

- The current file executed in a fresh connected client without a new AutoLead runtime error. Re-execution left one settings UI, one visual container, two beams, and four beam attachments—no duplicate visual instances.
- Tank `Highlight` instances and player ESP tracking were active. In a BMP-3 2017, the main-gun preview ran in gunner and driver seats; driver diagnostics reported the firing hook and direct-fire prerequisite as ready.
- For a finite unobstructed target, sampled predicted impact error was about `0.2` studs. Another sample stopped on `Workspace.Map.MapParts.Destructibles.Pine_big_2LOD0.propCollision` about `801` studs before the cursor target.
- Those earlier checks did **not** verify a fired shell against the preview. The Roblox window capture returned a blank frame, so final on-screen appearance was not visually confirmed at that stage.
- A later live load of the frame-synchronized preview completed without a new AutoLead runtime error. Sample aim/trace work was below 1 ms combined, but this is a local sample, not a measured game-FPS improvement. Cursor-motion appearance still needs visual confirmation in the game window.
- The VibeUI migration loaded with all 17 feature controls in the connected client. Setting ESP distance to a non-preset `3,456` studs updated the live script setting; it was restored to the previous `3,300` studs after the check. This validates the control callback, not the on-screen appearance of every tab.
- The new script loaded in the connected client with the Armor tab and no AutoLead warning. Diagnostics reported 598 client-visible armor values across 12 enemy vehicles set to zero, while friendly vehicle samples retained their values. A `Drawing` Square creation probe succeeded. Weapon damage, key presses, zoom appearance, and ESP scaling were not verified on screen.
- The latest freecam check confirmed that enabling it closes the menu, uses a `Scriptable` camera and mouse aim source, and leaves the cursor at `Default` so it can select a shot location. Holding RMB is intended to lock temporarily for camera rotation; physical RMB movement was not verified through MCP. Disabling freecam restored the normal camera and `Default` cursor instead of the stale `LockCurrentPosition` mode.
- The reconnected 2S19 live probe confirmed its `TurretInfo.FCS` is absent, just like the M109. Therefore an earlier $0.62^\circ$ barrel movement during a brief `TargetPos` probe did **not** establish that this control slews the 2S19; concurrent manual movement was possible. The script correctly reports `aim barrel to target arc` on this gun. A direct legacy-turn fallback was tried only in the live working copy, but the client disconnected before it could be validated; it was removed from the deliverable. The revised script loaded without a new AutoLead console error and returned an analytic preview error under `0.001` stud for one near finite target.
- On the reconnected client, the saved script loaded cleanly before seating. In the 2S19 gunner seat with `3OF45 Low Charge`, freecam mouse targeting was active. A visible `SpawnProtectors.Eagle Federation` hit at about 5,107 studs produced a legal low arc near $25.2^\circ$, while the barrel initially stayed near $1.9^\circ$ and the assist reported `aim barrel to target arc`. The player manually raised the barrel to about $25^\circ$ without leaving freecam; the assist then reported `ready` and its predicted terrain endpoint was within about `0.001` stud of the cursor target. One player-fired low-charge shot at about 5.2k studs reported `applied=true` in the firing hook, and the player observed that it landed close to the cursor.
- For the high arc, the cursor hit `Workspace.SkyboxLoaded.Part` around 6,700 studs. The solver selected a legal launch near $47.9^\circ$, and the player manually elevated the barrel to about $48.1^\circ$. The assist reported `ready`, with a computed preview endpoint within about `0.003` stud of the selected point. The player-fired shot was assigned an elevated direction by the firing hook, and the player observed that it landed close to the cursor after its roughly 17-second flight. The on-screen landing was user-observed, not independently measured by the MCP.
- The revised filled zone and beam were loaded in the connected client without a new AutoLead runtime error. In freecam at a nearby invalid artillery aim, the red zone and bore beam were both visible. For a reachable but not-yet-aligned distant aim, live diagnostics showed the planned beam and a blue/green zone instead of falsely marking it red. Their world-space endpoints differed only by the zone's deliberate `0.18`-stud surface offset. The Roblox window capture was blank, so the final visual appearance still needs player confirmation.

### Follow-up tests (2026-09-25)

- The player confirmed that the earlier freecam trajectory connects to the filled zone and the zone changes blue/green. The new revision tightens those colors to include firing readiness after a further report that a blue planned path could still refuse a shot.
- Live projectile tracking observed a player-fired shell, matched its game projectile state, and reached an impact state. Another rejected attempt reported `NOT FIRED` with an alignment reason. The low-arc freecam-only alignment rule causing that rejection has since been removed; the same-point firing retest is pending.
- Isolated calls to the active solver at 500 studs/s and 49 studs/s² gravity chose low arcs for 250 and 4,500 studs, a high root when explicitly preferred at 4,500 studs, and rejected 6,000 studs as out of range.
- Cursor-zoom ray preservation was checked at four viewport offsets; the maximum direction-vector error was approximately `6e-8`. The live zoom binding also applied its camera transform and 25° FOV, with zero sampled cursor-ray error, then zoom was switched off. Final cursor-follow appearance still needs player confirmation.
- The revised script loaded in the M109 and T-80B client without a new AutoLead runtime error. The client disconnected before the final normal-view/freecam firing comparison; that retest remains pending. The final small change making trajectory colors update even with the blast cue disabled was reviewed locally but was not reloaded before disconnection. These tests do not establish server damage or guaranteed hits on moving targets.

### Shot-progress follow-up (2026-09-25)

The first revision still delayed or missed shell discovery, and the user reported dark text. The corrected revision removes gradients from text labels and replaces repeated projectile-state searches with passive Part/Attachment observation. The live client subsequently reported three dispatched shots and three observed shells; one nearby shell ended within about 0.8 studs of its predicted endpoint. This verifies detection in that client, not server damage. Long-flight filling, frozen-target appearance, and final readability still need user visual confirmation. No shots were fired by the assistant.

## 8. Cleanup and diagnostics

### Moving-camera zoom correction (2026-09-26)

The earlier angular-proximity restore heuristic proved unreliable in user testing, including on foot. It has been replaced: the late zoom transform is presentation-only, and its exact saved camera pose/FOV is restored before the next input/camera update. The normal camera controller then computes movement before one new cursor lens transform is applied. There is no angle-based ownership guess or residual integration. Shortest-arc ray rotation replaces the paired lookAt frames to avoid extra roll. Mouse pixels are bounded to the viewport, native FOV changes are captured, and camera swaps/disable/freecam entry restore the owned pose.

Full-source compilation passed. An isolated harness running the actual zoom callbacks passed 1,800 frames across three FOV modes, with position/orientation/FOV changes, cursor sweeps and perturbations. Maximum cursor-direction error was about `2.5e-7`, with zero restore or position error; callback cleanup passed. This supersedes the earlier residual-preserving zoom approach. The test does not establish compatibility with every third-party camera writer; user testing is still needed for moving tanks and on-foot controls.

### Explosion shake follow-up (2026-09-26)

After the user clarified that shell detonation triggers the movement, added a separate explosion/flyby camera-shake toggle rather than relying on muzzle presets or zoom correction. Full-source compilation passed. Isolated tests passed for explosion/mass suppression, recoil pass-through, restoration, repeated toggling, preserving another owner's replacement and disabling retained wrappers on unload. This revision was not live-fired or reloaded during implementation.

### Zoom/recoil interaction follow-up (2026-09-26)

The preset toggle was active in the inspected client, but shell flyby and explosion effects use a separate mass-based shake path. Zoom previously removed its lens rotation only when the camera CFrame exactly equaled its last output; even small external camera changes could leave the lens rotation applied for another frame. Restoration now runs before the normal render priorities, preserves small residual rotations and world translation, and avoids undoing a pose already replaced with an unzoomed view. This ownership check compares angular proximity and is not a universal guarantee for arbitrary third-party camera controllers. Restored/applied rotations are orthonormalized to prevent matrix drift. The same cleanup handles zoom disable, camera replacement and freecam entry.

Isolated testing of the actual restore helper over 600 simulated recoil frames produced a maximum direction error around `1.2e-5` against the expected recoil-only view. A replacement-camera-pose test passed. This is not a live firing verification; flyby/explosion shake remains intentionally separate from the muzzle-preset toggle.

### Firing shake option (2026-09-26)

Live source inspection confirmed that cannon muzzle effects call `vfxHandler.ShakeCam` with recoil presets, separately from explosion shake. The new toggle compiled successfully. Isolated preset-table tests passed for suppression, explosion preservation, restoration, repeated toggling, and respecting later changes by another owner. No live shot was fired and the full script was not reloaded during this update; final on-screen behavior remains unverified.

### Shot cleanup, text and zoom follow-up (2026-09-26)

Removed the five-second finished-shot retention and detected object-pool teleports before reparenting. Completed/lost shots now remove their path, target text, zone, and cosmetic shell together. The dot marker became a ForceField-material shell proxy. World label sizing runs independently of the cached ballistic trace, so camera movement still resizes text without forcing additional raycasts. Zoom now uses engine viewport rays at both FOVs instead of manual projection with an incorrect GUI-inset subtraction; aiming uses the same current viewport ray.

Verification: the full saved source compiled without executing it. Isolated tests of the actual shot-update callback removed arrived, despawned, stalled and expired entries, while retaining an airborne entry. Twelve isolated camera-projection tests across three FOV modes had a maximum direction-vector error around `3.8e-8`. These are isolated checks, not a live firing or final visual test. The full script was not reloaded because the recent executor disconnect cause remains unresolved.

### Render-capability error fix (2026-09-25)

Repeated `lacking capability Plugin` errors occurred while the render callback wrote the impact HUD under a protected UI container. The gameplay overlay now lives in `LocalPlayer.PlayerGui`, without GUI protection or elevated callback permissions. If the preview callback throws again, it records `preview.error` and `preview.stopped`, hides its visuals where possible, unbinds itself, and warns once instead of retrying every frame. Reload after correcting the recorded error. Pooled-shell reuse also explicitly disconnects the previous candidate's callbacks before replacing its record.

After reloading, live inspection confirmed one overlay in PlayerGui, an active preview callback, and no new capability error in the sampled console logs. This is not proof that every source of game stutter has been eliminated.

### Cursor-preview follow-up (2026-09-25)

The user requested restoration of the DTC-reported revision after a temporary rollback; that revision is the base for this fix. The earlier disconnect's cause remains unconfirmed. Live inspection in normal view showed a road hit only about 28 studs away being converted to `arc=barrel` and `finiteTarget=false`. Removing that conversion preserved a later nearby ground target as finite; its invalid arc showed a red marker and a `12 m` distance label with the bore beam disabled. A reachable target then showed a blue connected trajectory, a `150 m` label, and only the intended `0.18`-stud marker surface lift. The user confirmed that the trajectory follows the cursor correctly. The script loaded successfully; no shot was fired by the assistant.

`_G.AutoLeadAssistDiagnostics()` reports active seat/weapon, aim state, predicted hit/error/time, impact-zone color/visibility, shot dispatch/observation status, ESP counts, armor scan counts, and zoom state. `_G.AutoLeadAssistSetFreecam(true/false)` and `_G.AutoLeadAssistSetZoom(true/false)` control the camera features. `_G.AutoLeadAssistUnload()` disconnects loops and input/notification handlers, restores the camera, weapon hooks, and local armor values, and removes all tracked-shell visuals as well as the preview/UI. Re-executing the file calls the previous unload handler first.
