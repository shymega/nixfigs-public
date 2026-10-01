# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: {
  imports = [./disks.nix];

  boot.initrd.availableKernelModules = ["nvme" "thunderbolt" "xhci_pci" "usbhid" "usb_storage" "sd_mod" "amdgpu" "hid_apple"];
  boot.initrd.kernelModules = ["amdgpu" "hid-apple"];
  boot.kernelModules = ["kvm-amd" "amdgpu"];
  boot.extraModulePackages = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
