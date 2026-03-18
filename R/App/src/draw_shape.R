# =============================================================================
# draw_shape.R — Atomic shape-drawing function
# =============================================================================
# Draws a single shape as a ggplot layer. Knows nothing about trials, the
# Ebbinghaus illusion, or experimental design.
#
# Returns a list of ggplot geoms that can be added to a plot with `+`.
# =============================================================================

library(ggplot2)
library(ggforce)

#' Draw a single shape as ggplot layer(s)
#'
#' @param shape Character: "circle" or "square"
#' @param x Numeric: center x-coordinate
#' @param y Numeric: center y-coordinate
#' @param size Numeric: radius (circle) or half side-length (square), in plot units
#' @param color Character: border/stroke color
#' @param fill Character or NA: fill color. NA = no fill (transparent).
#' @param alpha Numeric [0, 1]: opacity. Default 1.
#'
#' @return A list of ggplot2 geom layers
draw_shape <- function(shape, x, y, size, color = "black", fill = NA,
                       alpha = 1) {

  # --- Validate inputs ---
  stopifnot(
    is.character(shape), length(shape) == 1,
    shape %in% c("circle", "square"),
    is.numeric(x), length(x) == 1,
    is.numeric(y), length(y) == 1,
    is.numeric(size), length(size) == 1, size > 0,
    is.character(color), length(color) == 1,
    length(fill) == 1,
    is.numeric(alpha), length(alpha) == 1, alpha >= 0, alpha <= 1
  )

  # Resolve fill: NA means transparent
  fill_value <- if (is.na(fill)) NA_character_ else fill

  if (shape == "circle") {
    layer <- ggforce::geom_circle(
      aes(x0 = .env$x, y0 = .env$y, r = .env$size),
      color = color,
      fill  = fill_value,
      alpha = alpha
    )
  } else if (shape == "square") {
    # Square: size = half side-length, so side = 2 * size
    half <- size
    layer <- annotate(
      "rect",
      xmin  = x - half,
      xmax  = x + half,
      ymin  = y - half,
      ymax  = y + half,
      color = color,
      fill  = fill_value,
      alpha = alpha
    )
  }

  layer
}
