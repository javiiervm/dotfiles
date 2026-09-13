# NVIDIA HDMI power workaround

## Current behavior

On the HP OMEN hybrid-GPU setup:

- Boot without HDMI:
  - NVIDIA RTX 5070 eventually enters `suspended`.
- Connect HDMI:
  - NVIDIA wakes up normally and drives the external monitor.
- Disconnect HDMI:
  - NVIDIA remains `active` instead of returning to RTD3.
- Reboot without HDMI:
  - NVIDIA eventually returns to `suspended`.

## Current GPU layout

- AMD iGPU: `/dev/dri/card2`
  - Drives the internal `eDP-1` display.
- NVIDIA RTX 5070: `/dev/dri/card1`
  - Drives `HDMI-A-1`.

Hyprland currently uses both GPUs:

```lua
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")
hl.env("WLR_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")
````

## NVIDIA DRM configuration

Current `/etc/modprobe.d/nvidia.conf`:

```text
options nvidia-drm modeset=1 fbdev=0
options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0
```

After changing NVIDIA module options, regenerate the initramfs:

```bash
sudo mkinitcpio -P
```

## Check NVIDIA power state

```bash
cat /sys/bus/pci/devices/0000:04:00.0/power/runtime_status
```

Expected low-power state:

```text
suspended
```

## Temporary workaround

If HDMI has been used and the NVIDIA GPU remains `active` after disconnecting it:

1. Disconnect HDMI.
2. Reboot the laptop.
3. Do not reconnect HDMI.
4. Wait a few seconds after entering Hyprland.
5. Check the NVIDIA power state.

The RTX should eventually report:

```text
suspended
```

This workaround is temporary until HDMI hot-unplug can reliably return the NVIDIA GPU to RTD3 without restarting the system.
