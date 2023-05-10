library(shiny)
library(here)
library(stringi)

source(here('..', 'common.R'))

TEMPLATES_DIR <- here("templates")
stopifnot("the templates directory must exist" = fs::is_dir(TEMPLATES_DIR))

DEFAULT_SESSION <- read_yaml(here(TEMPLATES_DIR, "default_session.yaml"))


ui <- fluidPage(
    # Application title
    titlePanel("Shrager Memory Game: Teacher App"),

    sidebarLayout(
        sidebarPanel(
            uiOutput("sessionsList"),
            actionButton("createSession", "Create a new session", class = "btn-success")
        ),
        mainPanel(
            conditionalPanel("input.sessionsSelect",
                actionButton("deleteSession", "Delete this session", class = "btn-danger", style = "float: right"),
                h1(textOutput("activeSessionTitle")),
                uiOutput("activeSessionContent")
            )
        )
    )
)

server <- function(input, output) {
    state <- reactiveValues(
        sess = NULL,
        available_sessions = character()
    )

    updateAvailSessions <- function() {
        session_dirs <- fs::dir_ls(here(SESS_DIR), type = "directory")
        session_dates <- sapply(as.character(session_dirs), function(d) {
            read_yaml(here(d, "session.yaml"))$date
        }, USE.NAMES = FALSE)
        sortindices <- order(session_dates)
        session_ids <- basename(session_dirs)[sortindices]
        session_dates <- session_dates[sortindices]

        session_opts <- session_ids
        names(session_opts) <- sprintf("%s – %s", session_dates, session_ids)

        state$available_sessions <- session_opts
    }

    sessionDeleteModal <- function(sess_id) {
        bodytext <- sprintf("Do you really want to delete the session %s? All data for this session will be lost.
                            This cannot be undone.", sess_id)

        modalDialog(title = "Delete this session?",
                    bodytext,
                    footer = tagList(
                        modalButton("Cancel"),
                        actionButton("deleteSessionConfirmed", "OK")
                    )
        )
    }

    observeEvent(input$createSession, {
        sess_id <- NULL
        while (is.null(sess_id) || fs::dir_exists(here(SESS_DIR, sess_id))) {
            sess_id <- stri_rand_strings(1, SESS_ID_CODE_LENGTH)
        }

        fs::dir_create(here(SESS_DIR, sess_id))

        state$sess <- c(
            list(
                sess_id = sess_id,
                stage = "start",
                date = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
            ),
            DEFAULT_SESSION
        )

        save_sess_config(state$sess)
    })

    observeEvent(input$sessionsSelect, {
        req(input$sessionsSelect)
        state$sess <- load_sess_config(input$sessionsSelect)
    })

    observeEvent(input$deleteSession, {
        req(state$sess)
        showModal(sessionDeleteModal(state$sess$sess_id))
    })

    observeEvent(input$deleteSessionConfirmed, {
        req(state$sess)

        # directory deletion is a very sensitive operation; perform some checks beforehand
        stopifnot("session ID must be valid" = validate_sess_id(state$sess$sess_id))
        sess_dir <- here(SESS_DIR, state$sess$sess_id)

        # remove the session directory
        fs::dir_delete(sess_dir)

        updateAvailSessions()

        removeModal()
    })

    output$sessionsList <- renderUI({
        updateAvailSessions()

        selectInput("sessionsSelect", "Load session:", state$available_sessions, selected = state$sess$sess_id)
    })

    output$activeSessionTitle <- renderText({
        req(state$sess)

        sprintf("Session %s", state$sess$sess_id)
    })

    output$activeSessionContent <- renderUI({
        req(state$sess)

        qa_list <- lapply(state$sess$questions, function(item) {
            tags$li(item$q, tags$ul(lapply(item$a, tags$li)))
        })

        survey_list <- lapply(state$sess$survey, function(item) {
            tags$li(sprintf("%s: %s", item$label, item$text))
        })

        list(
            tags$h2("General information"),
            tags$ul(
                tags$li(sprintf("Date: %s", state$sess$date)),
                tags$li(sprintf("Language: %s", state$sess$language)),
                tags$li(sprintf("Current stage: %s", state$sess$stage))
            ),
            tags$h2("Sentences"),
            tags$ol(lapply(state$sess$sentences, tags$li)),
            tags$h2("Further information"),
            tags$div(
                tags$h3("Questions and answers"),
                tags$ol(qa_list),
                tags$h3("Survey"),
                tags$ol(survey_list),
                id = "session_info_container"
            )
        )
    })
}

# Run the application
shinyApp(ui = ui, server = server)
