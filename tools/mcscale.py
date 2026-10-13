"""Horizontal scale of the Spectrum view: Spectrum pixels per C64 multicolour
pixel (the C64 view is 160 multicolour pixels across, 4 per yaw unit).

1.75 is the PAL picture aspect of C64 pixels (field of view +-18.3 yaw
units), chosen by the user after comparing builds at 1.625 (the full C64
field of view) and 2.0 (VICE proportions) with the C64.
"""

MC_SCALE = 1.75
YAW_SCALE = 4 * MC_SCALE          # Spectrum pixels per yaw unit


def mc_to_x(mc):
    """Spectrum x of C64 multicolour x (80 = centre)."""
    return 128 + (mc - 80) * MC_SCALE
