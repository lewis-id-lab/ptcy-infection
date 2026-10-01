# Driver: run the remaining confounding analyses in a fresh R process.
# The interactive session's Stan toolchain became unstable after many
# consecutive brm calls ("invalid connection" at compile); these scripts are
# self-contained and resumable (existing fits are skipped).

source("scripts/refit-donor-confounding.R")
source("scripts/refit-cmv-letermovir.R")
source("scripts/refit-comparator-backbone.R")
cat("all confounding analyses done\n")
