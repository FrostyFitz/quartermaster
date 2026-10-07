# Attended-posture backstop

A Claude primary's only continuity path while attended (no `state/.afk` or `state/.afk-contract`) is the Stop hook's auto-arm (`bin/fm-claude-stop-autoarm.sh`).
That path runs entirely inside the Claude process tree, so it can die with the rest of that tree - a hook Claude itself kills at its own configured timeout, `SIGKILL`, a closed pane - with nothing left alive to retry, because retrying depends on the next Stop event and there is no next Stop event without a new prompt.

`bin/fm-attended-backstop.sh` is an independent check that runs outside that process tree entirely, from a systemd user timer, so it survives exactly that failure mode.
It implements tier B of the design in `data/attended-backstop/report.md`: detect, repair, and alert.
It does not type a recovery message into the primary's own pane (the report's tier C "nudge"); that tier, and its `attended-backstop` operational-input kind, are not implemented.

## Gate

The backstop runs only while `config/attended-backstop` (local, gitignored) exists, mirroring [`config/supervision-host`](configuration.md#supervision-host-configsupervision-host)'s presence-only gate.
Absence is fully off, matching the report's conservative default.

Each tick is also a no-op whenever any of these holds, so the common case costs one directory read:

- `state/.afk` or `state/.afk-contract` exists (away or quiet mode already owns continuity).
- Supervision is not needed (`bin/fm-supervision-lib.sh`).
- The watcher is healthy (`bin/fm-wake-lib.sh`'s model-aware `fm_watcher_supervision_verdict`).
- Supervision is unhealthy but under `FM_ATTENDED_BACKSTOP_THRESHOLD_SECS` (default 1800s - twice the arm layer's own stall bound, so ordinary self-healing has already had every chance to work before this backstop acts).
- The current down-episode was already handled (`state/.attended-backstop-episode`, cleared on recovery).

## What it does

Past the threshold, on the first tick of a down-episode: it starts or attaches the watcher in the background (`bin/fm-watch-arm.sh`), then always fires the wedge-alarm notifier (`bin/fm-supervise-daemon.sh`'s `wedge_alarm_notify`, [`wedge-alarm.md`](wedge-alarm.md)) with attended-specific wording, regardless of whether the re-arm succeeds.
It never touches `state/.lock`: a dead session-lock owner is `bin/fm-lock.sh`'s job, a different and bigger authority than this script's.

## Install

1. Land this repo's code (already done if you are reading this from a checked-out quartermaster).
2. Opt the home in: `touch config/attended-backstop`.
3. Set a working alert channel if `auto` is not enough for this platform: an absent `config/wedge-alarm` already defaults to `notify-send` on Linux when it is installed, or `osascript` on macOS; see [wedge-alarm.md](wedge-alarm.md#channels) for `command:` delivery to a phone or pager.
4. Install the templated unit from [`systemd/`](../systemd), replacing the placeholder `ExecStart` path with this machine's quartermaster checkout:
   ```
   mkdir -p ~/.config/systemd/user
   sed "s#/path/to/quartermaster#$(pwd)#" systemd/firstmate-attended-backstop@.service \
     > ~/.config/systemd/user/firstmate-attended-backstop@.service
   cp systemd/firstmate-attended-backstop@.timer ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now "firstmate-attended-backstop@$(systemd-escape "$(pwd)").timer"
   ```
   `%i` is the systemd-escaped `FM_HOME` path, so the same two unit files cover any number of secondmate homes - repeat step 4's last two commands with that home's path.

## Verify

```
systemctl --user status "firstmate-attended-backstop@$(systemd-escape "$(pwd)").timer"
journalctl --user -u "firstmate-attended-backstop@$(systemd-escape "$(pwd)").service"
```

## Uninstall

```
systemctl --user disable --now "firstmate-attended-backstop@$(systemd-escape "$(pwd)").timer"
rm config/attended-backstop
```

## Tests

`tests/fm-attended-backstop.test.sh` covers the no-op matrix, a single repair-only re-arm with a silent recovery tick, the alert floor firing once per episode and again on a new episode, and a healthy cycle writing nothing to `state/`.
