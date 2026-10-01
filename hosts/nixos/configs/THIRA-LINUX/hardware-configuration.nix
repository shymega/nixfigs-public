# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: {
  imports = [./disks.nix];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "sdhci_pci"
    "i915"
    "hid_apple"
  ];
  boot.initrd.kernelModules = [
    "i915"
    "thunderbolt"
    "hid_apple"
  ];
  boot.kernelModules = [
    "kvm-intel"
    "i915"
  ];
  boot.extraModulePackages = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
