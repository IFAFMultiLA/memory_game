library(shiny)
library(here)
library(stringi)

source(here('..', 'common.R'))

TEMPLATES_DIR <- here("templates")
stopifnot("the templates directory must exist" = fs::is_dir(TEMPLATES_DIR))

DEFAULT_SESSION <- read_yaml(here(TEMPLATES_DIR, "default_session.yaml"))


ui <- fluidPage(
    tags$script(src = "custom.js"),    # custom JS
    titlePanel("Shrager Memory Game: Teacher App"),

    sidebarLayout(
        sidebarPanel(
            uiOutput("sessionsList"),
            actionButton("createSession", "Create a new session", class = "btn-success", icon = icon("plus"))
        ),
        mainPanel(
            conditionalPanel("input.sessionsSelect",
                div(
                    downloadButton("downloadSessionData", "Download collected data", class = "btn-info"),
                    actionButton("deleteSession", "Delete this session", class = "btn-danger", icon = icon("trash")),
                    style = "float: right"),
                h1(textOutput("activeSessionTitle")),
                uiOutput("activeSessionMainInfo"),
                uiOutput("activeSessionContent")
            )
        )
    )
)

server <- function(input, output, session) {
    state <- reactiveValues(
        sess = NULL,
        available_sessions = character()
    )

    hasSurvey <- function() {
        !is.null(state$sess$survey) && length(state$sess$survey) > 0
    }

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
                        actionButton("deleteSessionConfirmed", "OK", icon = icon("trash"))
                    )
        )
    }

    observeEvent(input$createSession, {
        sess_id <- NULL
        while (is.null(sess_id) || fs::dir_exists(here(SESS_DIR, sess_id))) {
            sess_id <- stri_rand_strings(1, SESS_ID_CODE_LENGTH)
        }

        fs::dir_create(here(SESS_DIR, sess_id))
        now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

        state$sess <- c(
            list(
                sess_id = sess_id,
                stage = "start",
                date = now,
                stage_timestamps = list(
                    start = now,
                    directions = NULL,
                    questions = NULL,
                    survey = NULL,
                    results = NULL,
                    end = NULL
                )
            ),
            DEFAULT_SESSION
        )

        save_sess_config(state$sess)
        session$sendCustomMessage("session_advanced", state$sess$stage)
    })

    observeEvent(input$sessionsSelect, {
        req(input$sessionsSelect)
        state$sess <- load_sess_config(input$sessionsSelect)
        session$sendCustomMessage("session_advanced", state$sess$stage)
    })

    observeEvent(input$deleteSession, {
        req(state$sess)
        showModal(sessionDeleteModal(state$sess$sess_id))
    })

    observeEvent(input$deleteSessionConfirmed, {
        req(state$sess)

        # directory deletion is a very sensitive operation; perform some checks beforehand
        stopifnot("session ID must be valid" = validate_id(state$sess$sess_id, SESS_ID_CODE_LENGTH,
                                                           expect_session_dir = TRUE))
        sess_dir <- here(SESS_DIR, state$sess$sess_id)

        # remove the session directory
        fs::dir_delete(sess_dir)

        updateAvailSessions()

        removeModal()
    })

    observeEvent(input$advanceSession, {
        req(state$sess)

        cur_stage_index <- which(state$sess$stage == STAGES)
        stopifnot(length(cur_stage_index) == 1)

        if (cur_stage_index < length(STAGES)) {
            if (!hasSurvey() && state$sess$stage == "questions") {
                incr <- 2  # skip survey
            } else {
                incr <- 1
            }

            state$sess$stage <- STAGES[cur_stage_index + incr]
            state$sess$stage_timestamps[[state$sess$stage]] <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
            save_sess_config(state$sess)
            session$sendCustomMessage("session_advanced", state$sess$stage)
        }
    })

    output$sessionsList <- renderUI({
        updateAvailSessions()

        selectInput("sessionsSelect", "Load session:", state$available_sessions, selected = state$sess$sess_id)
    })

    output$activeSessionTitle <- renderText({
        req(state$sess)

        sprintf("Session %s", state$sess$sess_id)
    })

    output$activeSessionMainInfo <- renderUI({
        req(state$sess)

        next_action_label <- switch (state$sess$stage,
            start = "Show directions",
            directions = "Show questions",
            questions = ifelse(hasSurvey(), "Show survey", "Show results"),
            survey = "Show results",
            results = "End",
            end = "Session has ended"
        )

        adv_sess_btn_args <- list(inputId = "advanceSession", label = next_action_label, class = "btn-success",
                                  icon = icon(ifelse(state$sess$stage == "end", "step-forward", "forward")),
                                  style = "margin: 0 auto 15px auto; display: block")

        if (state$sess$stage == "end") {
            adv_sess_btn_args$disabled <- "disabled"
        }

        div(
            div(p("Current stage: ", span(state$sess$stage, id = "current_stage")),
                class = "alert alert-info", style = "text-align: center"),
            div(do.call(actionButton, adv_sess_btn_args), style = "width: 100%"),
            div(div(state$sess$stage_timestamps[[state$sess$stage]], id = "stage_timestamp", style = "display: none"),
                p("Time elapsed in current game stage:", id = "stage_timer_intro"),
                p("", id = "stage_timer", style = "text-align: center; font-weight: bold"),
                p(sprintf("Creation date: %s | Language: %s", state$sess$date, state$sess$language)),
                class = "alert alert-warning")
        )
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

    output$downloadSessionData <- downloadHandler(
        filename = function() {
            req(state$sess)

            paste0("session_", state$sess$sess_id, ".csv")
        },
        content = function(file) {
            req(state$sess)

            sess_data <- data_for_session(state$sess$sess_id, survey_labels_for_session(state$sess))
            write.csv(sess_data, file, row.names = FALSE)
        }
    )
}

# Run the application
shinyApp(ui = ui, server = server)
