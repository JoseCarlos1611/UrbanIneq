# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero

# This file contains helper functions related to the handling of numerical data,
# i.e., everything that has to do with generating X1, ... , X7 variables

# Match a given city name to the income file
cityname_match <- function(name, income_file) {
    alldata <- read_excel(path = income_file,
                          range = "A8:A55442",
                          .name_repair = "unique_quiet")[[1]]
    alldata <- alldata[grep("^[0-9]{5} ", alldata)]
    alldata.norm <- iconv(alldata, from = "UTF-8", to = "ASCII//TRANSLIT")
    alldata.pretty <- substr(alldata, 7, nchar(alldata))
    matched.idx <- grep(name, alldata.norm, ignore.case = TRUE, value = FALSE)
    city.options <- alldata.pretty[matched.idx]
    if (length(city.options) == 0) {
        cat(paste0("No cities matching '", name, "' were found, please try again\n"))
        return(NULL)
    }
    cat("\nChoose between the matched cities (enter 0 to search for another one):\n")
    city.seq <- seq(length(city.options))
    for (i in 1:length(city.options)) {
        cat(paste0(i, ":"), city.options[i], "\n")
    }
    if (interactive()) {
        city.choice <- as.numeric(readline())
        if (city.choice == "") return(NULL)
    } else {
        city.choice <- as.numeric(scan("stdin", character(), n = 1, quiet = TRUE))
    }
    if (!(city.choice %in% city.seq) && city.choice != 0) return(NULL)
    matched.pretty <- which(alldata.pretty == city.options[city.choice])
    if (length(matched.pretty) == 0) return(NULL)
    else {
        city_code <- strsplit(alldata[matched.pretty], " ")[[1]][1]
        return(city_code)
    }
}

# Clean the column containing census tract codes so that
# only the codes remain as a string
ct.clean <- function(ct_column) {
    ct_digits <- gregexpr(pattern = "\\d+",
                          text = ct_column)
    sapply(seq_along(ct_digits), function(i) {
        str_init <- ct_digits[[i]][1]
        str_end <- str_init + attr(ct_digits[[i]], "match.length")
        ct_str <- substr(ct_column[i],
                         start = str_init,
                         stop = str_end)
        return(ct_str)
    })
}

# Retrieves all the information available in the
# specified census file
ct.get_census_info <- function(ct_code, headers_list, filename) {
    if (!is.character(ct_code)) stop("ct_code must be a string")
    if (nchar(ct_code) != 5) stop("ct_code must be of length 5")
    alldata <- read_excel(path = filename, skip = 10)
    allct <- ct.clean(alldata$Sección)
    ct_which <- which(substr(allct, 1, 5) == ct_code)
    ct_data <- alldata[ct_which, ]
    ct_code <- ct.clean(ct_data$Sección)
    total <- as.matrix(ct_data$Personas)
    perc_cols <- grep("porcentaje", headers_list$orig, ignore.case = TRUE)
    pp_data <- data.frame(ct_code = ct_code,
                          total = total)
    for (col_idx in perc_cols) {
        old_name <- headers_list$orig[col_idx]
        new_name <- headers_list$repl[col_idx]
        pp_data[[new_name]] <- perc_fix(ct_data[[old_name]])
    }
    return(pp_data)
}

# Shortcut to convert string columns
# containing percentages to numeric
perc_fix <- function(column) {
    as.numeric(
               gsub("\\%", "",
                    gsub(",", ".", as.matrix(column))))
}

# Get the income (X2) variable for a given census tract
ct.get_income <- function(ct_code, filename) {
    skip_rows <- 6
    if (!is.character(ct_code)) stop("ct_code must be a string")
    if (nchar(ct_code) != 5) stop("ct_code must be of length 5")
    income.years <- colnames(read_excel(path = filename,
                                        range = "A8:Z8",
                                        .name_repair = "unique_quiet"))
    income.column <- which(substr(income.years, 1, 4) == "2021")[1]
    income.data <- read_excel(path = filename,
                              skip = skip_rows,
                              .name_repair = "unique_quiet")
    all_ct <- as.matrix(income.data[, 1])
    regex_str <- paste0("^", ct_code, "[0-9]{5}")
    local_ct.idx <- grep(regex_str, all_ct)
    local_ct.codes <- as.matrix(substr(all_ct[local_ct.idx, ], 1, 10))
    local_ct.income <- as.numeric(as.matrix(income.data[local_ct.idx, income.column]))
    income_df <- data.frame(local_ct.codes, local_ct.income)
    colnames(income_df) <- c("ct_code", "mean_income")
    return(income_df)
}
