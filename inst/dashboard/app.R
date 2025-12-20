# app.R
# Shiny app based on the dashboard.qmd file

library(shiny)
library(DBI)
library(RPostgres)
library(dplyr)
library(lubridate)
library(ggplot2)
library(plotly)
library(DT)
library(glue)
library(bslib)

# Function to establish database connection
get_env_required <- function(name) {
  v <- Sys.getenv(name, unset = "")
 if (!nzchar(v)) stop(sprintf("Missing required env var: %s", name), call. = FALSE)
  v
}

get_con <- function() {
 tryCatch({
    host <- get_env_required("DB_HOST")
    port <- as.integer(get_env_required("DB_PORT"))
    db   <- get_env_required("DB_NAME")
    user <- get_env_required("DB_USER")
    pass <- get_env_required("DB_PASS")
    sslm <- Sys.getenv("PGSSLMODE", unset = "prefer")

    message(sprintf("Connecting to Postgres: host=%s port=%s db=%s user=%s sslmode=%s",
                    host, port, db, user, sslm))

    DBI::dbConnect(
      RPostgres::Postgres(),
      host = host,
      port = port,
      dbname = db,
      user = user,
      password = pass,
      sslmode = sslm
    )
  }, error = function(e) {
    warning("Failed to connect to database: ", e$message)
    return(NULL)
  })
}

# Define query functions (same as in dashboard.qmd but with error handling)
q_kpi <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      total_news = 100,
      avg_score = 5.5,
      last_published = Sys.time(),
      top_category = "Technology"
    ))
  }
  
  # Build SQL query with parameters
  sql <- "
    SELECT 
      COUNT(*) as total_news,
      AVG(score) as avg_score,
      MAX(published_at) as last_published
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- paste(sql, "AND category = ANY($3)")
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- paste(sql, "AND (score BETWEEN $4 AND $5 OR score IS NULL)")
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- paste(sql, "AND score BETWEEN $4 AND $5")
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- paste(sql, "AND title ILIKE $6")
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_kpi query: ", e$message)
    # Return mock data in case of error
    data.frame(
      total_news = 0,
      avg_score = 0,
      last_published = Sys.time(),
      top_category = "N/A"
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      total_news = 0,
      avg_score = 0,
      last_published = Sys.time(),
      top_category = "N/A"
    )
  } else {
    # Get top category separately
    sql_category <- "
      SELECT category, COUNT(*) as cnt
      FROM news_analysis
      WHERE published_at >= $1 AND published_at < $2"
    
    params_cat <- list(date_from, date_to)
    
    if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
      sql_category <- paste(sql_category, "AND category = ANY($3)")
      params_cat <- append(params_cat, list(categories))
    }
    
    if(include_null_score) {
      if(!is.null(score_min) && !is.null(score_max)) {
        sql_category <- paste(sql_category, "AND (score BETWEEN $4 AND $5 OR score IS NULL)")
        params_cat <- append(params_cat, list(score_min, score_max))
      }
    } else {
      if(!is.null(score_min) && !is.null(score_max)) {
        sql_category <- paste(sql_category, "AND score BETWEEN $4 AND $5")
        params_cat <- append(params_cat, list(score_min, score_max))
      }
    }
    
    if(search_title != "") {
      sql_category <- paste(sql_category, "AND title ILIKE $6")
      params_cat <- append(params_cat, list(paste("%", search_title, "%", sep="")))
    }
    
    sql_category <- paste(sql_category, "GROUP BY category ORDER BY cnt DESC LIMIT 1")
    
    top_category_result <- tryCatch({
      dbGetQuery(con, sql_category, params_cat)
    }, error = function(e) {
      data.frame(category = character(0), cnt = integer(0))
    })
    
    top_category <- ifelse(nrow(top_category_result) > 0, top_category_result$category[1], "")
    result$top_category <- top_category
  }
  
  return(result)
}

q_timeseries <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
      count = sample(10:30, 10)
    ))
  }
  
  sql <- "
    SELECT 
      DATE(published_at) as day,
      COUNT(*) as count
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2
    GROUP BY DATE(published_at)
    ORDER BY day"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- gsub("GROUP BY", "AND category = ANY($3) GROUP BY", sql)
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("GROUP BY", paste("AND (score BETWEEN $4 AND $5 OR score IS NULL) GROUP BY"), sql)
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("GROUP BY", paste("AND score BETWEEN $4 AND $5 GROUP BY"), sql)
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- gsub("GROUP BY", paste("AND title ILIKE $6 GROUP BY"), sql)
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_timeseries query: ", e$message)
    # Return mock data in case of error
    data.frame(
      day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
      count = rep(0, 10)
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
      count = rep(0, 10)
    )
  }
  
  return(result)
}

q_top_categories <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      category = c("Technology", "Politics", "Business", "Science"),
      count = c(30, 25, 20, 15)
    ))
  }
  
  sql <- "
    SELECT 
      category,
      COUNT(*) as count
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2
      AND category IS NOT NULL
    GROUP BY category
    ORDER BY count DESC
    LIMIT 10"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- gsub("AND category IS NOT NULL", "AND category = ANY($3)", sql)
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("LIMIT", paste("AND (score BETWEEN $4 AND $5 OR score IS NULL) LIMIT"), sql)
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("LIMIT", paste("AND score BETWEEN $4 AND $5 LIMIT"), sql)
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- gsub("LIMIT", paste("AND title ILIKE $6 LIMIT"), sql)
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_top_categories query: ", e$message)
    # Return mock data in case of error
    data.frame(
      category = character(0),
      count = integer(0)
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      category = character(0),
      count = integer(0)
    )
  }
  
  return(result)
}

q_avg_score_over_time <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
      avg_score = runif(10, 4, 7)
    ))
  }
  
  sql <- "
    SELECT 
      DATE(published_at) as day,
      AVG(score) as avg_score
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2
      AND score IS NOT NULL
    GROUP BY DATE(published_at)
    ORDER BY day"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- gsub("AND score IS NOT NULL", "AND category = ANY($3) AND score IS NOT NULL", sql)
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("ORDER BY", paste("AND (score BETWEEN $4 AND $5 OR score IS NULL) ORDER BY"), sql)
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("ORDER BY", paste("AND score BETWEEN $4 AND $5 ORDER BY"), sql)
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- gsub("ORDER BY", paste("AND title ILIKE $6 ORDER BY"), sql)
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_avg_score_over_time query: ", e$message)
    # Return mock data in case of error
    data.frame(
      day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
      avg_score = rep(0, 10)
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
      avg_score = rep(0, 10)
    )
  }
  
  return(result)
}

q_score_distribution <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      score = 1:10,
      count = sample(5:20, 10)
    ))
  }
  
  sql <- "
    SELECT 
      score,
      COUNT(*) as count
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- paste(sql, "AND category = ANY($3)")
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- paste(sql, "AND (score BETWEEN $4 AND $5 OR score IS NULL)")
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- paste(sql, "AND score BETWEEN $4 AND $5")
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- paste(sql, "AND title ILIKE $6")
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  sql <- paste(sql, "GROUP BY score ORDER BY score")
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_score_distribution query: ", e$message)
    # Return mock data in case of error
    data.frame(
      score = integer(0),
      count = integer(0)
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      score = integer(0),
      count = integer(0)
    )
  }
  
  return(result)
}

q_heatmap_data <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      day = rep(seq(as.Date("2023-01-01"), as.Date("2023-01-05"), by = "day"), 4),
      category = rep(c("Technology", "Politics", "Business", "Science"), each = 5),
      count = sample(2:10, 20)
    ))
  }
  
  sql <- "
    SELECT 
      DATE(published_at) as day,
      category,
      COUNT(*) as count
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2
      AND category IS NOT NULL
    GROUP BY DATE(published_at), category
    ORDER BY day, category"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- gsub("AND category IS NOT NULL", "AND category = ANY($3)", sql)
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("GROUP BY", paste("AND (score BETWEEN $4 AND $5 OR score IS NULL) GROUP BY"), sql)
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- gsub("GROUP BY", paste("AND score BETWEEN $4 AND $5 GROUP BY"), sql)
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- gsub("GROUP BY", paste("AND title ILIKE $6 GROUP BY"), sql)
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_heatmap_data query: ", e$message)
    # Return mock data in case of error
    data.frame(
      day = as.Date(character(0)),
      category = character(0),
      count = integer(0)
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      day = as.Date(character(0)),
      category = character(0),
      count = integer(0)
    )
  }
  
  return(result)
}



q_top_news <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
  if (is.null(con)) {
    # Return mock data if no connection
    return(data.frame(
      published_at = seq(as.POSIXct("2023-01"), as.POSIXct("2023-01-05"), length.out = 10),
      category = sample(c("Technology", "Politics", "Business", "Science"), 10, replace = TRUE),
      score = runif(10, 1, 10),
      title = paste("Sample news", 1:10),
      link = paste("http://example.com/news", 1:10, sep = "/")
    ))
  }
  
  sql <- "
    SELECT 
      published_at,
      category,
      score,
      title,
      link
    FROM news_analysis
    WHERE published_at >= $1 AND published_at < $2"
  
  params <- list(date_from, date_to)
  
  if(length(categories) > 0 && !is.null(categories) && categories[1] != "") {
    sql <- paste(sql, "AND category = ANY($3)")
    params <- append(params, list(categories))
  }
  
  if(include_null_score) {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- paste(sql, "AND (score BETWEEN $4 AND $5 OR score IS NULL)")
      params <- append(params, list(score_min, score_max))
    }
  } else {
    if(!is.null(score_min) && !is.null(score_max)) {
      sql <- paste(sql, "AND score BETWEEN $4 AND $5")
      params <- append(params, list(score_min, score_max))
    }
  }
  
  if(search_title != "") {
    sql <- paste(sql, "AND title ILIKE $6")
    params <- append(params, list(paste("%", search_title, "%", sep="")))
  }
  
  sql <- paste(sql, "ORDER BY score DESC, published_at DESC LIMIT 200")
  
  result <- tryCatch({
    dbGetQuery(con, sql, params)
  }, error = function(e) {
    warning("Error in q_top_news query: ", e$message)
    # Return mock data in case of error
    data.frame(
      published_at = as.POSIXct(character(0)),
      category = character(0),
      score = integer(0),
      title = character(0),
      link = character(0)
    )
  })
  
  if(nrow(result) == 0) {
    result <- data.frame(
      published_at = as.POSIXct(character(0)),
      category = character(0),
      score = integer(0),
      title = character(0),
      link = character(0)
    )
  }
  
  return(result)
}

# Establish connection
con <- get_con()

# UI
ui <- fluidPage(
  theme = bslib::bs_theme(version = 5, primary = "navy"),
  
  # Application title
  titlePanel("News Analytics Dashboard"),
  
  # Sidebar with controls
  sidebarLayout(
    sidebarPanel(
      # Date range filter (default: last 30 days)
      dateRangeInput("date_range",
                     label = "Date Range:",
                     start = Sys.Date() - 30,
                     end = Sys.Date(),
                     max = Sys.Date()),
      
      # Category filter (multi-select)
      uiOutput("category_filter"),
      
      # Score range filter
      sliderInput("score_range",
                  label = "Score Range:",
                  min = 0, max = 10, value = c(0, 10)),
                  
      # Include NULL score checkbox
      checkboxInput("include_null_score", 
                    label = "Include NULL score", 
                    value = TRUE),
                    
      # Search title text input
      textInput("search_title",
                label = "Search in Title:",
                value = "")
    ),
    
    # Show the plots and table
    mainPanel(
      # KPI Cards
      fluidRow(
        column(3,
          wellPanel(
            h4("Total News"),
            verbatimTextOutput("total_news_kpi")
          )
        ),
        column(3,
          wellPanel(
            h4("Avg Score"),
            verbatimTextOutput("avg_score_kpi")
          )
        ),
        column(3,
          wellPanel(
            h4("Top Category"),
            verbatimTextOutput("top_category_kpi")
          )
        ),
        column(3,
          wellPanel(
            h4("Last Published"),
            verbatimTextOutput("last_published_kpi")
          )
        )
      ),
      
      # Charts
      h3("Time Series: News Count by Day"),
      plotlyOutput("time_series_chart"),
      
      fluidRow(
        column(6,
          h3("Top Categories"),
          plotlyOutput("top_categories_chart")
        ),
        column(6,
          h3("Average Score Over Time"),
          plotlyOutput("avg_score_chart")
        )
      ),
      
      fluidRow(
        column(6,
          h3("Score Distribution"),
          plotlyOutput("score_dist_chart")
        ),
        column(6,
          h3("Heatmap: Day vs Category"),
          plotlyOutput("heatmap_chart")
        )
      ),
      
      fluidRow(
        column(6,
          h3("Hourly Distribution"),
          plotlyOutput("hourly_chart")
        ),
        column(6,
          h3("Top News Table"),
          DT::dataTableOutput("top_news_table")
        )
      )
    )
  )
)


      
# Server
server <- function(input, output, session) {
  # Reactive to get unique categories
  observe({
    req(input$date_range[1], input$date_range[2])
    
    sql_categories <- "
      SELECT DISTINCT category 
      FROM news_analysis
      WHERE published_at >= $1 
        AND published_at < $2 
        AND category IS NOT NULL
      ORDER BY category"
    
    categories_data <- tryCatch({
      dbGetQuery(con, sql_categories, 
                 list(input$date_range[1], 
                      input$date_range[2] + 1))
    }, error = function(e) {
      data.frame(category = character(0))
    })
    
    categories_list <- categories_data$category
    
    output$category_filter <- renderUI({
      selectInput("categories", 
                  label = "Categories:",
                  choices = categories_list,
                  selected = categories_list,
                  multiple = TRUE)
    })
  })
  
  # Reactive data for KPIs
  reactive_kpi_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_kpi(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
  })
  
  # Render KPIs
  output$total_news_kpi <- renderText({
    if(nrow(reactive_kpi_data()) > 0) {
      reactive_kpi_data()$total_news
    } else {
      "N/A"
    }
  })
  
  output$avg_score_kpi <- renderText({
    if(nrow(reactive_kpi_data()) > 0) {
      round(reactive_kpi_data()$avg_score, 2)
    } else {
      "N/A"
    }
  })
  
  output$top_category_kpi <- renderText({
    if(nrow(reactive_kpi_data()) > 0) {
      reactive_kpi_data()$top_category
    } else {
      "N/A"
    }
  })
  
  output$last_published_kpi <- renderText({
    if(nrow(reactive_kpi_data()) > 0) {
      format(reactive_kpi_data()$last_published, "%Y-%m-%d %H:%M")
    } else {
      "N/A"
    }
  })
  
  # Reactive data for time series chart
  reactive_timeseries_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_timeseries(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
  })
  
  output$time_series_chart <- renderPlotly({
    if(nrow(reactive_timeseries_data()) == 0) {
      p <- ggplot() + 
        annotate("text", x = 1, y = 1, label = "No data available", size = 8) +
        theme_void()
    } else {
      p <- ggplot(reactive_timeseries_data(), aes(x = day, y = count)) +
        geom_line(color = "steelblue", size = 1) +
        geom_point(color = "steelblue", size = 2) +
        labs(title = "News Count by Day", x = "Date", y = "Count") +
        theme_minimal() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    }
    
    ggplotly(p)
  })
  
  # Reactive data for top categories chart
  reactive_top_categories_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_top_categories(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
 })
  
  output$top_categories_chart <- renderPlotly({
    if(nrow(reactive_top_categories_data()) == 0) {
      p <- ggplot() + 
        annotate("text", x = 1, y = 1, label = "No data available", size = 8) +
        theme_void()
    } else {
      p <- ggplot(reactive_top_categories_data(), aes(x = reorder(category, count), y = count)) +
        geom_bar(stat = "identity", fill = "lightblue") +
        coord_flip() +
        labs(title = "Top 10 Categories by News Count", x = "Category", y = "Count") +
        theme_minimal()
    }
    
    ggplotly(p)
  })
  
  # Reactive data for avg score chart
  reactive_avg_score_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_avg_score_over_time(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
 })
  
  output$avg_score_chart <- renderPlotly({
    if(nrow(reactive_avg_score_data()) == 0) {
      p <- ggplot() + annotate("text", x = 1, y = 1, label = "No data available", size = 8) +
        theme_void()
    } else {
      p <- ggplot(reactive_avg_score_data(), aes(x = day, y = avg_score)) +
        geom_line(color = "orange", size = 1) +
        geom_point(color = "orange", size = 2) +
        labs(title = "Average Score Over Time", x = "Date", y = "Average Score") +
        theme_minimal() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    }
    
  ggplotly(p)
})
  
  # Reactive data for score distribution chart
  reactive_score_dist_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_score_distribution(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
  })
  
  output$score_dist_chart <- renderPlotly({
    if(nrow(reactive_score_dist_data()) == 0) {
      p <- ggplot() + 
        annotate("text", x = 1, y = 1, label = "No data available", size = 8) +
        theme_void()
    } else {
      p <- ggplot(reactive_score_dist_data(), aes(x = as.factor(score), y = count)) +
        geom_bar(stat = "identity", fill = "green") +
        labs(title = "Score Distribution", x = "Score", y = "Count") +
        theme_minimal() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    }
    
    ggplotly(p)
  })
  
  # Reactive data for heatmap chart
  reactive_heatmap_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_heatmap_data(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
  })
  
  output$heatmap_chart <- renderPlotly({
    if(nrow(reactive_heatmap_data()) == 0) {
      p <- plot_ly(type = "heatmap", 
                    z = matrix(0, nrow = 1, ncol = 1),
                    x = c("No Data"), 
                    y = c("Available"))
    } else {
      p <- plot_ly(
        data = reactive_heatmap_data(),
        x = ~day,
        y = ~category,
        z = ~count,
        type = "heatmap",
        colorscale = "Viridis"
      ) %>%
        layout(
          title = "Heatmap: Day vs Category",
          xaxis = list(title = "Day"),
          yaxis = list(title = "Category")
        )
    }
    
    p
  })
  
  # Reactive data for hourly chart
  reactive_hourly_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_hourly_distribution(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
 })
  
  output$hourly_chart <- renderPlotly({
    if(nrow(reactive_hourly_data()) == 0) {
      p <- ggplot() + 
        annotate("text", x = 1, y = 1, label = "No data available", size = 8) +
        theme_void()
    } else {
      p <- ggplot(reactive_hourly_data(), aes(x = as.factor(hour), y = count)) +
        geom_bar(stat = "identity", fill = "purple") +
        labs(title = "Hourly Distribution of News", x = "Hour", y = "Count") +
        theme_minimal()
    }
    
    ggplotly(p)
  })
  
  # Reactive data for top news table
  reactive_top_news_data <- reactive({
    req(input$date_range[1], input$date_range[2])
    
    date_from <- input$date_range[1]
    date_to <- input$date_range[2] + 1
    categories <- input$categories
    include_null_score <- input$include_null_score
    score_min <- input$score_range[1]
    score_max <- input$score_range[2]
    search_title <- input$search_title
    
    q_top_news(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title)
  })
  
  output$top_news_table <- DT::renderDataTable({
    if(nrow(reactive_top_news_data()) == 0) {
      # Return empty table with appropriate columns
      empty_df <- data.frame(
        published_at = as.POSIXct(character(0)),
        category = character(0),
        score = integer(0),
        title = character(0),
        link = character(0)
      )
      return(DT::datatable(empty_df, options = list(pageLength = 10)))
    }
    
    # Format the data for display
    df <- reactive_top_news_data()
    df$published_at <- format(df$published_at, "%Y-%m-%d %H:%M")
    
    # Make the link column clickable
    df$link_html <- sprintf('<a href="%s" target="_blank">Link</a>', df$link)
    
    # Prepare the table with clickable links
    table_data <- df[, c("published_at", "category", "score", "title", "link_html")]
    colnames(table_data)[5] <- "link"
    
    DT::datatable(
      table_data,
      escape = FALSE,  # Allow HTML in the table
      options = list(
        pageLength = 10,
        lengthMenu = list(c(10, 25, 50, -1), c(10, 25, 50, "All"))
      ),
      colnames = c("Published At", "Category", "Score", "Title", "Link")
    )
  })
  
  # Close connection when Shiny session ends
  session$onSessionEnded(function() {
    if(!is.null(con) && dbIsValid(con)) {
      dbDisconnect(con)
    }
  })
}

# Run the application 
shinyApp(ui = ui, server = server)
