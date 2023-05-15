library(shiny)
library(here)

source(here('..', 'common.R'))

SESSION_REFRESH_TIME <- 1000   # session refresh timer in milliseconds

ui <- fluidPage(
    tags$script(src = "js.cookie.min.js"),    # cookie JS library
    tags$script(src = "custom.js"),    # custom JS
    titlePanel("Shrager Memory Game: Participant App"),
    verticalLayout(
        uiOutput("mainContent")
    )
)

display_start <- function(sess, group) {
    div(sess$messages$not_started, class = "alert alert-info", style = "text-align: center")
}

display_directions <- function(sess, group) {
    p(paste("directions;", group))
}

display_questions <- function(sess, group) {
    p(paste("questions;", group))
}

display_results <- function(sess, group) {
    p(paste("results;", group))
}

display_end <- function(sess, group) {
    div(sess$messages$end, class = "alert alert-info", style = "text-align: center")
}

server <- function(input, output, session) {
    # note: reactive value objects like "group" are actually functions; use group() to read its value and
    # group(<arg>) to set its value; see ?shiny::reactiveVal for more information
    group <- reactiveVal()    # initially NULL; on start either "control" or "treatment"
    sess_id_was_set <- reactiveVal(FALSE)
    group_was_set <- reactiveVal(FALSE)

    observeEvent(input$group, {
        print(paste("got group from JS:", input$group))
        isolate(group(input$group))
        group_was_set(TRUE)
    })

    output$mainContent <- renderUI({
        params <- getQueryString()
        sess_id <- params$sess_id
        if (is.null(sess_id) || !validate_sess_id(sess_id)) {
            showModal(modalDialog("Invalid session ID or session ID not given.", footer = NULL))
        } else {
            invalidateLater(SESSION_REFRESH_TIME)

            if (!sess_id_was_set()) {
                session$sendCustomMessage("set_sess_id", sess_id);
                isolate(sess_id_was_set(TRUE))
            }

            if (group_was_set() && group() == "unassigned") {
                isolate(group(sample(c("control", "treatment"), size = 1)))
                print("random assignment")
                session$sendCustomMessage("set_group", group());
            }

            sess <- load_sess_config(sess_id)

            print(group())

            display_fn <- switch (sess$stage,
                start = display_start,
                directions = display_directions,
                questions = display_questions,
                results = display_results,
                end = display_end
            )

            do.call(display_fn, list(sess = sess, group = group()))
        }
    })
}

# Run the application
shinyApp(ui = ui, server = server)
