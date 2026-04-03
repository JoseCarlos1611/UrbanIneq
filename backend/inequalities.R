# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero

# Generate the information table that will be used to select
# a sensitive variable
databias <- function(x, y) {
    all_median <- as.numeric(apply(x, 2, median))
    all_data <- data.frame(t(sapply(seq_along(all_median), function(j) {
        jmedian <- all_median[j]
        w.lt <- as.numeric(which(x[, j] < jmedian))
        w.gt <- as.numeric(which(x[, j] >= jmedian))
        ymean.lt <- mean(y[w.lt])
        ymean.gt <- mean(y[w.gt])
        return(c(ymean.lt, ymean.gt))
    })))
# get u(x, y)
    nums <- abs(all_data[, 1] - all_data[, 2])
# get variations
    variations <- (apply(all_data, 1, max) - apply(all_data, 1, min)) /
                   apply(all_data, 1, min) * 100
    variations <- round(variations, 2)
# bind it all together
    all_data <- cbind(all_data, nums, variations, all_median)
    colnames(all_data) <- c("lower", "greater", "u", "variation", "median")
    rownames(all_data) <- colnames(x)
    return(all_data)
}

# Hardcoded variable names (...)
varnames <- list("X1" = "Total population",
                 "X2" = "Income",
                 "X3" = "Underage population",
                 "X4" = "Elderly population",
                 "X5" = "Unemployed population",
                 "X6" = "Foreign population",
                 "X7" = "Loneliness index")

# Create the table from the existing data
bias <- databias(citydata$x, citydata$y)[-1, ]
rownames(bias) <- sapply(1:nrow(bias), function(i) {
                         paste0("x", i, ": ", varnames[i]) })
# Set as default sensitive variable the one with
# the higher variation
biasvar.suggest <- which.max(bias$variation)
biasvar.show_str <- paste("\nThis is the information table for the available",
                          "variables and their variation on the sensitive and",
                          "non-sensitive classes:\n\n")
cat(biasvar.show_str)
print(round(bias, 2))
biasvar.suggest_str <- paste("\nIt is suggested to use",
                             paste0("\"", rownames(bias)[biasvar.suggest],"\""),
                             "as your sensitive variable,",
                             "unless you have already decided on another one\n")
biasvar.choose_str <- paste("Type the variable you want to use as sensitive",
                            "like \"x1\", or hit Enter to use the suggested one: ")
cat(biasvar.suggest_str)

biasvar <- NULL
while (is.null(biasvar)) {
    cat(biasvar.choose_str)
    if (sourced) {
        biasvar.input <- readline()
    } else {
        biasvar.input <- readLines("stdin", n = 1)
    }
    if (biasvar.input == "") biasvar <- biasvar.suggest
    else {
        biasvar.match <- grep(biasvar.input, rownames(bias))
        if (length(biasvar.match) == 0) biasvar <- NULL
        else biasvar <- biasvar.match[1]
    }
}

