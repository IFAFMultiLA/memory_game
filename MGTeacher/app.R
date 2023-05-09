library(shiny)
library(here)
library(yaml)
library(stringi)


SESS_DIR <- fs::path_abs(here("..", "sessions"))
stopifnot("the sessions directory must exist" = fs::is_dir(SESS_DIR))

save_sess_config <- function(sess) {
    write_yaml(sess, here(SESS_DIR, sess$sess_id, "session.yaml"))
}

load_sess_config <- function(sess_id) {
    read_yaml(here(SESS_DIR, sess_id, "session.yaml"))
}


ui <- fluidPage(
    # Application title
    titlePanel("Shrager Memory Game: Teacher App"),

    sidebarLayout(
        sidebarPanel(
            uiOutput("sessionsList"),
            actionButton("createSession", "Create a new session")
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

    observeEvent(input$sessionsSelect, {
        state$sess <- load_sess_config(input$sessionsSelect)
    })

    output$sessionsList <- renderUI({
        session_dirs <- fs::dir_ls(here(SESS_DIR), type = "directory")
        session_dates <- sapply(as.character(session_dirs), function(d) {
            read_yaml(here(d, "session.yaml"))$date
        }, USE.NAMES = FALSE)
        sortindices <- order(session_dates)
        session_ids <- basename(session_dirs)[sortindices]
        session_dates <- session_dates[sortindices]

        session_opts <- session_ids
        names(session_opts) <- sprintf("%s – %s", session_dates, session_ids)

        selectInput("sessionsSelect", "Load session:", session_opts, selected = state$sess$sess_id)
    })

    output$activeSession <- renderUI({
        req(state$sess)

        list(
            h1(sprintf("Session %s", state$sess$sess_id)),
            tags$ul(
                tags$li(sprintf("Date: %s", state$sess$date)),
                tags$li(sprintf("Language: %s", state$sess$language)),
                tags$li(sprintf("Current stage: %s", state$sess$stage))
            )
        )
    })
}

# Run the application
shinyApp(ui = ui, server = server)
