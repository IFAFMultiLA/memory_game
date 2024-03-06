# Shrager Memory Game – common functions and variables.
#
# Functions and variables used in both Shiny apps (the participant and the teacher app).
#
# Author: Markus Konrad <markus.konrad@htw-berlin.de>

SESS_ID_CODE_LENGTH <- 8
USER_ID_CODE_LENGTH <- 32
SESS_DIR <- fs::path_abs(here("..", "sessions"))
stopifnot("the sessions directory must exist" = fs::is_dir(SESS_DIR))

STAGES <- c("start", "directions", "questions", "survey", "results", "end")
GROUPS <- c("ctrl", "treat")


# function that validates a single ID `id` for an expected length `expected_length` and optionally checks that there's
# a folder in the session directory with that ID if `expect_session_dir` is TRUE; also checks that the ID only
# consists of alphanumeric characters
validate_id <- function(id, expected_length, expect_session_dir = FALSE) {
    if (length(id) != 1) return(FALSE)
    if (nchar(id) != expected_length) return(FALSE)
    if (!grepl("^[A-Za-z0-9]+$", id)) return(FALSE)

    if (expect_session_dir) {
        sess_dir <- here(SESS_DIR, id)
        if (!fs::is_dir(sess_dir)) return(FALSE)
        if (!fs::file_exists(here(sess_dir, "session.yaml"))) return(FALSE)
    }

    TRUE
}

# save a session configuration (a list object) to the session.yaml file in the respective folder inside the
# "sessions" directory
save_sess_config <- function(sess) {
    write_yaml(sess, here(SESS_DIR, sess$sess_id, "session.yaml"))
}

# load a session configuration (a list object) from the respective session.yaml file
load_sess_config <- function(sess_id) {
    read_yaml(here(SESS_DIR, sess_id, "session.yaml"))
}

# return the labels for the survey of session `sess` as character vector if a survey is defined for that session;
# otherwise return NULL
survey_labels_for_session <- function(sess) {
    if (sess$config$survey) {
        sapply(sess$survey, function(item) {
            item$label
        })
    } else {
        NULL
    }
}

# load all user data for a session `sess_id`; control which survey data to load via `survey_labels`; use function
# `survey_labels_for_session()` to determine all survey labels
data_for_session <- function(sess_id, survey_labels) {
    # load participants data as list
    user_files <- fs::dir_ls(here(SESS_DIR, sess_id), type = "file", regexp = "user_[A-Za-z0-9]+.rds$")
    user_data <- lapply(user_files, function(f) {
        u <- readRDS(f)
        if (is.null(u$user_results) || is.null(u$user_answers)) {
            NULL
        } else {
            u
        }
    })

    # filter user data: take only participants that have submitted answers
    user_data <- user_data[!sapply(user_data, is.null)]

    # no user data – return empty data frame
    if (length(user_data) == 0) {
        return(data.frame(group = factor(levels = GROUPS),
                          n_correct = integer()))
    }

    # user group assignments as char. vector
    group <- sapply(user_data, function(u) {
        u$group
    })

    # num. correct answers as int. vector
    n_correct <- sapply(user_data, function(u) {
        sum(u$user_results)
    })

    # build the resulting data frame
    res <- data.frame(group = group, n_correct = n_correct, row.names = 1:length(group))

    # add survey answers as additional columns if necessary
    if (!is.null(survey_labels)) {
        survey_answers <- sapply(user_data, function(u) {
            ifelse(is.null(u$survey_answers), rep(NA, length(survey_labels)), u$survey_answers)
        })

        if (is.vector(survey_answers)) {  # single survey question
            survey_answers <- t(t(survey_answers))
        } else {  # multiple survey questions
            survey_answers <- t(survey_answers)
        }

        colnames(survey_answers) <- paste0("survey_", survey_labels)

        res <- cbind(res, survey_answers)
    }

    # set group as factor variable and return
    res$group <- factor(res$group, GROUPS)
    res
}

# check if a user provided answer `user_answer` is correct by matching it with the solution patterns defined in the
# question definition `questiondef`
check_answer <- function(questiondef, user_answer) {
    solutions <- questiondef$a
    is_regex <- !is.null(questiondef$regex) && questiondef$regex

    if (nchar(user_answer) > 0) {
        correct <- FALSE

        if (is_regex) {
            # apply regex based solution matching
            correct <- correct || any(sapply(solutions, grepl, user_answer, ignore.case = TRUE))
        } else {
            # apply non-regex based solution matching
            correct <- correct || any(tolower(user_answer) == tolower(solutions))
        }

        correct
    } else {
        # empty answers are always wrong
        FALSE
    }
}
