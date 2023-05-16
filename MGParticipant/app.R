library(shiny)
library(here)
library(stringi)

source(here('..', 'common.R'))

SESSION_REFRESH_TIME <- 1000   # session refresh timer in milliseconds

save_user_data <- function(sess_id, user_id, user_data) {
    saveRDS(c(list(user_id = user_id), user_data),
            here(SESS_DIR, sess_id, paste0("user_", user_id, ".rds")))
}

load_user_data <- function(sess_id, user_id) {
    file <- here(SESS_DIR, sess_id, paste0("user_", user_id, ".rds"))
    if (fs::file_exists(file)) {
        readRDS(file)
    } else {
        NULL
    }
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
        user_results = NULL
    )

    observe({
        params <- getQueryString()
        sess_id <- params$sess_id

        if (is.null(sess_id) || !validate_id(sess_id, SESS_ID_CODE_LENGTH)) {
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

            # save empty user data just to claim the ID
            save_user_data(state$sess_id, user_id, list(user_results = NULL))
            isolate(state$user_id <- user_id)
            session$sendCustomMessage("set_user_id", state$user_id);
        } else if (validate_id(input$user_id, USER_ID_CODE_LENGTH)) {
            user_id <- input$user_id
        } else {
            user_id <- NULL
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
        req(state$sess$stage == "questions")
        req(state$user_id)
        req(is.null(state$user_results))

        # check answers
        user_answers <- character(length(state$sess$questions))
        state$user_results <- sapply(1:length(state$sess$questions), function(i) {
            solutions <- state$sess$questions[[i]]$a
            user_answer <- trimws(input[[sprintf("answer_%s", i)]])
            user_answers[i] <- user_answer

            if (nchar(user_answer) > 0) {
                regex_solutions <- startsWith(solutions, "^")

                correct <- FALSE

                if (sum(regex_solutions) > 0) {
                    # apply regex based solution matching
                    correct <- correct || any(sapply(solutions[regex_solutions], grepl, user_answer, ignore.case = TRUE))
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

        save_user_data(state$sess_id, state$user_id,
            list(
               user_results = state$user_results,
               user_answers = user_answers
            )
        )
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
        user_answers <- user_data$user_answers

        list_items <- lapply(1:length(state$sess$questions), function(i) {
            item <- state$sess$questions[[i]]

            if (!is.null(state$user_results)) {
                answ <- span(
                    span(ifelse(is.null(user_answers), input[[sprintf("answer_%s", i)]], user_answers[i]),
                         style = "color: #666666"),
                    ifelse(state$user_results[i], "✅",  "❌")
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
            bottom_elem <- div(actionButton("submit_answers", "Submit answers", class = "btn-success"),
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

    display_results <- function() {

    }

    display_end <- function() {
        div(state$sess$messages$end, class = "alert alert-info", style = "text-align: center")
    }

    output$mainContent <- renderUI({
        req(state$sess)

        display_fn <- switch (state$sess$stage,
            start = display_start,
            directions = display_directions,
            questions = display_questions,
            results = display_results,
            end = display_end
        )

        display_fn()
    })
}

# Run the application
shinyApp(ui = ui, server = server)
