# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: {
  imports = [./disks.nix];

  boot.initrd.availableKernelModules = ["xhci_pci" "thunderbolt" "nvme" "ahci" "usbhid" "usb_storage" "sd_mod" "hid_apple"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];
  boot.extraModprobeConfig = ''
    option i915 fastboot=1
    option nvidia_drm modeset=1
    options nouveau modeset=0
  '';
  boot.blacklistedKernelModules = ["nouveau" "nvidiafb"];

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
