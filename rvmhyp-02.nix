# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  # Minisforum MS-S1 MAX: AMD Ryzen AI Max+ 395 "Strix Halo", Radeon 8060S
  # iGPU (gfx1151). BIOS UMA carve-out reserves 48GB of unified RAM as VRAM.
  networking.hostName = "rvmhyp-02";

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr
      rocmPackages.clr.icd
    ];
  };

  hardware.amdgpu.initrd.enable = true;

  networking.firewall.allowedTCPPorts = [11434];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
    # gfx1151 has no official ROCm gfx target yet; override to the nearest
    # supported RDNA3.5 ISA so the runtime doesn't refuse to load the GPU.
    rocmOverrideGfx = "11.5.1";
    host = "0.0.0.0";
    port = 11434;
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "32768";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
    };
    loadModels = [
      # Coding
      "qwen2.5-coder:32b"
      "qwen2.5-coder:7b"
      # Reasoning
      "deepseek-r1:32b"
      "gpt-oss:20b"
    ];
  };
}
