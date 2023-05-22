library(yaml)


SESS_ID_CODE_LENGTH <- 8
USER_ID_CODE_LENGTH <- 12
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
