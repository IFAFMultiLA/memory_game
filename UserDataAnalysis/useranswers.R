library(here)
library(yaml)
library(dplyr)
library(lubridate)

DATADIR <- here('data')
OUTPUTDIR <- here('output')

# ----- read in and parse session data -----

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

# ----- create dataframes from the vectors -----

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

# ----- analysis: wrong answers for a specific session -----

sid <- "3nz8T62U"
wrong_answers <- inner_join(sessquestions, sessanswers, by = c("sess_id", "question_i")) |>
    filter(sess_id == sid, correct == FALSE, answer != "") |>
    select(user_id, question, answer)
wrong_answers

write.csv(wrong_answers, fs::path_join(c(OUTPUTDIR, sprintf("wrong_answers_%s.csv", sid))), row.names = FALSE)

# ----- full data for all sessions in stage "questions" or later -----

fulldata <- filter(sessdata, stage >= "questions") |>
    inner_join(sessquestions, by = "sess_id") |>
    inner_join(sessanswers, by = c("sess_id", "question_i"))

write.csv(fulldata, fs::path_join(c(OUTPUTDIR, "fulldata.csv")), row.names = FALSE)

# ----- analysis user counts per session -----

user_counts <- group_by(fulldata, sess_id, language) |>
    distinct(user_id) |>
    count() |>
    arrange(desc(n))
user_counts

write.csv(user_counts, fs::path_join(c(OUTPUTDIR, "user_counts.csv")), row.names = FALSE)

# ----- valid sessions: those with at least 3 participants -----

valid_sessions <- filter(user_counts, n > 3) |> pull(sess_id)
valid_sessions

# ----- valid German language sessions -----

de_data <- filter(fulldata, sess_id %in% valid_sessions, language == "de") |>
    select(question_i, question, group, answer, correct)
de_data

# ----- number and proportion of correct answers per question -----

prop_correct_de_full <- group_by(de_data, question_i, question) |>
    summarize(n = n(), n_correct = sum(correct), prop_correct = sum(correct)/n()) |>
    ungroup() |>
    arrange(prop_correct)
prop_correct_de_full
write.csv(prop_correct_de_full, fs::path_join(c(OUTPUTDIR, "prop_correct_de_full.csv")), row.names = FALSE)

# ----- number and proportion of correct answers per question per treatment/control -----

prop_correct_de_full_by_group <- group_by(de_data, question_i, question, group) |>
    summarize(n = n(), n_correct = sum(correct), prop_correct = sum(correct)/n()) |>
    ungroup() |>
    arrange(group, prop_correct)
prop_correct_de_full_by_group
write.csv(prop_correct_de_full_by_group, fs::path_join(c(OUTPUTDIR, "prop_correct_de_full_by_group.csv")),
          row.names = FALSE)

# ----- German language sessions without empty answers -----

de_data_nomissings <- filter(de_data, answer != "")
de_data_nomissings

# ----- number and proportion of correct answers per question -----

prop_correct_de_nomissings <- group_by(de_data_nomissings, question_i, question) |>
    summarize(n = n(), n_correct = sum(correct), prop_correct = sum(correct)/n()) |>
    ungroup() |>
    arrange(prop_correct)
prop_correct_de_nomissings
write.csv(prop_correct_de_nomissings, fs::path_join(c(OUTPUTDIR, "prop_correct_de_nomissings.csv")), row.names = FALSE)

# ----- number and proportion of correct answers per question per treatment/control -----

prop_correct_de_nomissings_by_group <- group_by(de_data_nomissings, question_i, question, group) |>
    summarize(n = n(), n_correct = sum(correct), prop_correct = sum(correct)/n()) |>
    ungroup() |>
    arrange(group, prop_correct)
prop_correct_de_nomissings_by_group
write.csv(prop_correct_de_nomissings_by_group, fs::path_join(c(OUTPUTDIR, "prop_correct_de_nomissings_by_group.csv")),
          row.names = FALSE)
