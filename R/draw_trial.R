# =============================================================================
# draw_trial.R — Compose a full Ebbinghaus stimulus from a trial row
# =============================================================================
# Takes a single trial row (one-row data frame or named list) and returns
# a complete ggplot object ready for display or saving.
#
# Consumes parameters from the trials table schema. Does not generate,
# modify, or infer any parameters.
# =============================================================================

source("Ebbinghaus/R/draw_shape.R")

#' Draw a complete Ebbinghaus stimulus from trial parameters
#'
#' @param trial A one-row data frame or named list with the trials table schema.
#'
#' @return A ggplot object (the complete stimulus image).
draw_trial <- function(trial) {


  # Coerce to list for easy access
  if (is.data.frame(trial)) {
    stopifnot(nrow(trial) == 1)
    trial <- as.list(trial)
  }

  # --- Compute center positions for groups A and B based on orientation ---
  positions <- compute_group_positions(trial$orientation, trial$canvas_width,
                                       trial$canvas_height)
  ax <- positions$a_x
  ay <- positions$a_y
  bx <- positions$b_x
  by <- positions$b_y

  # --- Compute bounding box for all shapes ---
  # We need to know the full extent of every shape so we can set axis limits
  # that contain everything without clipping.
  all_extents <- compute_all_extents(trial, positions)

  # --- Build the plot ---
  p <- ggplot() +
    theme_void() +
    theme(
      plot.background = element_rect(fill = trial$background_color, color = NA),
      plot.margin = margin(0, 0, 0, 0)
    )

  # --- Draw surround shapes (behind test shapes) ---
  # Group A surrounds
  if (!is.na(trial$surround_a_n) && trial$surround_a_n > 0) {
    surround_positions_a <- compute_surround_positions(
      cx = ax, cy = ay,
      n = trial$surround_a_n,
      distance = trial$surround_a_distance
    )
    for (j in seq_len(trial$surround_a_n)) {
      p <- p + draw_shape(
        shape = trial$surround_a_shape,
        x     = surround_positions_a$x[j],
        y     = surround_positions_a$y[j],
        size  = trial$surround_a_size,
        color = trial$surround_a_color,
        fill  = if (is.na(trial$surround_a_fill)) NA else trial$surround_a_fill
      )
    }
  }

  # Group B surrounds
  if (!is.na(trial$surround_b_n) && trial$surround_b_n > 0) {
    surround_positions_b <- compute_surround_positions(
      cx = bx, cy = by,
      n = trial$surround_b_n,
      distance = trial$surround_b_distance
    )
    for (j in seq_len(trial$surround_b_n)) {
      p <- p + draw_shape(
        shape = trial$surround_b_shape,
        x     = surround_positions_b$x[j],
        y     = surround_positions_b$y[j],
        size  = trial$surround_b_size,
        color = trial$surround_b_color,
        fill  = if (is.na(trial$surround_b_fill)) NA else trial$surround_b_fill
      )
    }
  }

  # --- Draw test shapes (on top) ---
  p <- p + draw_shape(
    shape = trial$test_a_shape,
    x     = ax,
    y     = ay,
    size  = trial$test_a_size,
    color = trial$test_a_color,
    fill  = if (is.na(trial$test_a_fill)) NA else trial$test_a_fill
  )

  p <- p + draw_shape(
    shape = trial$test_b_shape,
    x     = bx,
    y     = by,
    size  = trial$test_b_size,
    color = trial$test_b_color,
    fill  = if (is.na(trial$test_b_fill)) NA else trial$test_b_fill
  )

  # --- Set axis limits using coord_fixed ---
  # coord_fixed with explicit xlim/ylim clips visually at the boundary
  # but does NOT discard geometry (unlike scale xlim/ylim which remove data).
  # We use the computed bounding box to ensure all shapes are fully contained.
  p <- p +
    coord_fixed(
      xlim = c(all_extents$xmin, all_extents$xmax),
      ylim = c(all_extents$ymin, all_extents$ymax),
      clip = "off"
    )

  p
}


#' Compute center positions for groups A and B based on orientation
#'
#' @param orientation "horizontal", "vertical", or "diagonal"
#' @param canvas_width Canvas width
#' @param canvas_height Canvas height
#'
#' @return A list with a_x, a_y, b_x, b_y
compute_group_positions <- function(orientation, canvas_width, canvas_height) {

  cx <- canvas_width / 2
  cy <- canvas_height / 2

  # Offset: place groups at 25% and 75% of the relevant axis
  switch(orientation,
    horizontal = list(
      a_x = canvas_width * 0.25,  a_y = cy,
      b_x = canvas_width * 0.75,  b_y = cy
    ),
    vertical = list(
      a_x = cx,  a_y = canvas_height * 0.75,   # A = top
      b_x = cx,  b_y = canvas_height * 0.25    # B = bottom
    ),
    diagonal = list(
      a_x = canvas_width * 0.25,   a_y = canvas_height * 0.75,   # A = upper-left
      b_x = canvas_width * 0.75,   b_y = canvas_height * 0.25    # B = lower-right
    ),
    stop("Unknown orientation: ", orientation)
  )
}


#' Compute positions for N surround shapes equally spaced around a center
#'
#' @param cx Center x
#' @param cy Center y
#' @param n Number of surround shapes
#' @param distance Distance from center to each surround center
#'
#' @return A data frame with x and y columns
compute_surround_positions <- function(cx, cy, n, distance) {

  angles <- seq(0, 2 * pi, length.out = n + 1)[-(n + 1)]

  data.frame(
    x = cx + distance * cos(angles),
    y = cy + distance * sin(angles)
  )
}


#' Compute bounding box that contains all shapes in a trial
#'
#' Examines test shapes and surround shapes and returns the min/max x/y
#' needed to fully contain every shape, plus a padding margin.
#'
#' @param trial A trial as a list
#' @param positions Output of compute_group_positions()
#' @param padding Fraction of total extent to add as margin. Default 0.05 (5%).
#'
#' @return A list with xmin, xmax, ymin, ymax
compute_all_extents <- function(trial, positions, padding = 0.05) {

  # Start with test shape extents
  # For both circle (radius = size) and square (half-side = size),
  # the shape extends `size` units from center in each direction.
  all_x <- c(positions$a_x - trial$test_a_size, positions$a_x + trial$test_a_size,
              positions$b_x - trial$test_b_size, positions$b_x + trial$test_b_size)
  all_y <- c(positions$a_y - trial$test_a_size, positions$a_y + trial$test_a_size,
              positions$b_y - trial$test_b_size, positions$b_y + trial$test_b_size)

  # Add surround shape extents for group A
  if (!is.na(trial$surround_a_n) && trial$surround_a_n > 0) {
    spos_a <- compute_surround_positions(
      positions$a_x, positions$a_y,
      trial$surround_a_n, trial$surround_a_distance
    )
    all_x <- c(all_x, spos_a$x - trial$surround_a_size,
                       spos_a$x + trial$surround_a_size)
    all_y <- c(all_y, spos_a$y - trial$surround_a_size,
                       spos_a$y + trial$surround_a_size)
  }

  # Add surround shape extents for group B
  if (!is.na(trial$surround_b_n) && trial$surround_b_n > 0) {
    spos_b <- compute_surround_positions(
      positions$b_x, positions$b_y,
      trial$surround_b_n, trial$surround_b_distance
    )
    all_x <- c(all_x, spos_b$x - trial$surround_b_size,
                       spos_b$x + trial$surround_b_size)
    all_y <- c(all_y, spos_b$y - trial$surround_b_size,
                       spos_b$y + trial$surround_b_size)
  }

  xmin <- min(all_x)
  xmax <- max(all_x)
  ymin <- min(all_y)
  ymax <- max(all_y)

  # Add padding
  x_pad <- (xmax - xmin) * padding
  y_pad <- (ymax - ymin) * padding

  list(
    xmin = xmin - x_pad,
    xmax = xmax + x_pad,
    ymin = ymin - y_pad,
    ymax = ymax + y_pad
  )
}
