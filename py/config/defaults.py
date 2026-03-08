"""
Ebbinghaus Benchmark — Default Configuration

This file defines all shared constants and parameter pools used across the
project. Researchers can modify these values to control what gets generated.
I encourage you to contact me if you feel there is an important default option missing.

For reproducibility purposes, I encourage you to edit defaults in this file.
Overriding constants outside of this file poses a risk of information lost.
"""

# --- Shape pools ---
# This defines which shapes are available for random selection. The geometric
# definition of each shape (how it is drawn) lives in src/draw_shape.py.
SHAPE_POOL = ["circle", "square"]

# --- Size ranges (as proportion of canvas min-dimension) ---
# These are multiplied by min(canvas_width, canvas_height) at generation time
# to produce plot-unit sizes. For example, 0.04 on a 768px canvas = ~30 units.
TEST_SIZE_RANGE = (0.03, 0.08)
SURROUND_SIZE_RANGE = (0.02, 0.15)

# --- Surround count range ---
SURROUND_N_RANGE = (4, 8)

# --- Surround distance range (as proportion of canvas min-dimension) ---
SURROUND_DISTANCE_RANGE = (0.08, 0.22)

# --- Color pools ---
# Colors use 6-digit hex codes for unambiguous storage.
COLOR_POOL = ["#000000", "#4D4D4D", "#999999", "#4682B4", "#B22222"]
FILL_POOL = ["#000000", "#4D4D4D", "#999999", "#4682B4", "#B22222", None]
# Background restricted to black and white only.
BACKGROUND_POOL = ["#FFFFFF", "#000000"]

# --- Canvas sizes (pixels) ---
CANVAS_SIZES = [512, 768, 1024]

# --- Orientation options ---
ORIENTATION_POOL = ["horizontal", "vertical", "diagonal"]

# --- File format options ---
FILE_FORMAT_POOL = ["png", "svg", "webp"]

# --- Verify trial tolerance ---
FLOAT_TOLERANCE = 1e-9

# --- Design defaults ---
DEFAULT_N_PER_TIER = 50
DEFAULT_FILE_FORMAT = "png"
DEFAULT_CANVAS_WIDTH = 768
DEFAULT_CANVAS_HEIGHT = 768
