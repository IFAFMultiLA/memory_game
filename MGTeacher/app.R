# Shrager Memory Game – teacher app.
#
# Shiny app for creating and managing the experiments.
#
# Author: Markus Konrad <markus.konrad@htw-berlin.de>

library(shiny)
library(here)
library(yaml)
library(stringi)
library(qrcode)

# include common functions
source(here('..', 'common.R'))

TEMPLATES_DIR <- here("templates")
stopifnot("the templates directory must exist" = fs::is_dir(TEMPLATES_DIR))

# load available experiment session templates: yaml files in "templates" directory
available_sessions_templates <- fs::path_file(fs::dir_ls(here(TEMPLATES_DIR), type = "file", glob = "*.yaml"))

# UI definitions
ui <- fluidPage(
    shinyjs::useShinyjs(),
    tags$script(src = "custom.js"),    # custom JS
    titlePanel("Shrager Memory Game: Teacher App"),

    sidebarLayout(
        # side panel: select existing session or create a new session from a template
        sidebarPanel(
            uiOutput("sessionsList"),
            selectInput("createSessionTemplate", "Create a new session from template:", available_sessions_templates,
                        selected = "default_session_en.yaml"),
            actionButton("createSession", "", class = "btn-success", icon = icon("plus"))
        ),
        # main panel: information about selected session and session controls
        mainPanel(
            conditionalPanel("input.sessionsSelect",
                div(
                    downloadButton("downloadSessionData", "Download collected data", class = "btn-info"),
                    actionButton("deleteSession", "Delete this session", class = "btn-danger", icon = icon("trash")),
                    style = "float: right"),
                h1(textOutput("activeSessionTitle")),
                uiOutput("activeSessionMainInfo"),
                plotOutput("activeSessionQRCode"),
                actionButton("toggleSessContentDisplay", "Toggle session information display", icon = icon("cog")),
                shinyjs::hidden(uiOutput("activeSessionContent"))
            )
        )
    )
)

# server definitions
server <- function(input, output, session) {
    # current app state
    state <- reactiveValues(
        sess = NULL,                         # selected session ID
        available_sessions = character()     # available sessions
    )

    # helper function that returns TRUE when the currently selected session includes a survey, otherwise FALSE
    hasSurvey <- function() {
        state$sess$config$survey && !is.null(state$sess$survey) && length(state$sess$survey) > 0
    }

    # helper function that returns the URL to the participant app for the selected session
    appURL <- function() {
        paste0(Sys.getenv("PARTICIPANT_APP_BASEURL"), "?sess_id=", state$sess$sess_id)
    }

    # helper function to update the vector of available sessions
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

    # helper function to display a modal asking to delete the experiment session `sess_id`
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

    # actions to perform when creating a new session
    observeEvent(input$createSession, {
        # check that we have a valid session template
        req(input$createSessionTemplate)
        req(endsWith(input$createSessionTemplate, ".yaml"))
        req(grepl("^[A-Za-z0-9_-]+$", substring(input$createSessionTemplate, 1, nchar(input$createSessionTemplate)-5)))

        # generate a random session ID and make sure it doesn't already exist
        sess_id <- NULL
        while (is.null(sess_id) || fs::dir_exists(here(SESS_DIR, sess_id))) {
            sess_id <- stri_rand_strings(1, SESS_ID_CODE_LENGTH)
        }

        # create a directory for that session
        fs::dir_create(here(SESS_DIR, sess_id))
        now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

        # load the session configuration template
        sess_template_data <- read_yaml(here(TEMPLATES_DIR, input$createSessionTemplate))

        # create the session configuration
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
            sess_template_data
        )

        # save the session configuration to the session directory
        save_sess_config(state$sess)

        # announce the current session stage
        session$sendCustomMessage("session_advanced", state$sess$stage)
    })

    # actions to perform when a session has been selected
    observeEvent(input$sessionsSelect, {
        req(input$sessionsSelect)

        # load the session configuration
        state$sess <- load_sess_config(input$sessionsSelect)

        # announce the current session stage
        session$sendCustomMessage("session_advanced", state$sess$stage)
    })

    # actions to perform when trying to delete a session
    observeEvent(input$deleteSession, {
        req(state$sess)
        showModal(sessionDeleteModal(state$sess$sess_id))
    })

    # actions to perform when deleting a session was confirmed
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

    # actions to perform when advancing to the next stage of the current session
    observeEvent(input$advanceSession, {
        req(state$sess)

        # get current stage index
        cur_stage_index <- which(state$sess$stage == STAGES)
        stopifnot(length(cur_stage_index) == 1)

        if (cur_stage_index < length(STAGES)) {   # make sure the stage index is valid
            if (!hasSurvey() && state$sess$stage == "questions") {
                incr <- 2  # skip survey
            } else {
                incr <- 1
            }

            # move to the next stage, note the time and update the data on disk
            state$sess$stage <- STAGES[cur_stage_index + incr]
            state$sess$stage_timestamps[[state$sess$stage]] <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
            save_sess_config(state$sess)
            session$sendCustomMessage("session_advanced", state$sess$stage)
        }
    })

    # actions to perform when showing the initially hidden session information
    observeEvent(input$toggleSessContentDisplay, {
        req(state$sess)

        shinyjs::toggle("activeSessionContent")
    })

    # dynamic list of sessions as "select input element"
    output$sessionsList <- renderUI({
        updateAvailSessions()

        selectInput("sessionsSelect", "Load existing session:", state$available_sessions, selected = state$sess$sess_id)
    })

    # session title
    output$activeSessionTitle <- renderText({
        req(state$sess)

        sprintf("Session %s", state$sess$sess_id)
    })

    # main session information display
    output$activeSessionMainInfo <- renderUI({
        req(state$sess)

        # label for advancing to the next stage of the session
        next_action_label <- switch (state$sess$stage,
            start = "Show directions",
            directions = "Show questions",
            questions = ifelse(hasSurvey(), "Show survey", "Show results"),
            survey = "Show results",
            results = "End",
            end = "Session has ended"
        )

        # set up the "advance to next stage" button
        adv_sess_btn_args <- list(inputId = "advanceSession", label = next_action_label, class = "btn-success",
                                  icon = icon(ifelse(state$sess$stage == "end", "step-forward", "forward")),
                                  style = "margin: 0 auto 15px auto; display: block")

        if (state$sess$stage == "end") {
            adv_sess_btn_args$disabled <- "disabled"
        }

        base_app_url <- Sys.getenv("PARTICIPANT_APP_BASEURL")

        if (base_app_url == "") {
            participant_app_url <- div(
                p("environment variable ", tags$code("PARTICIPANT_APP_BASEURL"), " not set – can't show
                   participant app URL or generate QR code"),
                class = "alert alert-danger"
            )
        } else {
            participant_app_url <- div(
                p("Share this URL or use the QR code below: ", tags$code(appURL())),
                class = "alert alert-info"
            )
        }

        # finally create the output HTML elements with all information
        div(
            div(p("Current stage: ", span(state$sess$stage, id = "current_stage")),
                class = "alert alert-info", style = "text-align: center"),
            div(do.call(actionButton, adv_sess_btn_args), style = "width: 100%"),
            div(div(state$sess$stage_timestamps[[state$sess$stage]], id = "stage_timestamp", style = "display: none"),
                p("Time elapsed in current game stage:", id = "stage_timer_intro"),
                p("", id = "stage_timer", style = "text-align: center; font-weight: bold"),
                p(sprintf("Creation date: %s | Language: %s", state$sess$date, state$sess$language)),
                class = "alert alert-warning"),
            participant_app_url
        )
    })

    # plot for the QR code to the participant app
    output$activeSessionQRCode <- renderPlot({
        req(Sys.getenv("PARTICIPANT_APP_BASEURL"))

        plot(qr_code(appURL()))
    })

    # full session content display
    output$activeSessionContent <- renderUI({
        req(state$sess)

        qa_list <- lapply(state$sess$questions, function(item) {
            tags$li(item$q, tags$ul(lapply(item$a, tags$li)))
        })

        survey_list <- lapply(state$sess$survey, function(item) {
            tags$li(sprintf("%s: %s", item$label, item$text))
        })

        config_list <- lapply(names(state$sess$config), function(k) {
            tags$li(sprintf("%s: %s", k, state$sess$config[[k]]))
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
                tags$h3("Configuration"),
                tags$ul(config_list),
                id = "session_info_container"
            )
        )
    })

    # download handler for session data
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
