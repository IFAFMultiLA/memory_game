library(shiny)
library(here)
library(yaml)
library(stringi)


SESS_DIR <- here('..', 'sessions')
stopifnot("the sessions directory must exist" = fs::is_dir(SESS_DIR))

save_sess_config <- function(sess) {
    fname <- here(SESS_DIR, sess$sess_id, 'session.yaml')
    write_yaml(sess, fname)
}


ui <- fluidPage(
    # Application title
    titlePanel("Shrager Memory Game: Teacher App"),

    sidebarLayout(
        sidebarPanel(
            actionButton('createSession', 'Create session')
        ),
        mainPanel(
           uiOutput("activeSession")
        )
    )
)

server <- function(input, output) {
    state <- reactiveValues(sess = NULL)

    observeEvent(input$createSession, {
        sess_id <- NULL
        while (is.null(sess_id) || fs::dir_exists(here(SESS_DIR, sess_id))) {
            sess_id <- stri_rand_strings(1, 12)
        }

        fs::dir_create(here(SESS_DIR, sess_id))

        state$sess <- list(
            sess_id = sess_id,
            stage = "start",
            date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            language = "de",       # TODO: load from file
            sentences = list(),    # sentences to be memorized; TODO: load from file
            questions = list(),    # questions along with possible correct answers; TODO: load from file
            survey = list()        # post-experiment questionnaire; TODO: load from file
        )

        save_sess_config(state$sess)
    })

    output$activeSession <- renderUI({
        req(state$sess)

        h1(state$sess$sess_id)
    })
}

# Run the application
shinyApp(ui = ui, server = server)
