library(shiny)
library(here)

source(here('..', 'common.R'))

SESSION_REFRESH_TIME <- 1000   # session refresh timer in milliseconds

ui <- fluidPage(
    tags$script(src = "js.cookie.min.js"),    # cookie JS library
    tags$script(src = "custom.js"),    # custom JS
    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),   # custom CSS
    # titlePanel("Shrager Memory Game: Participant App"),
    verticalLayout(
        uiOutput("mainContent")
    )
)

display_start <- function(sess, group) {
    div(sess$messages$not_started, class = "alert alert-info", style = "text-align: center")
}

display_directions <- function(sess, group) {
    msg_key <- paste0("directions_", group)
    directions <- sess$messages[[msg_key]]
    div(HTML(directions))
}

display_questions <- function(sess, group) {
    list_items <- lapply(1:length(sess$questions), function(i) {
        item <- sess$questions[[i]]
        tags$li(
            span(item$q),
            textInput(inputId = sprintf("answer_%s", i), label = NULL)
        )
    })
    tags$ol(list_items, id = "questions")
}

display_results <- function(sess, group) {
    p(paste("results;", group))
}

display_end <- function(sess, group) {
    div(sess$messages$end, class = "alert alert-info", style = "text-align: center")
}

server <- function(input, output, session) {
    state <- reactiveValues(
        sess_id = NULL,
        sess = NULL,
        group = NULL,
        sess_id_was_set = FALSE,
        group_was_set = FALSE
    )

    observe({
        params <- getQueryString()
        sess_id <- params$sess_id

        if (is.null(sess_id) || !validate_sess_id(sess_id)) {
            showModal(modalDialog("Invalid session ID or session ID not given.", footer = NULL))
        } else {
            state$sess_id <- sess_id

            invalidateLater(SESSION_REFRESH_TIME)

            if (!state$sess_id_was_set) {
                session$sendCustomMessage("set_sess_id", state$sess_id);
                isolate(state$sess_id_was_set <- TRUE)
            }

            if (state$group_was_set && state$group == "unassigned") {
                isolate(state$group <- sample(c("control", "treatment"), size = 1))
                print(sprintf("random assignment to %s", state$group))
                session$sendCustomMessage("set_group", state$group);
            }

            state$sess <- load_sess_config(state$sess_id)
        }
    })

    observeEvent(input$group, {
        print(paste("got group from JS:", input$group))
        isolate(state$group <- input$group)   # doesn't trigger update
        state$group_was_set <- TRUE    # triggers update
    })

    output$mainContent <- renderUI({
        req(state$sess)

        display_fn <- switch (state$sess$stage,
            start = display_start,
            directions = display_directions,
            questions = display_questions,
            results = display_results,
            end = display_end
        )

        do.call(display_fn, list(sess = state$sess, group = state$group))
    })
}

# Run the application
shinyApp(ui = ui, server = server)
