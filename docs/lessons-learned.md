# Lessons Learned — Reusable Checklist

The full story with all the false leads is in
[`debugging-journey.md`](debugging-journey.md). This file is the distilled
version: the lessons that weren't specific to one bug, kept as a standalone
checklist to run through *before* diving deep into any future ROS 2 debugging
session — on this project or any other.

## 1. Verify, don't assume, after every config change

The single biggest time-sink in this whole session (debugging-journey.md, Issue
#10) was trusting that a params file edit had taken effect without checking the
live node's actual parameter value. Running `ros2 param get <node> <param>`
immediately after every relaunch would have caught the problem on the very first
attempt instead of several fix-cycles later.

```bash
ros2 param get /slam_toolbox base_frame
ros2 param get /costmap/costmap odom_frame
```

Make this reflexive, not optional — it costs one command and answers "did my
change actually apply?" with certainty instead of hope.

## 2. `ros2 launch` can hide errors that `ros2 run` surfaces directly

When something "isn't working" and there's no clear error message, that absence
of an error is itself a clue — `ros2 launch` wrappers can silently swallow
params-file loading failures. Try the direct invocation to see if there's a
parsing/loading failure being quietly eaten:

```bash
ros2 run <package> <node> --ros-args --params-file <path>
```

If this throws something like `Couldn't parse params file` while the launch-file
version stayed silent, the launch wrapper was the problem all along, not the
node or the YAML content.

## 3. YAML top-level keys must match the real node namespace exactly

Hit this exact pattern twice in one session, in two unrelated packages
(`slam_toolbox`, then `nav2_costmap_2d`). A params YAML's top-level key structure
has to mirror the node's actual name and namespace, or ROS 2 silently ignores the
whole file and falls back to compiled-in defaults — which then produces confusing
"frame doesn't exist" errors that look unrelated to the real cause.

**Before assuming a params file's structure is correct, check:**

```bash
ros2 node list
```

...and make sure the YAML's top-level keys match what that actually shows,
including namespace nesting.

## 4. Rebuilding a hand-edited YAML from scratch beats continuing to patch it

Once a config file has been through many rounds of `nano`/`sed` edits in one
session, treat it as a suspect in its own right — a stray whitespace or
indentation issue is easy to introduce and hard to spot by eye. A clean rebuild
via heredoc is often faster than continuing the hunt:

```bash
cat > my_params.yaml << 'EOF'
...
EOF

# validate before touching ROS at all:
python3 -c "import yaml; yaml.safe_load(open('my_params.yaml'))"
```

## 5. Identity/placeholder transforms can break unrelated downstream logic

Using a "trick" to skip a dependency — e.g. setting `odom_frame` and `base_frame`
to the *same* frame name to avoid needing a real transform — can silently break a
different, non-obvious calculation elsewhere that assumes those frames are
legitimately distinct (debugging-journey.md, Issue #12: motion-distance gating
always saw "zero movement" because a frame's transform to itself is always
identity, no matter the threshold). Whenever using a placeholder/identity
transform as a stand-in, ask explicitly: *what else reads this same transform,
and does it assume it's non-trivial?*

## 6. Distinguish "wrong OS version" from "wrong belief about what's installed"

When two machines need matching software versions, verify both directly with
commands — don't trust memory or old notes of what a machine "is." A whole
re-flash cycle was almost triggered by an outdated belief (debugging-journey.md,
Issue #2) that direct verification would have prevented immediately:

```bash
printenv ROS_DISTRO
ls /opt/ros/
lsb_release -a
```

## 7. A specific network error ("No route to host") is more informative than a timeout

If a connection attempt fails with "No route to host" rather than a plain
timeout, that's a signal the target IP itself may be wrong — not just slow to
respond. Worth scanning the subnet before retrying the same address repeatedly:

```bash
sudo nmap -sn <subnet>/24
ip neigh
```

## 8. Environment variables never apply retroactively to a running process

A process only reads environment variables at its own startup. Setting
`ROS_DOMAIN_ID` (or anything else) in a shell after a node is already running has
zero effect on that node — it has to be restarted in a shell where the variable
is confirmed set first:

```bash
source ~/.bashrc
printenv ROS_DOMAIN_ID   # confirm before relaunching, not after
```

## 9. Don't treat every unexpected value as a bug — check for an explicit config first

A slow-feeling update rate, a throttled interval, a conservative default — these
often trace back to a deliberately named config value (`map_update_interval`,
in this case) rather than something broken. Check the params file for an
explicit setting before assuming the code is misbehaving.

## 10. Know which of two similar-looking tools is actually being asked for

"Persistent cumulative map" and "live current-instant view" solve different
problems (mapping vs. real-time obstacle awareness) and are different tools
(`slam_toolbox`'s `/map` vs. a rolling `nav2_costmap_2d`). Confirm which one is
actually wanted before treating one's behavior as a bug in the other.
