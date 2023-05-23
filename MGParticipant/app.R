library(shiny)
library(here)
library(stringi)
library(dplyr)

source(here('..', 'common.R'))

SESSION_REFRESH_TIME <- 1000   # session refresh timer in milliseconds

user_data_path <- function(sess_id, user_id) {
    here(SESS_DIR, sess_id, paste0("user_", user_id, ".rds"))
}

save_user_data <- function(sess_id, user_id, group, user_data, update = FALSE) {
    # print("saving user data")
    # print(user_data)

    if (update) {
        existing_data <- load_user_data(sess_id, user_id)
        if (is.null(existing_data)) {
            existing_data <- list()
        }

        for (k in names(user_data)) {
            existing_data[[k]] <- user_data[[k]]
        }

        existing_data[c('user_id', 'group')] <- NULL

        user_data <- existing_data
    }

    saveRDS(c(list(user_id = user_id, group = group), user_data),
            here(SESS_DIR, sess_id, paste0("user_", user_id, ".rds")))
}

load_user_data <- function(sess_id, user_id) {
    file <- user_data_path(sess_id, user_id)
    # print("loading user data")
    if (fs::file_exists(file)) {
        readRDS(file)
    } else {
        NULL
    }
}

survey_input_int <- function(item) {
    lbl <- paste0("survey_", item$label)

    args <- list(
        id = lbl,
        name = lbl,
        type = "number",
        step = "1"
    )

    if (!is.null(item$input$range)) {
        args$min <- item$range[1]
        args$max <- item$range[2]
    }

    if (!is.null(item$input$required) && item$input$required) {
        args$required <- "required"
    }

    do.call(tags$input, args)
}

survey_input_text <- function(item) {
    lbl <- paste0("survey_", item$label)

    args <- list(
        id = lbl,
        name = lbl,
        type = "text"
    )

    if (!is.null(item$input$required) && item$input$required) {
        args$required <- "required"
    }

    do.call(tags$input, args)
}

ui <- fluidPage(
    tags$script(src = "js.cookie.min.js"),    # cookie JS library
    tags$script(src = "custom.js"),    # custom JS
    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),   # custom CSS
    # titlePanel("Shrager Memory Game: Participant App"),
    verticalLayout(
        uiOutput("mainContent")
    )
)

server <- function(input, output, session) {
    state <- reactiveValues(
        user_id = NULL,
        sess_id = NULL,
        sess = NULL,
        group = NULL,
        sess_id_was_set = FALSE,
        group_was_set = FALSE,
        question_indices = NULL,
        user_results = NULL,
        user_answers = NULL,
        survey_answers = NULL
    )

    hasSurvey <- function() {
        state$sess$config$survey && !is.null(state$sess$survey) && length(state$sess$survey) > 0
    }

    observe({
        params <- getQueryString()
        sess_id <- params$sess_id

        if (is.null(sess_id) || !validate_id(sess_id, SESS_ID_CODE_LENGTH, expect_session_dir = TRUE)) {
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

    observeEvent(input$user_id, {
        print(paste("got user_id via JS:", input$user_id))

        if (input$user_id == "unassigned") {
            user_id <- NULL
            while (is.null(user_id) || fs::file_exists(here(SESS_DIR, state$sess_id, paste0(user_id, ".rds")))) {
                user_id <- stri_rand_strings(1, USER_ID_CODE_LENGTH)
            }

            isolate(state$user_id <- user_id)
            session$sendCustomMessage("set_user_id", state$user_id);
        } else if (validate_id(input$user_id, USER_ID_CODE_LENGTH)) {
            user_id <- input$user_id
        } else {
            user_id <- NULL
        }

        # save empty user data just to claim the ID
        if (!is.null(user_id) && !fs::file_exists(user_data_path(state$sess_id, user_id))) {
            save_user_data(state$sess_id, user_id, state$group, list(user_results = NULL, user_answers = NULL))
        }

        print(paste("setting user ID to", user_id))
        state$user_id <- user_id
    })

    observeEvent(input$group, {
        print(paste("got group via JS:", input$group))
        isolate(state$group <- input$group)   # doesn't trigger update
        state$group_was_set <- TRUE    # triggers update
    })

    observeEvent(input$submit_answers, {
        req(state$sess)
        #req(state$sess$stage == "questions")
        req(state$user_id)
        req(is.null(state$user_results) && is.null(state$user_answers))

        # check answers
        user_answers <- character(length(state$sess$questions))
        state$user_results <- sapply(seq_along(state$sess$questions), function(i) {
            solutions <- state$sess$questions[[i]]$a
            user_answer <- trimws(input[[sprintf("answer_%s", i)]])
            user_answers[i] <<- user_answer

            if (nchar(user_answer) > 0) {
                regex_solutions <- startsWith(solutions, "^")

                correct <- FALSE

                if (sum(regex_solutions) > 0) {
                    # apply regex based solution matching
                    correct <- correct || any(sapply(solutions[regex_solutions], grepl, user_answer,
                                                     ignore.case = TRUE))
                }

                if (sum(!regex_solutions) > 0) {
                    # apply non-regex based solution matching
                    correct <- correct || any(tolower(user_answer) == tolower(solutions[!regex_solutions]))
                }

                correct
            } else {
                # empty answers are always wrong
                FALSE
            }
        })

        # save user data for this session and user ID
        state$user_answers <- user_answers
        save_user_data(state$sess_id, state$user_id, state$group,
                       list(
                           question_indices = state$question_indices,
                           user_results = state$user_results,
                           user_answers = state$user_answers
                       )
        )
    })

    observeEvent(input$submit_survey, {
        req(state$sess)
        #req(state$sess$stage == "survey")
        req(state$user_id)
        req(is.null(state$survey_answers))

        survey_answers <- sapply(state$sess$survey, function(item) {
            as.character(input[[paste0("survey_", item$label)]])
        })

        # save survey data for this session and user ID
        state$survey_answers <- survey_answers
        save_user_data(state$sess_id, state$user_id, state$group, list(survey_answers = state$survey_answers),
                       update = TRUE)
    })

    display_start <- function() {
        div(state$sess$messages$not_started, class = "alert alert-info", style = "text-align: center")
    }

    display_directions <- function() {
        msg_key <- paste0("directions_", state$group)
        directions <- state$sess$messages[[msg_key]]
        div(HTML(directions))
    }

    display_questions <- function() {
        user_data <- load_user_data(state$sess_id, state$user_id)
        state$user_results <- user_data$user_results
        state$user_answers <- user_data$user_answers
        state$question_indices <- user_data$question_indices

        isolate({
            if (is.null(state$question_indices)) {
                state$question_indices <- seq_along(state$sess$questions)

                if (state$sess$config$randomize_questions) {
                    state$question_indices <- sample(state$question_indices)
                }
            }
        })

        list_items <- lapply(state$question_indices, function(i) {
            item <- state$sess$questions[[i]]

            if (!is.null(state$user_results)) {
                answ <- span(
                    span(ifelse(is.null(state$user_answers), input[[sprintf("answer_%s", i)]], state$user_answers[i]),
                         style = "color: #666666"),
                    icon(ifelse(state$user_results[i], "check", "remove"),
                         style = paste("color:", ifelse(state$user_results[i], "#00AA00", "#AA0000")))
                )
            } else {
                answ <- textInput(inputId = sprintf("answer_%s", i), label = NULL)
            }

            tags$li(
                div(item$q),
                answ
            )
        })

        if (is.null(state$user_results)) {
            bottom_elem <- div(actionButton("submit_answers", state$sess$messages$submit, class = "btn-success"),
                               id = "submit_container")
        } else {
            n_correct <- sum(state$user_results)
            bottom_elem <- p(sprintf(state$sess$messages$results_summary, n_correct),
                             style = "font-weight: bold; text-align: center")
        }

        div(
            tags$ol(list_items, id = "questions"),
            bottom_elem
        )
    }

    display_survey <- function() {
        user_data <- load_user_data(state$sess_id, state$user_id)
        state$survey_answers <- user_data$survey_answers

        if (is.null(state$survey_answers)) {
            survey_items <- lapply(state$sess$survey, function(item) {
                survey_input_fn <- switch (item$input$type,
                    int = survey_input_int,
                    text = survey_input_text
                )

                tags$li(tags$label(item$text, `for` = paste0('survey_', item$label)), survey_input_fn(item))
            })

            div(
                tags$ol(survey_items, id = "survey"),
                div(actionButton("submit_survey", state$sess$messages$submit, class = "btn-success"),
                    id = "submit_container")
            )
        } else {
            div(state$sess$messages$survey_ended, class = "alert alert-info", style = "text-align: center")
        }
    }

    display_results <- function() {
        # get results
        sess_data <- data_for_session(state$sess_id, survey_labels_for_session(state$sess))

        # summarize
        summ_data <- group_by(sess_data, group, .drop = FALSE) |>
            summarise(n = n(),
                      total_correct = sum(n_correct),
                      mean_correct = round(mean(n_correct), 2),
                      sd_correct = round(sd(n_correct), 2))

        # prepare for display
        msgs <- state$sess$messages

        tbl_data <- t(summ_data)
        cols <- tbl_data[1, ]
        col_own_group <- cols == state$group
        cols[col_own_group] <- sprintf(msgs$own_group, state$group)
        cols[!col_own_group] <- sprintf(msgs$other_group, cols[!col_own_group])
        colnames(tbl_data) <- cols
        tbl_data <- tbl_data[-1, ]

        rownames(tbl_data) <- c(msgs$summary_statistics_count, msgs$summary_statistics_total,
                                msgs$summary_statistics_mean, msgs$summary_statistics_std)

        list(
            h1(msgs$summary_statistics),
            p(sprintf(msgs$group_information, state$group)),
            renderTable(tbl_data, rownames = TRUE),
            div(downloadButton("downloadResults", msgs$download_data, class = "btn-info"),
                style = "text-align: center")
        )
    }

    display_end <- function() {
        div(state$sess$messages$end, class = "alert alert-info", style = "text-align: center")
    }

    output$mainContent <- renderUI({
        req(state$sess)

        post_questions_stage <- ifelse(hasSurvey(), "survey", "results")

        if (state$sess$stage == post_questions_stage && is.null(state$user_results)) {
            session$sendCustomMessage("autosubmit", "submit_answers")
        }

        if (hasSurvey() && state$sess$stage == "results" && is.null(state$survey_answers)) {
            session$sendCustomMessage("autosubmit", "submit_survey")
        }

        display_fn <- switch (state$sess$stage,
            start = display_start,
            directions = display_directions,
            questions = display_questions,
            survey = display_survey,
            results = display_results,
            end = display_end
        )

        display_fn()
    })

    output$downloadResults <- downloadHandler(
        filename = function() {
            req(state$sess$stage == "results")
            "results.csv"
        },
        content = function(file) {
            req(state$sess$stage == "results")

            sess_data <- data_for_session(state$sess_id, survey_labels_for_session(state$sess))
            write.csv(sess_data, file, row.names = FALSE)
        }
    )
}

# Run the application
shinyApp(ui = ui, server = server)
