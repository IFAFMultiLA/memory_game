library(yaml)


SESS_ID_CODE_LENGTH <- 8
SESS_DIR <- fs::path_abs(here("..", "sessions"))
stopifnot("the sessions directory must exist" = fs::is_dir(SESS_DIR))


validate_sess_id <- function(sess_id) {
    if (length(sess_id) != 1) return(FALSE)
    if (nchar(sess_id) != SESS_ID_CODE_LENGTH) return(FALSE)
    if (!grepl("^[A-Za-z0-9]+$", sess_id)) return(FALSE)

    sess_dir <- here(SESS_DIR, sess_id)
    if (!fs::is_dir(sess_dir)) return(FALSE)
    if (!fs::file_exists(here(sess_dir, "session.yaml"))) return(FALSE)

    TRUE
}

save_sess_config <- function(sess) {
    write_yaml(sess, here(SESS_DIR, sess$sess_id, "session.yaml"))
}

load_sess_config <- function(sess_id) {
    read_yaml(here(SESS_DIR, sess_id, "session.yaml"))
}
