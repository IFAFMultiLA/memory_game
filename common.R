library(yaml)


SESS_ID_CODE_LENGTH <- 8
USER_ID_CODE_LENGTH <- 32
SESS_DIR <- fs::path_abs(here("..", "sessions"))
stopifnot("the sessions directory must exist" = fs::is_dir(SESS_DIR))

STAGES <- c("start", "directions", "questions", "survey", "results", "end")


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

save_sess_config <- function(sess) {
    write_yaml(sess, here(SESS_DIR, sess$sess_id, "session.yaml"))
}

load_sess_config <- function(sess_id) {
    read_yaml(here(SESS_DIR, sess_id, "session.yaml"))
}

survey_labels_for_session <- function(sess) {
    sapply(sess$survey, function(item) {
        item$label
    })
}

data_for_session <- function(sess_id, survey_labels) {
    user_files <- fs::dir_ls(here(SESS_DIR, sess_id), type = "file", regexp = "user_[A-Za-z0-9]+.rds$")
    user_data <- lapply(user_files, readRDS)
    group <- sapply(user_data, function(u) {
        u$group
    })
    n_correct <- sapply(user_data, function(u) {
        sum(u$user_results)
    })

    survey_answers <- t(sapply(user_data, function(u) {
        u$survey_answers
    }))
    colnames(survey_answers) <- paste0("survey_", survey_labels)

    sessdata <- data.frame(group = group, n_correct = n_correct, row.names = 1:length(group))
    cbind(sessdata, survey_answers)
}

