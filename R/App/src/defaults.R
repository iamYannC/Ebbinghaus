# =============================================================================
# Ebbinghaus Benchmark — Default Configuration
# =============================================================================
# This file defines all shared constants and parameter pools used across the
# project. Researchers can modify these values to control what gets generated.
# I encourage you to contact me if you feel there is an important default option missing.
#
# For reproducibility purposes, I encourage you to edit defaults in this file.
# Overriding constants outside of this file pose a risk of information lost.
# =============================================================================

# --- Shape pools ---
# This defines which shapes are available for random selection. The geometric
# definition of each shape (how it is drawn) lives in R/draw_shape.R.
SHAPE_POOL <- c("circle", "square")

# --- Size ranges (as proportion of canvas min-dimension) ---
# These are multiplied by min(canvas_width, canvas_height) at generation time
# to produce plot-unit sizes. For example, 0.04 on a 768px canvas = ~30 units.
TEST_SIZE_RANGE      <- c(0.03, 0.08)
SURROUND_SIZE_RANGE  <- c(0.02, 0.15)

# --- Surround count range ---
SURROUND_N_RANGE <- c(4L, 8L)

# --- Surround distance range (as proportion of canvas min-dimension) ---
SURROUND_DISTANCE_RANGE <- c(0.08, 0.22)

# --- Color pools ---
# Colors use 6-digit hex codes for unambiguous storage.
COLOR_POOL      <- c("#000000", "#4D4D4D", "#999999", "#4682B4", "#B22222")
FILL_POOL       <- c("#000000", "#4D4D4D", "#999999", "#4682B4", "#B22222", NA)
# Background restricted to black and white only.
BACKGROUND_POOL <- c("#FFFFFF", "#000000")

# --- Canvas sizes (pixels) ---
CANVAS_SIZES <- c(512L, 768L, 1024L)

# --- Orientation options ---
ORIENTATION_POOL <- c("horizontal", "vertical", "diagonal")

# --- File format options ---
FILE_FORMAT_POOL <- c("png", "svg", "webp")

# --- Verify trial tolerance ---
FLOAT_TOLERANCE <- 1e-9

# --- Design defaults ---
DEFAULT_N_PER_TIER   <- 50L   # Minimum trials per tier in generate_design()
DEFAULT_FILE_FORMAT  <- "png"
DEFAULT_CANVAS_WIDTH  <- 768L
DEFAULT_CANVAS_HEIGHT <- 768L
