# run_dashboard.R
# Script to run the Quarto dashboard with proper error handling

# Load required libraries
library(shiny)
library(DBI)
library(RPostgres)

# Function to establish database connection with error handling
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

# Check if we're just rendering (for quarto) or running interactively
if (interactive() || length(sys.calls()) == 1) {
  # Try to establish connection
 con <- get_con()
  
  # Check if connection was successful
  if (is.null(con)) {
    message("Database connection failed, starting dashboard with mock data")
    
    # Create mock data functions that simulate the database queries
    q_kpi <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        total_news = 100,
        avg_score = 5.5,
        last_published = Sys.time(),
        top_category = "Technology"
      )
    }
    
    q_timeseries <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
        count = sample(10:30, 10)
      )
    }
    
    q_top_categories <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        category = c("Technology", "Politics", "Business", "Science"),
        count = c(30, 25, 20, 15)
      )
    }
    
    q_avg_score_over_time <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        day = seq(as.Date("2023-01-01"), as.Date("2023-01-10"), by = "day"),
        avg_score = runif(10, 4, 7)
      )
    }
    
    q_score_distribution <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        score = 1:10,
        count = sample(5:20, 10)
      )
    }
    
    q_heatmap_data <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        day = rep(seq(as.Date("2023-01-01"), as.Date("2023-01-05"), by = "day"), 4),
        category = rep(c("Technology", "Politics", "Business", "Science"), each = 5),
        count = sample(2:10, 20)
      )
    }
    
    q_hourly_distribution <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        hour = 0:23,
        count = sample(5:15, 24)
      )
    }
    
    q_top_news <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      data.frame(
        published_at = seq(as.POSIXct("2023-01-01"), as.POSIXct("2023-01-05"), length.out = 10),
        category = sample(c("Technology", "Politics", "Business", "Science"), 10, replace = TRUE),
        score = runif(10, 1, 10),
        title = paste("Sample news", 1:10),
        link = paste("http://example.com/news", 1:10, sep = "/")
      )
    }
  } else {
    message("Database connection successful, starting dashboard with real data")
    
    # Source the original query functions from the dashboard file
    # We'll define the functions that were in the original setup chunk
    source(textConnection("
    q_kpi <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      # Build SQL query with parameters
      sql <- '
        SELECT 
          COUNT(*) as total_news,
          AVG(score) as avg_score,
          MAX(published_at) as last_published
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- paste(sql, 'AND category = ANY($3)')
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- paste(sql, 'AND (score BETWEEN $4 AND $5 OR score IS NULL)')
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- paste(sql, 'AND score BETWEEN $4 AND $5')
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- paste(sql, 'AND title ILIKE $6')
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      result <- dbGetQuery(con, sql, params)
      
      # Get top category separately
      sql_category <- '
        SELECT category, COUNT(*) as cnt
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2'
      
      params_cat <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql_category <- paste(sql_category, 'AND category = ANY($3)')
        params_cat <- append(params_cat, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql_category <- paste(sql_category, 'AND (score BETWEEN $4 AND $5 OR score IS NULL)')
          params_cat <- append(params_cat, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql_category <- paste(sql_category, 'AND score BETWEEN $4 AND $5')
          params_cat <- append(params_cat, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql_category <- paste(sql_category, 'AND title ILIKE $6')
        params_cat <- append(params_cat, list(paste('%', search_title, '%', sep='')))
      }
      
      sql_category <- paste(sql_category, 'GROUP BY category ORDER BY cnt DESC LIMIT 1')
      
      top_category_result <- dbGetQuery(con, sql_category, params_cat)
      top_category <- ifelse(nrow(top_category_result) > 0, top_category_result$category[1], '')
      
      result$top_category <- top_category
      
      return(result)
    }

    q_timeseries <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          DATE(published_at) as day,
          COUNT(*) as count
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2
        GROUP BY DATE(published_at)
        ORDER BY day'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- gsub('GROUP BY', 'AND category = ANY($3) GROUP BY', sql)
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('GROUP BY', paste('AND (score BETWEEN $4 AND $5 OR score IS NULL) GROUP BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('GROUP BY', paste('AND score BETWEEN $4 AND $5 GROUP BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- gsub('GROUP BY', paste('AND title ILIKE $6 GROUP BY'), sql)
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      result <- dbGetQuery(con, sql, params)
      return(result)
    }

    q_top_categories <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          category,
          COUNT(*) as count
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2
          AND category IS NOT NULL
        GROUP BY category
        ORDER BY count DESC
        LIMIT 10'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- gsub('AND category IS NOT NULL', 'AND category = ANY($3)', sql)
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('LIMIT', paste('AND (score BETWEEN $4 AND $5 OR score IS NULL) LIMIT'), sql)
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('LIMIT', paste('AND score BETWEEN $4 AND $5 LIMIT'), sql)
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- gsub('LIMIT', paste('AND title ILIKE $6 LIMIT'), sql)
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      result <- dbGetQuery(con, sql, params)
      return(result)
    }

    q_avg_score_over_time <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          DATE(published_at) as day,
          AVG(score) as avg_score
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2
          AND score IS NOT NULL
        GROUP BY DATE(published_at)
        ORDER BY day'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- gsub('AND score IS NOT NULL', 'AND category = ANY($3) AND score IS NOT NULL', sql)
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('ORDER BY', paste('AND (score BETWEEN $4 AND $5 OR score IS NULL) ORDER BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('ORDER BY', paste('AND score BETWEEN $4 AND $5 ORDER BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- gsub('ORDER BY', paste('AND title ILIKE $6 ORDER BY'), sql)
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      result <- dbGetQuery(con, sql, params)
      return(result)
    }

    q_score_distribution <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          score,
          COUNT(*) as count
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- paste(sql, 'AND category = ANY($3)')
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- paste(sql, 'AND (score BETWEEN $4 AND $5 OR score IS NULL)')
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- paste(sql, 'AND score BETWEEN $4 AND $5')
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- paste(sql, 'AND title ILIKE $6')
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      sql <- paste(sql, 'GROUP BY score ORDER BY score')
      
      result <- dbGetQuery(con, sql, params)
      return(result)
    }

    q_heatmap_data <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          DATE(published_at) as day,
          category,
          COUNT(*) as count
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2
          AND category IS NOT NULL
        GROUP BY DATE(published_at), category
        ORDER BY day, category'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- gsub('AND category IS NOT NULL', 'AND category = ANY($3)', sql)
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('GROUP BY', paste('AND (score BETWEEN $4 AND $5 OR score IS NULL) GROUP BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('GROUP BY', paste('AND score BETWEEN $4 AND $5 GROUP BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- gsub('GROUP BY', paste('AND title ILIKE $6 GROUP BY'), sql)
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      result <- dbGetQuery(con, sql, params)
      return(result)
    }

    q_hourly_distribution <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          EXTRACT(HOUR FROM published_at) as hour,
          COUNT(*) as count
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2
        GROUP BY EXTRACT(HOUR FROM published_at)
        ORDER BY hour'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- gsub('GROUP BY', 'AND category = ANY($3) GROUP BY', sql)
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('GROUP BY', paste('AND (score BETWEEN $4 AND $5 OR score IS NULL) GROUP BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- gsub('GROUP BY', paste('AND score BETWEEN $4 AND $5 GROUP BY'), sql)
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- gsub('GROUP BY', paste('AND title ILIKE $6 GROUP BY'), sql)
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      result <- dbGetQuery(con, sql, params)
      # Ensure all hours 0-23 are represented
      all_hours <- data.frame(hour = 0:23)
      result <- merge(all_hours, result, by = 'hour', all.x = TRUE)
      result$count[is.na(result$count)] <- 0
      return(result)
    }

    q_top_news <- function(con, date_from, date_to, categories, include_null_score, score_min, score_max, search_title) {
      sql <- '
        SELECT 
          published_at,
          category,
          score,
          title,
          link
        FROM news_analysis
        WHERE published_at >= $1 AND published_at < $2'
      
      params <- list(date_from, date_to)
      
      if(length(categories) > 0 && !is.null(categories) && categories[1] != '') {
        sql <- paste(sql, 'AND category = ANY($3)')
        params <- append(params, list(categories))
      }
      
      if(include_null_score) {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- paste(sql, 'AND (score BETWEEN $4 AND $5 OR score IS NULL)')
          params <- append(params, list(score_min, score_max))
        }
      } else {
        if(!is.null(score_min) && !is.null(score_max)) {
          sql <- paste(sql, 'AND score BETWEEN $4 AND $5')
          params <- append(params, list(score_min, score_max))
        }
      }
      
      if(search_title != '') {
        sql <- paste(sql, 'AND title ILIKE $6')
        params <- append(params, list(paste('%', search_title, '%', sep='')))
      }
      
      sql <- paste(sql, 'ORDER BY score DESC, published_at DESC LIMIT 200')
      
      result <- dbGetQuery(con, sql, params)
      return(result)
    }
    "))
  }
  
  # Run the Shiny app (the actual dashboard code would go here)
  # For now, we'll just run a simple app to verify the connection works
  ui <- fluidPage(
    titlePanel("News Analytics Dashboard - Connection Test"),
    h3(paste("Database connection:", ifelse(is.null(con), "FAILED", "SUCCESS"))),
    if(!is.null(con)) {
      verbatimTextOutput("db_info")
    }
  )
  
  server <- function(input, output, session) {
    if(!is.null(con)) {
      output$db_info <- renderText({
        paste("Connected to:", paste(DBI::dbGetInfo(con), collapse = ", "))
      })
      
      # Close connection when session ends
      session$onSessionEnded(function() {
        if(dbIsValid(con)) {
          dbDisconnect(con)
        }
      })
    }
 }
  
  shinyApp(ui = ui, server = server, options = list(host = "0.0.0.0", port = 800))
}