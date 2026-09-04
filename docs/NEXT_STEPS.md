# Next Steps: Integrating `rf2o_laser_odometry`

**Status:** Identified as the correct fix. Not yet implemented or tested.

## The gap this closes

Right now, both `slam_toolbox` and the local costmap read "where is the sensor
right now" from a **hand-set, permanently-identity** `odom → laser` static
transform (published because this rig has no wheel encoders — see
debugging-journey.md, Issues #9 and #12). That means:

- The map still *builds* (slam_toolbox also does internal scan-matching), but
  positions smear across passes instead of lining up crisply (Issue #13).
- The local costmap's reported sensor position is frozen — it never updates,
  because there is no real, changing transform for it to read (Issue #15).

[`rf2o_laser_odometry`](https://github.com/MAPIRlab/rf2o_laser_odometry) computes
a real, continuously-updating `odom → laser` transform purely by comparing
consecutive LiDAR scans against each other — no wheel encoders required, which is
exactly the constraint here.

## Checklist

- [ ] **Clone and build** on the machine that will run it (likely the laptop,
      alongside `slam_toolbox` and the costmap — not the Pi, which just runs the
      raw driver):

  ```bash
  cd ~/ros2_ws/src
  git clone https://github.com/MAPIRlab/rf2o_laser_odometry.git -b humble-devel
  cd ~/ros2_ws
  colcon build --packages-select rf2o_laser_odometry
  source install/setup.bash
  ```

- [ ] **Stop the static `odom → laser` transform publisher entirely.** rf2o
      replaces it — running both at once will fight over the same transform.

- [ ] **Launch `rf2o_laser_odometry_node`** with the frame names already in use
      elsewhere in this pipeline (`config/my_slam_params.yaml`,
      `config/local_costmap_params.yaml`) so nothing else needs to change:

  ```bash
  ros2 run rf2o_laser_odometry rf2o_laser_odometry_node --ros-args \
    -p base_frame_id:=laser \
    -p odom_frame_id:=odom \
    -p publish_tf:=true \
    -p laser_scan_topic:=/scan
  ```

- [ ] **Verify it's actually producing a changing transform** — this is the key
      verification step that was never reached in the original debugging
      session. Run this while physically moving the LiDAR and confirm the
      values genuinely change in real time (not just once at startup):

  ```bash
  ros2 run tf2_ros tf2_echo odom laser
  ```

  If this stays frozen, don't move on to the next step — that's the same
  "verify, don't assume" lesson from Issue #10 applying here too.

- [ ] **Restart `slam_toolbox` and the costmap** afterward so they pick up the
      real transform instead of any cached identity one. Re-run
      `scripts/verify-slam-params.sh` to confirm frame values are still what's
      expected.

- [ ] **Re-check Issues #12, #13, and #15** against the new behavior:
      - Does the map still smear across passes, or does it now line up cleanly?
      - Does the costmap's `Position` field now move as the sensor moves?

## If rf2o doesn't fully resolve it

Laser-scan-only odometry (rf2o) works by matching scan-to-scan, which degrades in
feature-poor environments (long straight corridors, open rooms with few
distinguishing features). If drift or jitter shows up under those conditions,
the next-tier options — in rough order of effort — are:

1. Tune rf2o's own params (it has a handful of matching-related tolerances).
2. Add a wheel-encoder-based odometry source once the rover has a real
   differential-drive base (see the parent
   [slam-rover-project](../README.md#why-this-repo-exists) plan), and fuse it
   with rf2o via `robot_localization`'s EKF node rather than relying on either
   alone.
3. Revisit whether the eventual camera array (planned for the full rover) can
   contribute visual odometry as a second independent estimate.
