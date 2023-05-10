library(shiny)
library(here)

source(here('..', 'common.R'))

SESSION_REFRESH_TIME <- 1000   # session refresh timer in milliseconds

ui <- fluidPage(
    titlePanel("Shrager Memory Game: Participant App"),
    sidebarLayout(
        sidebarPanel(),
        mainPanel(
           textOutput("text")
        )
    )
)

server <- function(input, output) {
    output$text <- renderText({
        params <- getQueryString()
        sess_id <- params$sess_id
        if (is.null(sess_id) || !validate_sess_id(sess_id)) {
            showModal(modalDialog("Invalid session ID or session ID not given.", footer = NULL))
        } else {
            print("refreshing session...")
            invalidateLater(SESSION_REFRESH_TIME)

            sess <- load_sess_config(sess_id)

            sess$stage
        }
    })
}

# Run the application
shinyApp(ui = ui, server = server)
