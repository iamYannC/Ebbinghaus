# =============================================================================
# Ebbinghaus Benchmark — Shiny App (Phase 1 UI)
# =============================================================================
# A bslib-powered interface for generating trial designs and rendering stimuli.
# Launch with: shiny::runApp("R/App") from the project root.
# =============================================================================

library(shiny)
library(bslib)
library(reactable)
library(dplyr)
library(ggplot2)
library(ggforce)

# --- Source bundled project files (order matters) ----------------------------

source("src/defaults.R")
source("src/verify_trial.R")
source("src/classify_tier.R")
source("src/generate_trial.R")
source("src/generate_design.R")
source("src/draw_shape.R")
source("src/draw_trial.R")
source("src/render_stimuli.R")

# --- Constants ---------------------------------------------------------------

TIER_CHOICES <- c(
  "Tier 0 - Sanity (no surrounds)"       = "0",
  "Tier 1 - Classic illusion"             = "1",
  "Tier 2 - Incongruent (opposes truth)"  = "2",
  "Tier 3 - Congruent (reinforces truth)" = "3"
)

# =============================================================================
# UI
# =============================================================================

ui <- page_navbar(
  title = tags$a(
    href = "https://zenodo.org/records/18915222",
    target = "_blank",
    title = "Click for the Project's official DOI",
    class = "d-flex align-items-center text-decoration-none me-4",
    tags$img(src = "hex.png", height = "100", class = "me-2"),
    tags$span("Ebbinghaus Benchmark", class = "fw-semibold")
  ),
  theme = bs_theme(
    version = 5,
    "navbar-padding-y" = "0",
    bg = "#e5e5e5", fg = "#356665", primary = "#c08c66",
    base_font = font_google("Ubuntu"),
    code_font = font_google("Iosevka Charon Mono"),
    "font-size-base" = "0.75rem", "enable-rounded" = FALSE
  ),
  
  fillable = TRUE,

  # --- Tab 0: Welcome ---------------------------------------------------------

  nav_panel(
    "Welcome",
    div(
      style = "padding: 3rem;",
      div(
        style = "max-width: 640px; font-size: 1.5rem;",
        tags$p(
          "The Ebbinghaus Benchmark is an open-source project I've put",
          " together to allow researchers a simple yet flexible API to generate",
          " variants of the Ebbinghaus Illusion. The full project is on ",
          tags$a("GitHub", href = "https://github.com/iamYannC/Ebbinghaus",
                 target = "_blank"),
          " and ",
          tags$a("Kaggle", href = "https://www.kaggle.com/datasets/yanncohen/ebbinghaus-illusion-benchmark",
                 target = "_blank"),
          ", and is comprised of two additional phases: Evaluation and Analysis.",
          " It is suitable both as an AI benchmark and for human participants."
        ),
        tags$p(
          "You can also find a Python implementation and a ",
          tags$a("notebook example",
                 href = "https://www.kaggle.com/code/yanncohen/ebbinghaus-illusion-benchmark-python",
                 target = "_blank"),
          " with open-source, free models."
        ),
        tags$p(
          "In this application I provide you with a UI to generate the",
          " underlying table as well as the stimuli. Please read more about",
          " the different options in my repository and contact me if you have",
          " further questions."
        ),
        tags$hr(class = "my-4", style = "max-width: 200px; margin-inline: auto;"),
        tags$p(
          class = "mb-1",
          "I hope you find it useful."
        ),
        tags$p(
          tags$strong("Yann."),
          tags$br(),
          tags$a("yann-dev.io",
                 href = "https://iamyannc.github.io/Yann-dev",
                 target = "_blank")
        )
      )
    )
  ),

  # --- Tab 1: Trials ---------------------------------------------------------

  nav_panel(
    "Trials",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        checkboxGroupInput(
          "tiers", "Tiers to generate",
          choices = TIER_CHOICES,
          selected = as.character(0:3)
        ),
        numericInput("n_per_tier", "Trials per tier",
                     value = 10, min = 1, max = 500, step = 1),
        numericInput("master_seed", "Master seed",
                     value = NA, step = 1),
        helpText("Leave blank for a random seed."),
        tags$hr(),
        tags$p(
          tags$strong("Total trials: "),
          textOutput("total_trials", inline = TRUE)
        ),
        actionButton("generate_btn", "Generate Design",
                     class = "btn-primary w-100"),
        tags$hr(),
        downloadButton("download_csv", "Download CSV",
                       class = "btn-outline-secondary w-100")
      ),
      card(
        full_screen = TRUE,
        card_header("Design Matrix"),
        reactableOutput("trials_table")
      )
    )
  ),

  # --- Tab 2: Stimuli --------------------------------------------------------

  nav_panel(
    "Stimuli",
    layout_sidebar(
      sidebar = sidebar(
        width = 250,
        actionButton("render_btn", "Generate Stimuli",
                     class = "btn-primary w-100"),
        tags$hr(),
        downloadButton("download_zip", "Download ZIP",
                       class = "btn-outline-secondary w-100")
      ),
      card(
        full_screen = TRUE,
        card_header(textOutput("stimuli_header", inline = TRUE)),
        div(
          style = "overflow-y: auto;",
          uiOutput("stimuli_grid")
        )
      )
    )
  ),

  # --- Tab 3: Configuration --------------------------------------------------

  nav_panel(
    "Configuration",
    tags$div(
      style = "column-count: 3; column-gap: 1rem; padding: 0.5rem;",

      # Shapes
      card(
        style = "break-inside: avoid; margin-bottom: 1rem;",
        card_header("Shapes"),
        card_body(
          checkboxGroupInput(
            "cfg_shape_pool", "Shape pool",
            choices = c("circle", "square"),
            selected = SHAPE_POOL
          ),
          checkboxGroupInput(
            "cfg_orientation_pool", "Orientation pool",
            choices = c("horizontal", "vertical", "diagonal"),
            selected = ORIENTATION_POOL
          )
        )
      ),

      # Sizes & Distances
      card(
        style = "break-inside: avoid; margin-bottom: 1rem;",
        card_header("Sizes & Distances"),
        card_body(
          tags$label("Test size range"),
          layout_columns(
            col_widths = c(6, 6),
            numericInput("cfg_test_size_min", "Min",
                         TEST_SIZE_RANGE[1], min = 0.01, max = 0.5, step = 0.01),
            numericInput("cfg_test_size_max", "Max",
                         TEST_SIZE_RANGE[2], min = 0.01, max = 0.5, step = 0.01)
          ),
          tags$label("Surround size range"),
          layout_columns(
            col_widths = c(6, 6),
            numericInput("cfg_surround_size_min", "Min",
                         SURROUND_SIZE_RANGE[1], min = 0.01, max = 0.5, step = 0.01),
            numericInput("cfg_surround_size_max", "Max",
                         SURROUND_SIZE_RANGE[2], min = 0.01, max = 0.5, step = 0.01)
          ),
          tags$label("Surround count range"),
          layout_columns(
            col_widths = c(6, 6),
            numericInput("cfg_surround_n_min", "Min",
                         SURROUND_N_RANGE[1], min = 1, max = 20, step = 1),
            numericInput("cfg_surround_n_max", "Max",
                         SURROUND_N_RANGE[2], min = 1, max = 20, step = 1)
          ),
          tags$label("Surround distance range"),
          layout_columns(
            col_widths = c(6, 6),
            numericInput("cfg_surround_dist_min", "Min",
                         SURROUND_DISTANCE_RANGE[1], min = 0.01, max = 0.5, step = 0.01),
            numericInput("cfg_surround_dist_max", "Max",
                         SURROUND_DISTANCE_RANGE[2], min = 0.01, max = 0.5, step = 0.01)
          )
        )
      ),

      # Colors
      card(
        style = "break-inside: avoid; margin-bottom: 1rem;",
        card_header("Colors"),
        card_body(
          textAreaInput(
            "cfg_color_pool", "Color pool (hex, one per line)",
            value = paste(COLOR_POOL, collapse = "\n"), rows = 5
          ),
          textAreaInput(
            "cfg_fill_pool", "Fill pool (hex or NA, one per line)",
            value = paste(
              ifelse(is.na(FILL_POOL), "NA", FILL_POOL),
              collapse = "\n"
            ),
            rows = 5
          ),
          checkboxGroupInput(
            "cfg_background_pool", "Background pool",
            choices = c("White (#FFFFFF)" = "#FFFFFF",
                        "Black (#000000)" = "#000000"),
            selected = BACKGROUND_POOL
          )
        )
      ),

      # Canvas & Output
      card(
        style = "break-inside: avoid; margin-bottom: 1rem;",
        card_header("Canvas & Output"),
        card_body(
          checkboxGroupInput(
            "cfg_canvas_sizes", "Canvas sizes (px)",
            choices = c("512" = "512", "768" = "768", "1024" = "1024"),
            selected = as.character(CANVAS_SIZES)
          ),
          selectInput(
            "cfg_default_format", "Select file format",
            choices = FILE_FORMAT_POOL,
            selected = DEFAULT_FILE_FORMAT
          )
        )
      ),

      # Advanced
      card(
        style = "break-inside: avoid; margin-bottom: 1rem;",
        card_header("Advanced"),
        card_body(
          numericInput("cfg_float_tolerance", "Float tolerance",
                       FLOAT_TOLERANCE, min = 1e-15, max = 1e-3)
        )
      )
    ),

    tags$div(
      class = "mt-3 mb-3 ms-2",
      actionButton("reset_config", "Reset to Defaults",
                   class = "btn-outline-danger")
    )
  ),

  # --- Right-aligned: GitHub icon --------------------------------------------

  nav_spacer(),
  nav_item(
    tags$a(
      href = "https://github.com/iamYannC/Ebbinghaus",
      target = "_blank",
      title = "Benchmark Repo on GitHub",
      class = "nav-link px-2",
      tags$svg(
        xmlns = "http://www.w3.org/2000/svg",
        width = "20", height = "20", fill = "currentColor",
        viewBox = "0 0 16 16",
        tags$path(d = paste0(
          "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17",
          ".55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23",
          "-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82",
          ".72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89",
          "-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 ",
          ".67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 ",
          "2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 ",
          "3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93",
          "-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"
        ))
      )
    )
  )
)

# =============================================================================
# Server
# =============================================================================

server <- function(input, output, session) {

  rv <- reactiveValues(
    trials           = NULL,
    stimuli_dir      = NULL,
    stimuli_rendered = FALSE
  )

  # --- Helpers ---------------------------------------------------------------

  parse_hex_pool <- function(text, allow_na = FALSE) {
    lines <- trimws(strsplit(text, "\n")[[1]])
    lines <- lines[nzchar(lines)]
    if (length(lines) == 0) return(NULL)

    is_na <- toupper(lines) == "NA"
    hex_vals <- lines[!is_na]
    valid <- grepl("^#[0-9A-Fa-f]{6}$", hex_vals)

    if (!all(valid)) {
      showNotification(
        paste("Invalid hex codes:", paste(hex_vals[!valid], collapse = ", ")),
        type = "error"
      )
      return(NULL)
    }

    if (allow_na) {
      result <- ifelse(is_na, NA_character_, lines)
    } else {
      if (any(is_na)) {
        showNotification("NA is not allowed in this color pool.", type = "error")
        return(NULL)
      }
      result <- lines
    }
    result
  }

  validate_config <- function() {
    problems <- character()

    if (length(input$cfg_shape_pool) == 0)
      problems <- c(problems, "Select at least one shape.")
    if (length(input$cfg_orientation_pool) == 0)
      problems <- c(problems, "Select at least one orientation.")
    if (length(input$cfg_background_pool) == 0)
      problems <- c(problems, "Select at least one background color.")
    if (length(input$cfg_canvas_sizes) == 0)
      problems <- c(problems, "Select at least one canvas size.")

    for (msg in problems) showNotification(msg, type = "error")
    length(problems) == 0
  }

  # --- Total trials label ----------------------------------------------------

  output$total_trials <- renderText({
    n_tiers <- length(input$tiers)
    n_per <- input$n_per_tier %||% 0
    paste0(n_tiers, " tiers x ", n_per, " = ", n_tiers * n_per)
  })

  # --- Generate design -------------------------------------------------------

  observeEvent(input$generate_btn, {
    selected_tiers <- as.integer(input$tiers)
    n_per_tier <- input$n_per_tier
    seed <- if (is.na(input$master_seed)) NULL else as.integer(input$master_seed)

    if (length(selected_tiers) == 0) {
      showNotification("Select at least one tier.", type = "error")
      return()
    }
    if (is.na(n_per_tier) || n_per_tier < 1) {
      showNotification("Trials per tier must be at least 1.", type = "error")
      return()
    }
    if (!validate_config()) return()

    color_pool <- parse_hex_pool(input$cfg_color_pool, allow_na = FALSE)
    fill_pool  <- parse_hex_pool(input$cfg_fill_pool, allow_na = TRUE)
    if (is.null(color_pool) || is.null(fill_pool)) return()

    img_dir <- file.path(tempdir(), "ebbinghaus_stimuli")
    if (dir.exists(img_dir)) unlink(img_dir, recursive = TRUE)
    dir.create(img_dir, recursive = TRUE)

    file_format <- input$cfg_default_format

    withProgress(message = "Generating design...", value = 0, {
      if (is.null(seed)) seed <- round(runif(1, -1e9, 1e9))
      set.seed(seed)

      total <- n_per_tier * length(selected_tiers)
      trial_seeds <- round(runif(total, -1e9, 1e9))
      tier_vec <- rep(selected_tiers, each = n_per_tier)

      trials_list <- vector("list", total)
      for (i in seq_len(total)) {
        trials_list[[i]] <- generate_trial(
          seed                    = trial_seeds[i],
          tier                    = tier_vec[i],
          file_format             = file_format,
          shape_pool              = input$cfg_shape_pool,
          size_range              = c(input$cfg_test_size_min,
                                      input$cfg_test_size_max),
          surround_size_range     = c(input$cfg_surround_size_min,
                                      input$cfg_surround_size_max),
          surround_n_range        = c(as.integer(input$cfg_surround_n_min),
                                      as.integer(input$cfg_surround_n_max)),
          surround_distance_range = c(input$cfg_surround_dist_min,
                                      input$cfg_surround_dist_max),
          canvas_sizes            = as.integer(input$cfg_canvas_sizes),
          color_pool              = color_pool,
          fill_pool               = fill_pool,
          background_pool         = input$cfg_background_pool,
          orientation_pool        = input$cfg_orientation_pool
        )
        incProgress(1 / total)
      }

      trials <- do.call(rbind, trials_list)

      # Shuffle so tiers are interleaved
      set.seed(seed + 1L)
      trials <- trials[sample(nrow(trials)), ]

      trials$trial_id    <- seq_len(nrow(trials))
      trials$master_seed <- seed

      tier_label <- ifelse(is.na(trials$tier), "tNA", paste0("t", trials$tier))
      trials$file_path <- file.path(
        img_dir,
        paste0(trials$trial_id, "_", trials$true_larger, "_",
               tier_label, ".", trials$file_format)
      )
      rownames(trials) <- NULL

      rv$trials           <- trials
      rv$stimuli_dir      <- img_dir
      rv$stimuli_rendered <- FALSE
    })

    showNotification(
      paste0("Generated ", nrow(rv$trials), " trials (seed: ", seed, ")"),
      type = "message"
    )
  })

  # --- Trials table ----------------------------------------------------------

  output$trials_table <- renderReactable({
    req(rv$trials)

    display_cols <- c(
      "trial_id", "tier", "true_larger", "true_diff_ratio",
      "orientation", "canvas_width", "canvas_height",
      "test_a_shape", "test_a_size", "test_b_shape", "test_b_size",
      "surround_a_n", "surround_b_n",
      "background_color", "file_format", "master_seed"
    )
    df <- rv$trials[, intersect(display_cols, names(rv$trials))]

    reactable(
      df,
      searchable = TRUE,
      striped    = TRUE,
      compact    = TRUE,
      defaultPageSize = 20,
      columns = list(
        true_diff_ratio = colDef(format = colFormat(digits = 4)),
        test_a_size     = colDef(format = colFormat(digits = 2)),
        test_b_size     = colDef(format = colFormat(digits = 2))
      )
    )
  })

  # --- Download CSV ----------------------------------------------------------

  output$download_csv <- downloadHandler(
    filename = function() {
      req(rv$trials)
      seed <- rv$trials$master_seed[1]
      n <- nrow(rv$trials)
      paste0(format(Sys.Date(), "%Y-%m"), "-", seed, "-", n, ".csv")
    },
    content = function(file) {
      write.csv(rv$trials, file, row.names = FALSE)
    }
  )

  # --- Render stimuli --------------------------------------------------------

  observeEvent(input$render_btn, {
    req(rv$trials)

    trials <- rv$trials
    n <- nrow(trials)

    withProgress(message = "Rendering stimuli...", value = 0, {
      dirs <- unique(dirname(trials$file_path))
      for (d in dirs) {
        if (!dir.exists(d)) dir.create(d, recursive = TRUE)
      }

      for (i in seq_len(n)) {
        row <- trials[i, ]

        # Coerce empty strings to NA (safety for Python-generated data)
        chr_cols <- vapply(row, is.character, logical(1))
        row[chr_cols] <- lapply(row[chr_cols], function(x) {
          x[x == ""] <- NA_character_; x
        })

        p <- draw_trial(row)

        ggsave(
          row$file_path, plot = p,
          width  = row$canvas_width / 96,
          height = row$canvas_height / 96,
          dpi = 96, units = "in",
          bg = row$background_color,
          device = if (row$file_format == "svg") "svg" else NULL
        )

        incProgress(1 / n, detail = paste0(i, " / ", n))
      }
    })

    rv$stimuli_rendered <- TRUE
    addResourcePath("stimuli", rv$stimuli_dir)

    showNotification(
      paste0("Rendered ", n, " stimuli."),
      type = "message"
    )
  })

  # --- Stimuli header --------------------------------------------------------

  output$stimuli_header <- renderText({
    if (isTRUE(rv$stimuli_rendered)) {
      paste0("Stimuli (", nrow(rv$trials), " images)")
    } else {
      "Stimuli"
    }
  })

  # --- Stimuli grid ----------------------------------------------------------

  output$stimuli_grid <- renderUI({
    if (is.null(rv$trials)) {
      return(tags$p(
        class = "text-muted m-3",
        "Generate a design in the Trials tab first."
      ))
    }
    if (!isTRUE(rv$stimuli_rendered)) {
      return(tags$p(
        class = "text-muted m-3",
        "Click ", tags$strong("Generate Stimuli"), " to render images."
      ))
    }

    trials <- rv$trials
    fnames <- basename(trials$file_path)

    grid_items <- lapply(seq_len(nrow(trials)), function(i) {
      src <- paste0("stimuli/", fnames[i])
      tags$div(
        style = "text-align: center; cursor: pointer;",
        tags$img(
          src = src,
          class = "img-fluid rounded",
          style = "max-width: 100%; border: 1px solid #dee2e6;",
          onclick = sprintf(
            "Shiny.setInputValue('preview_img', '%s', {priority: 'event'})",
            src
          )
        ),
        tags$small(class = "text-muted d-block mt-1", fnames[i])
      )
    })

    tags$div(
      style = paste(
        "display: grid;",
        "grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));",
        "gap: 16px; padding: 8px;"
      ),
      grid_items
    )
  })

  # --- Image preview modal ---------------------------------------------------

  observeEvent(input$preview_img, {
    showModal(modalDialog(
      tags$img(src = input$preview_img, style = "width: 100%;"),
      size = "l",
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })

  # --- Download ZIP ----------------------------------------------------------

  output$download_zip <- downloadHandler(
    filename = function() {
      req(rv$trials, rv$stimuli_rendered)
      seed <- rv$trials$master_seed[1]
      n <- nrow(rv$trials)
      paste0(format(Sys.Date(), "%Y-%m"), "-", seed, "-", n, ".zip")
    },
    content = function(file) {
      files <- list.files(rv$stimuli_dir, full.names = TRUE)
      zip(file, files, flags = "-j")
    }
  )

  # --- Reset configuration ---------------------------------------------------

  observeEvent(input$reset_config, {
    updateCheckboxGroupInput(session, "cfg_shape_pool",
                             selected = c("circle", "square"))
    updateCheckboxGroupInput(session, "cfg_orientation_pool",
                             selected = c("horizontal", "vertical", "diagonal"))
    updateNumericInput(session, "cfg_test_size_min",     value = 0.03)
    updateNumericInput(session, "cfg_test_size_max",     value = 0.08)
    updateNumericInput(session, "cfg_surround_size_min", value = 0.02)
    updateNumericInput(session, "cfg_surround_size_max", value = 0.15)
    updateNumericInput(session, "cfg_surround_n_min",    value = 4)
    updateNumericInput(session, "cfg_surround_n_max",    value = 8)
    updateNumericInput(session, "cfg_surround_dist_min", value = 0.08)
    updateNumericInput(session, "cfg_surround_dist_max", value = 0.22)
    updateTextAreaInput(session, "cfg_color_pool",
      value = paste(c("#000000", "#4D4D4D", "#999999", "#4682B4", "#B22222"),
                    collapse = "\n"))
    updateTextAreaInput(session, "cfg_fill_pool",
      value = paste(c("#000000", "#4D4D4D", "#999999", "#4682B4", "#B22222", "NA"),
                    collapse = "\n"))
    updateCheckboxGroupInput(session, "cfg_background_pool",
                             selected = c("#FFFFFF", "#000000"))
    updateCheckboxGroupInput(session, "cfg_canvas_sizes",
                             selected = c("512", "768", "1024"))
    updateSelectInput(session, "cfg_default_format", selected = "png")
    updateNumericInput(session, "cfg_float_tolerance", value = 1e-9)
    updateNumericInput(session, "cfg_n_per_tier",     value = 50)

    showNotification("Configuration reset to defaults.", type = "message")
  })
}

# =============================================================================

shinyApp(ui, server)
