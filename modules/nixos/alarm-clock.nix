# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) getExe';
  cfg = config.nixfigs.alarm-clock;
  user = config.users.users.${cfg.user};

  rfkill = getExe' pkgs.util-linux "rfkill";

  # Matched by description, not by node/device name: the alsa_card bus path
  # (pci-0000_XX_00.N) shifts across docks/boots, but this friendly name is
  # stable on both hosts that use this option.
  selectSpeakerSink = pkgs.writeShellScript "alarm-select-speaker-sink" ''
    set -euo pipefail
    wpctl=${getExe' pkgs.wireplumber "wpctl"}
    sed=${getExe' pkgs.gnused "sed"}
    grep=${getExe' pkgs.gnugrep "grep"}
    head=${getExe' pkgs.coreutils "head"}
    sleep=${getExe' pkgs.coreutils "sleep"}

    dev_id=$("$wpctl" status | "$sed" -n '/Devices:/,/Sinks:/p' \
      | "$grep" 'Ryzen HD Audio Controller' | "$grep" -oE '[0-9]+' | "$head" -1) || true
    if [ -n "$dev_id" ]; then
      "$wpctl" set-profile "$dev_id" 1
      "$sleep" 0.5
    fi

    # Prefer the GPD Duo convolver's virtual sink when present (it's what
    # actually reaches the Duo speakers, EQ'd) -- the raw card sink is
    # swallowed internally and never appears under Sinks: on that hardware.
    # Hosts without the convolver fall through to the raw card sink below.
    sink_id=$("$wpctl" status | "$sed" -n '/Filters:/,/Streams:/p' \
      | "$grep" 'laptop-convolver' | "$grep" 'Audio/Sink' | "$grep" -oE '[0-9]+' | "$head" -1) || true
    if [ -z "$sink_id" ]; then
      sink_id=$("$wpctl" status | "$sed" -n '/Sinks:/,/Sources:/p' \
        | "$grep" 'Ryzen HD Audio Controller' | "$grep" -oE '[0-9]+' | "$head" -1) || true
    fi
    if [ -n "$sink_id" ]; then
      "$wpctl" set-default "$sink_id"
    fi
  '';
in
  with lib; {
    options.nixfigs.alarm-clock = {
      enable = mkEnableOption "wake-from-suspend alarm clock";

      user = mkOption {
        type = types.str;
        default = "dzrodriguez";
        description = "User whose PipeWire session the alarm plays through.";
      };

      audioFile = mkOption {
        type = types.str;
        default = "${user.home}/.alarm.ogg";
        defaultText = literalExpression ''"''${home of nixfigs.alarm-clock.user}/.alarm.ogg"'';
        description = "Sound file to play.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "*-*-* 08:15:00";
        description = "systemd.time(7) calendar spec for when the alarm fires.";
      };

      volume = mkOption {
        type = types.ints.between 0 100;
        default = 100;
        description = ''
          Volume, as a percentage, that the default sink is forced to (and
          unmuted at) before playback, so a sink left muted or turned down
          cannot silence the alarm.
        '';
      };

      inhibitHours = mkOption {
        type = types.ints.positive;
        default = 1;
        description = ''
          Hours to inhibit suspension for once the alarm fires. Names the
          instance of nixfigs-common's inhibit-suspension@.service, whose
          ExecStart appends the "h" unit itself (sleep %ih) -- so this is a
          bare integer, not "1h".
        '';
      };

      wakeOnly = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Resume the machine at onCalendar and hold it awake, but play nothing.
          The sink is left alone. For hosts that should come back up on schedule
          without a sound going off in an empty room.
        '';
      };

      forceSpeakers = mkEnableOption ''
        forcing playback onto the onboard "Ryzen HD Audio Controller" analog
        speakers before the alarm plays, activating its ALSA profile first if
        WirePlumber has it set to off (it does, by default, after most
        suspend/resume cycles on these hosts)
      '';

      blockBluetooth = mkEnableOption ''
        rfkill-blocking Bluetooth before the alarm plays and before bedtime
        suspends, so a paired device can't be or become the default sink;
        unblocked again once the post-alarm inhibit window ends
      '';

      inhibitPowerAndLid = mkEnableOption ''
        also inhibiting the power button and lid switch (on top of sleep) for
        the duration of the post-alarm inhibit window
      '';

      bedtime = {
        enable = mkEnableOption "scheduled nightly suspend";

        onCalendar = mkOption {
          type = types.str;
          default = "*-*-* 02:00:00";
          description = "systemd.time(7) calendar spec for when the host suspends.";
        };
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        systemd.services.alarm-clock = {
          description =
            if cfg.wakeOnly
            then "Scheduled wake-up (silent)"
            else "Alarm clock";

          # Timer-triggered oneshot, not part of any boot target: without
          # this, nixos-rebuild switch re-runs it (playing the alarm or
          # re-waking the system) any time its unit definition changes.
          restartIfChanged = false;

          # Deliberately Wants= without a matching After=: the inhibitor is a
          # oneshot that sleeps for inhibitHours, so ordering after it would
          # hold the alarm back for that long. Unordered means concurrent.
          # It is also what stops bedtime's logind idle rules putting the
          # machine straight back to sleep on resume.
          wants = ["inhibit-suspension@${toString cfg.inhibitHours}.service"];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = user.group;

            # Reaches the user's PipeWire socket. Valid even with nobody logged
            # in, because the user lingers, so the user manager is always up.
            Environment = "XDG_RUNTIME_DIR=/run/user/${toString user.uid}";

            ExecStart =
              if cfg.wakeOnly
              then ["${getExe' pkgs.coreutils "true"}"]
              else
                optional cfg.blockBluetooth "${rfkill} block bluetooth"
                ++ optional cfg.forceSpeakers selectSpeakerSink
                ++ [
                  "${getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ ${toString (cfg.volume / 100.0)}"
                  "${getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SINK@ 0"
                  "${getExe pkgs.mpv} --no-video --no-terminal --ao=pipewire ${escapeShellArg cfg.audioFile}"
                ];
          };
        };

        systemd.timers.alarm-clock = {
          description = "Alarm clock";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.onCalendar;
            WakeSystem = true;
            AccuracySec = "1s";
            Unit = "alarm-clock.service";
            # A missed alarm (powered off at onCalendar) must not fire the
            # moment the timer is next started -- it should just wait for the
            # next onCalendar occurrence.
            Persistent = false;
          };
        };
      })

      (mkIf cfg.bedtime.enable {
        systemd.services.bedtime = {
          description = "Suspend the system at bedtime";
          # Timer-triggered oneshot, not part of any boot target: without
          # this, nixos-rebuild switch re-runs it (suspending the machine
          # mid-switch) any time its unit definition changes.
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            # No --ignore-inhibitors: a held sleep lock (a long build, a manual
            # inhibit-suspension@N) skips bedtime for that night rather than
            # suspending out from under it.
            ExecStart =
              optional cfg.blockBluetooth "${rfkill} block bluetooth"
              ++ ["${getExe' pkgs.systemd "systemctl"} suspend"];
          };
        };

        systemd.timers.bedtime = {
          description = "Suspend the system at bedtime";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.bedtime.onCalendar;
            Unit = "bedtime.service";
            # Emphatically Persistent = false: a bedtime missed while powered
            # off must not fire on the next boot and suspend the machine
            # underneath whoever just turned it on.
            Persistent = false;
          };
        };
      })

      (mkIf (cfg.enable && (cfg.blockBluetooth || cfg.inhibitPowerAndLid)) {
        # Overrides nixfigs-common's generic inhibit-suspension@ template:
        # extends --what= to cover the power key/lid (instead of just sleep),
        # and/or appends the Bluetooth unblock once the held sleep ends.
        systemd.services."inhibit-suspension@".serviceConfig.ExecStart = mkForce (
          [
            (concatStringsSep " " (
              [(getExe' pkgs.systemd "systemd-inhibit")]
              ++ ["--what=${concatStringsSep ":" (["sleep"] ++ optionals cfg.inhibitPowerAndLid ["handle-power-key" "handle-lid-switch"])}"]
              ++ ["--why=PreventSuspension" "--who=system" (getExe' pkgs.coreutils "sleep") "%ih"]
            ))
          ]
          ++ optional cfg.blockBluetooth "${rfkill} unblock bluetooth"
        );
      })
    ];
  }
