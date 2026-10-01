# Stage B: refit the C1 OS cascade after removing duplicate study 401.
# Stale c1_os fits were deleted; each script skips fits that still exist.

keys <- c("c1_os_m1", "c1_os_m2")
source("scripts/refit-random-slope.R")
keys <- "c1_os_m1"
source("scripts/refit-fixed-intercept.R")
source("scripts/refit-donor-confounding.R")
source("scripts/refit-m1-on-m2-subset.R")
source("scripts/refit-comparator-backbone.R")
cat("stage B done\n")
