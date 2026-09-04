# Debugging Journey: RPLIDAR A1 + ROS 2 + SLAM on Raspberry Pi

**Context:** Raspberry Pi 4B (headless, wired Ethernet, hostel LAN) running the
RPLIDAR A1, streaming live scan data over the network to a laptop (Ubuntu 22.04,
ROS 2 Humble) for visualization in `rviz2` and live SLAM mapping via
`slam_toolbox`.

This is the actual debugging journey, not just the final config. Every issue below
includes what broke, what we tried that *didn't* work, the real root cause, the
fix, and the generalizable lesson. Several of these looked like completely
different bugs on the surface but turned out to share one underlying pattern —
that repetition is the most useful part of this document, so it's called out
explicitly wherever it happens.

---

## 1. OS/ROS 2 distro mismatch (Pi's original Debian 13 has no ROS 2 support)

**What broke:** The Pi was running Debian 13 (trixie). No official ROS 2 apt
repository exists for Debian — only for specific Ubuntu versions.

**What we tried that didn't fully work:** Considered building ROS 2 from source on
Debian trixie — technically possible, but flagged as high-risk/high-effort (hours
of compile time, dependency mismatches on a very new Debian release) and
ultimately not attempted.

**Root cause:** ROS 2's binary packages are Ubuntu-specific, not
Debian-compatible, despite being closely related distros.

**Fix:** Re-flashed the Pi's SD card to Ubuntu Server. (First attempt accidentally
landed on 22.04 instead of the intended 24.04 — see Issue #2.)

**Lesson:** Before installing ROS 2 on any new machine, confirm the OS version
first and cross-check it against the official ROS 2 distro compatibility table.
Don't assume "Ubuntu" is enough — the exact version matters.

---

## 2. Re-flash landed on the wrong Ubuntu version — but it turned out to be fine

**What broke:** Intended to flash Ubuntu Server 24.04 (to match ROS 2 Jazzy,
believed to be the laptop's distro). `lsb_release -a` on the freshly flashed Pi
showed 22.04 (jammy) instead.

**What we tried:** Started planning a second re-flash to correct this.

**Root cause (the real one):** The laptop's actual ROS 2 distro was never Jazzy —
direct verification (`printenv ROS_DISTRO` and `ls /opt/ros/`) confirmed it was
Humble, which officially pairs with Ubuntu 22.04. The "Jazzy" belief was
outdated/incorrect information carried over from earlier in the project.

**Fix:** No re-flash needed — 22.04 + Humble was already the correct, matched
pairing. Verified directly rather than trusting prior assumptions.

**Lesson:** When two machines need matching software versions, verify both
directly with commands — don't rely on memory or notes of what a machine "is."
Use `printenv`, `ls /opt/ros/`, etc.

---

## 3. `colcon: command not found`

**What broke:** `colcon build --symlink-install` failed instantly with "command
not found," despite colcon supposedly being part of the earlier dev-tools install
step.

**Root cause:** `python3-colcon-common-extensions` was listed in an earlier
combined `apt install` command but hadn't actually been installed (likely skipped,
or the terminal session moved on before it completed).

**Fix:**

```bash
sudo apt install -y python3-colcon-common-extensions
```

Then retry the build.

**Lesson:** When a multi-package `apt install` step happens early and a tool from
that list is "missing" much later, don't assume something is broken — just install
that one specific package directly rather than re-running the whole original
command.

---

## 4. `CMake Error: No CMAKE_CXX_COMPILER could be found`

**What broke:** After fixing colcon, the build then failed on a missing C++
compiler.

**Root cause:** `build-essential` (which provides `g++`) was, again, part of an
earlier combined install that hadn't actually completed/applied.

**Fix:**

```bash
sudo apt install -y build-essential g++ cmake
g++ --version   # verify before rebuilding
```

Then rebuilt successfully (with many harmless SDK compiler warnings — not errors).

**Lesson:** Same pattern as Issue #3 — combined `apt install` commands run once,
early in a long session, are easy to lose track of. When a tool "disappears,"
check whether it was ever actually installed rather than assuming corruption.

---

## 5. SSH host key warning after re-flash

**What broke:** `ssh test@<pi-ip>` refused to connect with a "REMOTE HOST
IDENTIFICATION HAS CHANGED" warning after the OS re-flash.

**Root cause:** Completely expected — a fresh OS install generates a new SSH host
key. The laptop's `known_hosts` file still had the old Debian install's key cached
for that IP, and SSH correctly refused to connect until told the change was
expected (not a MITM attack).

**Fix:**

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "<pi-ip>"
```

Then reconnect and accept the new key. (Automated in
[`scripts/clear-ssh-known-host.sh`](../scripts/clear-ssh-known-host.sh).)

**Lesson:** This warning is always expected after any OS re-flash/reinstall at the
same IP — not a security incident to panic about, just stale local trust data to
clear.

---

## 6. "No route to host" after a Pi reboot

**What broke:** After a `sudo reboot`, SSH failed with "No route to host" — a
different, more specific error than a timeout.

**What we initially misdiagnosed:** Assumed it might be a lingering boot delay.

**Root cause:** DHCP handed the Pi a different IP address after reboot than it had
before — the old IP genuinely had no device answering on it.

**Fix:**

```bash
sudo nmap -sn <subnet>/24
# or:
ip neigh
```

Scan for the Pi's MAC prefix to find its new IP, then SSH to the new address.
(Automated in [`scripts/find-pi-ip.sh`](../scripts/find-pi-ip.sh).)

**Lesson:** "No route to host" (vs. a plain timeout) is a useful signal that the
target IP itself may be wrong, not just slow to respond — worth scanning the
subnet rather than retrying the same IP repeatedly.

---

## 7. `ROS_DOMAIN_ID` set on both machines, but laptop still couldn't see `/scan`

**What broke:** Set `ROS_DOMAIN_ID=42` in `.bashrc` on both Pi and laptop,
confirmed via `printenv` on both — yet the laptop's `ros2 topic list` still didn't
show `/scan`.

**What we checked (and ruled out):** Confirmed the `.bashrc` line was correctly
saved on the Pi via `grep`. Domain ID was genuinely set correctly in *new* shells.

**Root cause:** The `rplidar_a1_launch.py` process on the Pi had been started
*before* `ROS_DOMAIN_ID` was set in that terminal session. A running process only
reads environment variables at its own startup — setting the variable afterward,
even on the same machine, has zero effect on an already-running process.

**Fix:** Stopped the LiDAR launch, ran `source ~/.bashrc` in that same terminal to
pick up the new variable, confirmed with `printenv ROS_DOMAIN_ID`, then relaunched.

**Lesson:** Environment variable changes never apply retroactively to
already-running processes — always restart the process after confirming the
variable is set in that exact shell session.

---

## 8. rviz: "No tf data" warning, Fixed Frame stuck on `map`

**What broke:** rviz defaulted its Fixed Frame to `map`, which didn't exist yet (no
SLAM running at this point — just the raw LiDAR driver).

**Root cause:** `map` is only ever published once something like `slam_toolbox` is
running and building it. With just the raw driver active, only the `laser` frame
(the LiDAR's own frame, from its published `/scan` messages) existed.

**Fix:** Changed rviz's Fixed Frame to `laser` — confirmed as the actual
`frame_id` via:

```bash
ros2 topic echo /scan --once
```

rather than assumed.

**Lesson:** Always check the actual `frame_id` field in a message directly rather
than guessing a "default" frame name — it removed ambiguity later too, when this
same check ended up being the key diagnostic for a much bigger issue (#12).

---

## 9. slam_toolbox: `/map` topic exists but "Resolution/Width/Height: 0" — no map data

**What broke:** Added a Map display in rviz pointed at `/map`. The topic existed,
but was structurally empty (all zeros), and rviz showed "No tf data."

**What we tried first (wrong):** Published a static transform `map` → `laser`
directly, assuming slam_toolbox just needed *some* link between the two frames.

**Root cause (partially correct, but incomplete):** slam_toolbox internally
expects a specific frame chain — `map` → `odom` → `base_frame` — not a direct
`map` → sensor-frame link. Publishing `map` → `laser` skipped the expected `odom`
layer entirely, so slam_toolbox never had a valid starting point.

**Fix (at this stage):** Switched the static transform to `odom` → `laser`
instead, matching the expected chain shape (with zero real odometry, i.e. an
identity transform, since no wheel encoders exist).

**Lesson:** When a tool expects a specific frame chain, providing a shortcut link
between the two endpoints isn't equivalent — the intermediate frame name matters
even if its actual transform is trivial (all zeros).

---

## 10. slam_toolbox: "Failed to compute odom pose" — the longest-running bug of the night

This one had multiple false leads before the real cause was found. The full chain
of misdiagnosis is documented because the eventual root cause explains why each
earlier attempt looked like it should have worked but didn't.

**What broke:** Even after fixing Issue #9, slam_toolbox continuously logged
`WARN: Failed to compute odom pose`, and `/map` still produced no real data.

**False lead #1 — clock drift between Pi and laptop.** Ran `date` on both machines
roughly 15 seconds apart — looked like a real gap. Re-tested with `date +%s.%N`
run as close to simultaneously as possible: actual drift was ~1.5 seconds (just
terminal-switching delay), well within tolerance. Ruled out.

**False lead #2 — duplicate/leftover static transform publisher processes.**
Theorized that an old `map` → `laser` publisher (from before the odom fix) might
still be running alongside the new `odom` → `laser` one, giving `laser` two
conflicting parent frames. Did a full Pi reboot + fresh restart of every node to
eliminate this possibility entirely. Warning persisted regardless. Ruled out
(though this was still a reasonable and correctly-executed check).

**False lead #3 (partially correct) — wrong `base_frame` parameter.** Inspected
slam_toolbox's actual default params file (`mapper_params_online_async.yaml`) and
found `base_frame: base_footprint` — a frame that never existed in this minimal
setup (only ever had `laser`). This looked like the smoking gun. Copied the file,
edited `base_frame` to `laser`, relaunched via
`ros2 launch ... params_file:=...`. The warning did not stop.

**The actual root cause** (found via a completely different diagnostic path):
switched from `ros2 launch slam_toolbox online_async_launch.py params_file:=...`
to running the node directly:

```bash
ros2 run slam_toolbox async_slam_toolbox_node --ros-args --params-file <path>
```

This direct invocation threw an explicit, immediate error: `Couldn't parse params
file`. This revealed that `ros2 launch`'s wrapper had been silently failing to
load the custom YAML file the *entire time* — meaning every edit made (including
the correct `base_frame: laser` fix) had never actually been applied. slam_toolbox
had been running on its compiled-in defaults throughout, including the missing
`base_footprint` frame, no matter what was changed in the file.

The YAML file itself had become malformed from several rounds of `nano` edits and
`sed` substitutions (likely a stray whitespace/indentation issue introduced during
editing — never pinned down exactly which line, since the fix was to rebuild the
file cleanly rather than hunt further).

**Fix:** Rebuilt `my_slam_params.yaml` from scratch in one shot via a
`cat > file << 'EOF' ... EOF` heredoc (avoiding incremental nano/sed edits
entirely), verified it was valid YAML with:

```bash
python3 -c "import yaml; yaml.safe_load(open('my_slam_params.yaml'))"
```

*before* touching ROS at all, then launched via `ros2 run` directly. Confirmed the
fix took effect with:

```bash
ros2 param get /slam_toolbox base_frame   # returned "laser", correctly
```

— something that should have been checked from the very first edit, rather than
trusting that a file edit + relaunch had worked.

**Lesson (the most important one from this session):**

1. `ros2 launch` wrappers can silently swallow params-file loading errors that
   `ros2 run` will report explicitly. When a params file "isn't taking effect"
   despite being clearly correct, try running the node directly to surface the
   real error.
2. Never trust that a config edit worked — verify it on the live node with
   `ros2 param get <node> <param>` immediately after every relaunch. This would
   have caught the problem on the very first attempt instead of several
   fix-cycles later.
3. When a YAML file has been hand-edited many times across a debugging session,
   consider it a suspect in its own right — rebuilding from scratch is often
   faster than continuing to patch it.

---

## 11. Map updating, but only once every 5 seconds

**What broke:** Once Issue #10 was actually fixed, `/map` started publishing —
but `ros2 topic hz /map` showed a steady 0.2 Hz (once every 5 seconds), feeling
sluggish.

**Root cause:** Not a bug — `map_update_interval: 5.0` in the params file was a
deliberate throttle (reduce compute/network load), copied from the default config.

**Fix:** Lowered `map_update_interval` to `1.0` for more responsive live viewing.

**Lesson:** Before treating a "slow update" as a bug, check whether it's an
explicit, named config value first — often it is.

---

## 12. Map wasn't updating at all when physically moving the LiDAR

**What broke:** After the timing fix, physically moving/rotating the LiDAR still
didn't change the map — it stayed frozen at the initial scan.

**What we tried first:** Lowered `minimum_travel_distance` /
`minimum_travel_heading` thresholds (from 0.5 down to 0.1, then to 0.0) — these
gate how much movement is required before slam_toolbox bothers updating.

**Root cause:** Because `odom_frame` and `base_frame` had earlier been set to the
same frame name (`laser`) as a workaround (Issue #9/#10), slam_toolbox's
odometry-based motion estimate was always zero *by definition* (a frame's
transform to itself is always identity) — regardless of how far the sensor
physically moved. The travel-distance thresholds could never be crossed because
the input to that check was structurally always "no movement," even at a 0.0
threshold.

**Fix:** Restored `odom_frame: odom` as a genuinely separate frame from
`base_frame: laser` (re-applying the lesson from Issue #9 — but this time actually
verified working, thanks to the Issue #10 fix, since the params file was now
trusted to load correctly). With `odom` and `laser` distinct, slam_toolbox's
scan-matching could detect real motion and started updating the map correctly.

**Lesson:** A "trick" that removes a dependency (making two frames identical to
avoid needing a transform) can silently break a different, non-obvious downstream
calculation (motion-distance gating) that assumes those frames are legitimately
different. Watch for this kind of second-order effect when using
placeholder/identity transforms as workarounds.

---

## 13. Map correctly accumulating, but "old" scan positions never disappear

**What broke:** As the LiDAR moved, previously-scanned walls/areas stayed marked
on the map, even after moving away — looked like a bug ("not deleting old
frames").

**Root cause:** None — this is correct, intended SLAM behavior. The Map display
is a persistent, cumulative occupancy grid by design; it's supposed to retain
everything ever mapped, not just the current instant. What looked like
"duplicate/smeared" old data was really the visible effect of the no-real-odometry
setup (Issue #12) — without accurate motion tracking, the same physical wall gets
placed at slightly different estimated positions across passes, causing visible
smearing rather than a single crisp line.

**Clarification, not a fix:** If a live, non-accumulating view is actually wanted,
that's a fundamentally different tool — a rolling local costmap (see Issue #14),
not the persistent SLAM map.

**Lesson:** "Persistent map" and "live current-instant view" are two different
products serving two different purposes (mapping vs. real-time obstacle
awareness) — confirm which one is actually wanted before treating accumulation as
a bug.

---

## 14. Local rolling costmap: same YAML-namespace mismatch bug as #10, in a new package

**What broke:** Set up `nav2_costmap_2d` for a small, live, non-accumulating view
(a genuinely different concept from the SLAM map — see Issue #13). Got the exact
same *class* of error as Issue #10: `Invalid frame ID "base_link"` — a frame that
was never configured anywhere in this session.

**Root cause:** The custom params YAML used top-level keys
`local_costmap: local_costmap:` (matching the parameter name that seemed
intuitive), but the actual running node's real name — confirmed via
`ros2 node list` — was `costmap.costmap` (i.e. node `costmap` inside namespace
`costmap`). ROS 2 params files must have their top-level keys match the actual
node/namespace name *exactly*, or the file is effectively ignored and defaults
apply — the same silent-failure pattern as Issue #10, just in a different package.

**Fix:** Rewrote the YAML with matching keys
(`costmap: costmap: ros__parameters: ...`), confirmed via a clean
`cat > file << EOF` rebuild rather than further edits.

**Also required:** `nav2_costmap_2d` is a lifecycle node — it starts inactive and
does nothing until explicitly told to configure and activate:

```bash
ros2 lifecycle set /costmap/costmap configure
ros2 lifecycle set /costmap/costmap activate
```

This alone was a separate, easy-to-miss requirement distinct from the YAML issue.

**Lesson:** This exact "YAML top-level key doesn't match real node namespace →
silent default fallback → confusing frame errors" pattern hit twice in one
session (slam_toolbox, then costmap_2d). Whenever a ROS 2 node's behavior doesn't
match a custom params file, the very first check should be: does `ros2 node
list`'s actual name match the YAML's top-level key structure exactly?

---

## 15. Costmap technically working, but frozen — not tracking real movement *(unresolved)*

**What broke:** After fixing Issue #14, the costmap activated and published real
data, but its `Position` field (which should track the sensor's current location)
stayed frozen at one fixed value regardless of actually moving the LiDAR.

**Root cause:** The same underlying limitation as Issue #12 — the rolling
window's "where is the sensor right now" comes from the `odom` → `laser`
transform, which (even after the Issue #12 fix restored a real `odom` frame) is
still a *fixed, hand-set identity transform*, not a genuinely continuous motion
estimate. Nothing in the pipeline has real, live odometry data to work from.

**Status:** Not yet resolved. The identified correct fix — not yet implemented or
tested — is [`rf2o_laser_odometry`](https://github.com/MAPIRlab/rf2o_laser_odometry),
a package that computes a real, continuously-updating `odom` → `laser` transform
purely from consecutive LiDAR scan comparisons (no wheel encoders needed). This
would replace the fixed static transform publisher and give both slam_toolbox and
the costmap genuine motion data to track, which should resolve both the map
"smearing" (Issue #13) and this frozen-costmap issue at the same root. See
[`docs/NEXT_STEPS.md`](NEXT_STEPS.md) for the full integration checklist.

---

## Cross-cutting lessons

The lessons that recurred across multiple issues, rather than being specific to
one, are pulled out into their own reference: [`docs/lessons-learned.md`](lessons-learned.md).
