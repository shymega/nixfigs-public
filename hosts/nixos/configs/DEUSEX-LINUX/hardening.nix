# https://github.com/cynicsketch/nix-mineral
# Several of these options are the default but having them defined is useful for educational purposes
{
  config,
  lib,
  ...
}: {
  boot = {
    kernel = {
      sysctl = {
        # "Only admin can use ptrace, as it required CAP_SYS_PTRACE capability."
        "kernel.yama.ptrace_scope" = "2";

        # Disables magic sysrq key
        # https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html
        "kernel.sysrq" = "0";

        # Disable io_uring. Responsible for many vulnerabilities
        "kernel.io_uring_disabled" = "2";

        # https://www.kernel.org/doc/html/latest/admin-guide/sysctl/fs.html
        "fs.protected_fifos" = "2"; # Disallow O_CREAT on FIFOs we don't own
        "fs.protected_hardlinks" = "1"; # Disallow hardlink creation unless user can access it
        "fs.protected_regular" = "2"; # Disallow O_CREAT on FIFOs we don't own
        "fs.protected_symlinks" = "1"; # Disallow following symlinks not owned by the process's user
        "fs.suid_dumpable" = "0"; # Don't coredump processes which have changed privilege levels

        # https://www.kernel.org/doc/html/latest/admin-guide/sysctl/kernel.html
        "kernel.dmesg_restrict" = "1"; # User must have CAP_SYSLOG to view
        "kernel.kexec_load_disabled" = "1"; # Disable kexec_*load cannot alter a loaded image
        "kernel.kptr_restrict" = "2"; # Kernel pointers are always outputted as 0
        "kernel.perf_event_paranoid" = "2"; # Disallow ftrace, raw, CPU, and kernel profiling without CAP_PERFMON
        "kernel.unprivileged_bpf_disabled" = "1"; # Disable bpf() calls and don't recover
        "kernel.randomize_va_space" = "2"; # Randomise nmap, stack, VDSO, and heap layout
        "kernel.unprivileged_userns_clone" = "1"; # Disable user namespaces

        # https://docs.kernel.org/admin-guide/sysctl/net.html
        "net.core.bpf_jit_harden" = "2"; # Enable JIT hardening for all users

        # https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html
        "net.ipv4.conf.all.accept_source_route" = "0"; # Do not accept SRR packet options
        "net.ipv4.conf.all.rp_filter" = "1"; # Prevent IP spoofing by rejecting packets not in an interfaces IP address range
        "net.ipv4.tcp_rfc1337" = "1"; # Conform to RFC1337 preventing TCP TIME_WAIT assassination
        "net.ipv4.tcp_syncookies" = "1"; # Send syncookies when syn backlog queue overflows preventing SYN flood attack

        # https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html
        "vm.mmap_rnd_bits" = "32"; # Use 32 bits for VMA random offset
        "vm.mmap_rnd_compat_bits" = "16"; # Use 16 bits for VMA random offset in compatibility mode
        "vm.unprivileged_userfaultfd" = "0"; # Restrict unprivileged users to handle page faults in user mode
        "vm.mmap_min_addr" = "65536"; # Disallow writing to low addresses to guard against null reference bugs
        "vm.swappiness" = "1"; # Try to swap as little as possible
      };
    };

    kernelParams = [
      # Disable PCI DMA during early boot
      "efi=disable_early_pci_dma"

      # Apply relevant CPU exploit mitigations
      "mitigations=auto"

      # Page Table Isolation
      # A Meltdown mitigation harms performance
      "pti=auto"

      # Gather more entropy on boot
      "extra_latent_entropy"

      # Zero allocated and freed memory
      # Slight performance hit
      "init_on_alloc=1"
      "init_on_free=1"

      # Randomise page allocations to make memory layout less predictable
      "page_alloc.shuffle=1"

      # Randomise kernel stack offsets at each syscall to prevent stack-based attacks
      "randomize_kstack_offset=on"

      # Disables merging slabs prevents exploitation
      # Slab is a small block of memory and commonly used objects to improve performance and cache utilisation
      "slab_nomerge"

      # Reduce boot-time logging
      "quiet"

      # By default don't display kernel logs
      "loglevel=0"

      # Disable trust in CPUs RNG
      "random.trust_cpu=off"

      # Disable trust in bootloader RNG
      "random.trust_bootloader=off"

      # Ensure DMA protections are applied
      "iommu=force"
      "iommu.strict=1"
    ];
  };

  environment = {
    etc = {
      # Empty /etc/securetty to prevent root login on tty.
      securetty.text = ''
        # /etc/securetty: list of terminals on which root is allowed to login.
        # See securetty(5) and login(1).
      '';

      gitconfig.text = ''
        [core]
          ## https://github.com/git/git/security/advisories/GHSA-8prw-h3cq-mghm
          symlinks = false

        ## https://forums.whonix.org/t/git-users-enable-fsck-by-default-for-better-security/2066
        [transfer]
          fsckobjects = true
        [fetch]
          fsckobjects = true
        [receive]
          fsckobjects = true
      '';

      "bluetooth/main.conf".text = lib.mkForce ''
        [General]
        # Do not stay pairable forever stop after 30s
        PairableTimeout = 30
        # Do not stay discoverable forever stop after 30s
        DiscoverableTimeout = 30
        # Only allow a single controller
        MaxControllers=1
      '';
    };
  };

  fileSystems = {
    # bind for remounting
    # nosuid protects against SUID-root privilege escalation
    # noexec prevents running untrusted binaries
    # nodev prevents fake devices being used for privilege escalation

    "/home" = {
      device = "/home";
      options = [
        "bind"
        "nosuid"
        "exec"
        "nodev"
      ];
    };

    "/home/lawrence/Downloads" = {
      device = "/home/lawrence/Downloads";
      options = [
        "bind"
        "nosuid"
        "noexec"
        "nodev"
      ];
    };

    "/root" = {
      device = "/root";
      options = [
        "bind"
        "nosuid"
        "noexec"
        "nodev"
      ];
    };

    "/tmp" = {
      device = "/tmp";
      options = [
        "bind"
        "nosuid"
        "exec"
        "nodev"
      ];
    };

    "/var" = {
      device = "/var";
      options = [
        "bind"
        "nosuid"
        "noexec"
        "nodev"
      ];
    };

    "/boot" = {
      options = [
        "nosuid"
        "noexec"
        "nodev"
      ];
    };

    "/srv" = {
      device = "/srv";
      options = [
        "bind"
        "nosuid"
        "noexec"
        "nodev"
      ];
    };

    "/etc" = {
      device = "/etc";
      options = [
        "bind"
        "nosuid"
        "nodev"
      ];
    };
  };

  boot.specialFileSystems = {
    "/run" = {
      options = [
        "noexec"
      ];
    };

    "/dev" = {
      options = [
        "noexec"
      ];
    };
  };

  # Randomise MAC addreses
  networking = {
    wireless.enable = false;
    networkmanager = {
      ethernet = {
        macAddress = "random";
      };
      wifi = {
        macAddress = "random";
        scanRandMacAddress = true;
      };
    };
  };

  security = {
    apparmor = {
      enable = true;
      killUnconfinedConfinables = true;
    };

    pam = {
      # Disable generating core dumps
      loginLimits = [
        {
          domain = "*"; # Applies for all users
          item = "core"; # Limits core dumps
          type = "hard"; # Strict/unchangeable
          value = "0"; # Set core dump size to 0
        }
      ];

      services = {
        # Increase number of hash rounds for /etc/shadow
        passwd.rules.password."unix".settings.rounds = 65536;

        # https://unix.stackexchange.com/questions/670116/debian-bullseye-disable-console-tty-login-for-root
        login.rules.auth = {
          "nologin" = {
            enable = true;
            order = 0;
            control = "requisite";
            modulePath = "${config.security.pam.package}/lib/security/pam_nologin.so";
          };
          "securetty" = {
            enable = true;
            order = 1;
            control = "requisite";
            modulePath = "${config.security.pam.package}/lib/security/pam_securetty.so";
          };
        };

        su.requireWheel = true; # Restrict su to wheel group
        su-l.requireWheel = true; # Restrict su -l to wheel group
        system-login.failDelay.delay = "4000000"; # 4 second delay to failed login attempts
      };
    };
  };

  services = {
    # Disallow root login over SSH
    openssh.settings.PermitRootLogin = lib.mkForce "no";

    # DNS connections will fail if not using a DNS server supporting DNSSEC
    resolved.dnssec = "true";
  };

  # Get extra entropy since we disabled hardware entropy sources
  # Read more about why at the following URLs:
  # https://github.com/smuellerDD/jitterentropy-rngd/issues/27
  # https://blogs.oracle.com/linux/post/rngd1
  services.jitterentropy-rngd.enable = true;
  boot.kernelModules = ["jitterentropy_rng"];

  # Don't store coredumps from systemd-coredump
  systemd.coredump.extraConfig = ''
    Storage=none
  '';

  systemd.tmpfiles.settings = {
    # Restrict permissions of /home/$USER so that only the owner of the
    # directory can access it (the user). systemd-tmpfiles also has the benefit
    # of recursively setting permissions too, with the "Z" option as seen below.
    "restricthome"."/home/*".Z.mode = "~0700";

    # Make all files in /etc/nixos owned by root, and only readable by root.
    # /etc/nixos is not owned by root by default, and configuration files can
    # on occasion end up also not owned by root. This can be hazardous as files
    # that are included in the rebuild may be editable by unprivileged users,
    # so this mitigates that.
    "restrictetcnixos"."/etc/nixos/*".Z = {
      mode = "0000";
      user = "root";
      group = "root";
    };
  };

  # Reduces need for swap
  zramSwap.enable = true;

  # Limit access to nix to users with the "wheel" group. ("sudoers")
  nix.settings.allowed-users = ["@wheel"];

  services = {
    timesyncd = {
      enable = false;
    };

    chrony = {
      enable = true;

      # Enable seccomp filter
      extraFlags = ["-F 1"];

      # Allow rtcsync
      enableRTCTrimming = false;

      # Prevent default servers
      servers = [];

      # Deprecated
      initstepslew.enabled = false;

      # https://github.com/GrapheneOS/infrastructure/blob/main/chrony.conf
      extraConfig = ''
        server time.cloudflare.com iburst nts
        server ntppool1.time.nl iburst nts
        server nts.netnod.se iburst nts
        server ptbtime1.ptb.de iburst nts
        server time.dfm.dk iburst nts
        server time.cifelli.xyz iburst nts

        minsources 3
        authselectmode require

        # EF
        dscp 46

        driftfile /var/lib/chrony/drift
        dumpdir /var/lib/chrony
        ntsdumpdir /var/lib/chrony

        leapseclist /usr/share/zoneinfo/leap-seconds.list
        makestep 1.0 3

        rtconutc
        rtcsync

        cmdport 0

        noclientlog
      '';
    };
  };
}
