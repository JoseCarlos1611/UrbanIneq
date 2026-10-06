# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero
# Optimized numerical-data helpers. Existing function names/signatures remain
# compatible; an optional in-memory INE bundle avoids repeated XLSX parsing.

cityname_match <- function(name, income_file, ine_bundle = NULL) {
    alldata <- if (!is.null(ine_bundle) && !is.null(ine_bundle$city_names)) {
        ine_bundle$city_names
    } else {
        read_excel(path = income_file,
                   range = "A8:A55442",
                   .name_repair = "unique_quiet")[[1]]
    }
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
    for (i in 1:length(city.options)) cat(paste0(i, ":"), city.options[i], "\n")
    if (interactive()) {
        city.choice <- as.numeric(readline())
        if (city.choice == "") return(NULL)
    } else {
        city.choice <- as.numeric(scan("stdin", character(), n = 1, quiet = TRUE))
    }
    if (!(city.choice %in% city.seq) && city.choice != 0) return(NULL)
    matched.pretty <- which(alldata.pretty == city.options[city.choice])
    if (length(matched.pretty) == 0) return(NULL)
    strsplit(alldata[matched.pretty], " ")[[1]][1]
}

ct.clean <- function(ct_column) {
    ct_digits <- gregexpr(pattern = "\\d+", text = ct_column)
    vapply(seq_along(ct_digits), function(i) {
        str_init <- ct_digits[[i]][1]
        str_end <- str_init + attr(ct_digits[[i]], "match.length")
        substr(ct_column[i], start = str_init, stop = str_end)
    }, character(1))
}

perc_fix <- function(column) {
    as.numeric(gsub("\\%", "", gsub(",", ".", as.matrix(column))))
}

ct.get_census_info <- function(ct_code, headers_list, filename, ine_bundle = NULL) {
    if (!is.character(ct_code)) stop("ct_code must be a string")
    if (nchar(ct_code) != 5) stop("ct_code must be of length 5")

    alldata <- if (!is.null(ine_bundle) && !is.null(ine_bundle$census_data)) {
        ine_bundle$census_data
    } else {
        read_excel(path = filename, skip = 10)
    }

    allct <- ct.clean(alldata$Sección)
    ct_which <- which(substr(allct, 1, 5) == ct_code)
    ct_data <- alldata[ct_which, , drop = FALSE]
    cleaned_codes <- ct.clean(ct_data$Sección)
    total <- as.matrix(ct_data$Personas)
    perc_cols <- grep("porcentaje", headers_list$orig, ignore.case = TRUE)
    pp_data <- data.frame(ct_code = cleaned_codes, total = total)

    for (col_idx in perc_cols) {
        old_name <- headers_list$orig[col_idx]
        new_name <- headers_list$repl[col_idx]
        pp_data[[new_name]] <- perc_fix(ct_data[[old_name]])
    }
    pp_data
}

ct.get_income <- function(ct_code, filename, ine_bundle = NULL) {
    skip_rows <- 6
    if (!is.character(ct_code)) stop("ct_code must be a string")
    if (nchar(ct_code) != 5) stop("ct_code must be of length 5")

    if (!is.null(ine_bundle) && !is.null(ine_bundle$income_years) && !is.null(ine_bundle$income_data)) {
        income.years <- ine_bundle$income_years
        income.data <- ine_bundle$income_data
    } else {
        income.years <- colnames(read_excel(path = filename,
                                            range = "A8:Z8",
                                            .name_repair = "unique_quiet"))
        income.data <- read_excel(path = filename,
                                  skip = skip_rows,
                                  .name_repair = "unique_quiet")
    }

    income.column <- which(substr(income.years, 1, 4) == "2021")[1]
    if (is.na(income.column)) stop("Could not find the 2021 income column in INE input")

    all_ct <- as.matrix(income.data[, 1])
    regex_str <- paste0("^", ct_code, "[0-9]{5}")
    local_ct.idx <- grep(regex_str, all_ct)
    local_ct.codes <- as.matrix(substr(all_ct[local_ct.idx, ], 1, 10))
    local_ct.income <- as.numeric(as.matrix(income.data[local_ct.idx, income.column]))
    income_df <- data.frame(local_ct.codes, local_ct.income)
    colnames(income_df) <- c("ct_code", "mean_income")
    income_df
}
