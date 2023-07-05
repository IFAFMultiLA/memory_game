library(here)
library(yaml)
library(dplyr)

DATADIR <- here('data')


session_ids <- character()
session_dates <- character()
session_lang <- character()
session_stage <- character()
session_questions_ids <- character()
session_question_indices <- integer()
session_questions <- character()
sessanswers <- NULL

for (sess_dir in fs::dir_ls(DATADIR, type = "directory")) {
    sess_file <- fs::path_join(c(sess_dir, 'session.yaml'))
    if (fs::file_exists(sess_file)) {
        sess <- read_yaml(sess_file)
        session_ids <- append(session_ids, sess$sess_id)
        session_dates <- append(session_dates, sess$date)
        session_lang <- append(session_lang, sess$language)
        session_stage <- append(session_stage, sess$stage)
        session_questions_ids <- append(session_questions_ids, rep(sess$sess_id, length(sess$questions)))
        session_question_indices <- append(session_question_indices, 1:length(sess$questions))
        session_questions <- append(session_questions, sapply(sess$questions, function(item) item$q))

        for (user_file in fs::dir_ls(sess_dir, type = "file", glob = "*.rds")) {
            if (startsWith(fs::path_file(user_file), 'user_')) {
                u <- readRDS(user_file)

                if (is.null(u$user_answers)) {
                    answers <- NA_character_
                    question_i <- NA_integer_
                } else {
                    answers <- u$user_answers[u$question_indices]
                    question_i <- 1:length(u$question_indices)
                }

                if (is.null(u$user_results)) {
                    correct <- NA
                } else {
                    correct <- u$user_results[u$question_indices]
                }

                useransw <- data.frame(sess_id = sess$sess_id,
                                       user_id = u$user_id,
                                       group = ifelse(is.null(u$group), NA, u$group),
                                       question_i = question_i,
                                       answer = answers,
                                       correct = correct)
                if (is.null(sessanswers)) {
                    sessanswers <- useransw
                } else {
                    sessanswers <- bind_rows(sessanswers, useransw)
                }
            }
        }
    }
}

sessdata <- data.frame(sess_id = session_ids, date = session_dates, language = session_lang, stage = session_stage) |>
    mutate(date = as.POSIXct(gsub("T", " ", date)),
           language = as.factor(language),
           stage = ordered(stage, levels = c("start", "directions", "questions", "survey", "results", "end")))
sessdata

filter(sessdata, language == "de") |>
    arrange(desc(date))

sessquestions <- data.frame(sess_id = session_questions_ids,
                            question_i = session_question_indices,
                            question = session_questions)
sessquestions

sessanswers

wrong_answers <- inner_join(sessquestions, sessanswers, by = c("sess_id", "question_i")) |>
    filter(sess_id == "3nz8T62U", correct == FALSE, answer != "") |>
    select(user_id, question, answer)

write.csv(wrong_answers, "wrong_answers.csv", row.names = FALSE)
