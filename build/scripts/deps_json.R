#!/usr/bin/env Rscript

## Write the Bioconductor dependency graph as JSON: one entry per package,
## listing the Bioconductor packages it needs before it can be built.
## CRAN dependencies are left out: r2u provides those.
##
## Usage: Rscript deps_json.R [biocdeps=]<output.json>

args <- commandArgs(trailingOnly = TRUE)
biocdeps <- "biocdeps.json"
for (arg in args) {
    arg <- sub("^--", "", arg)
    if (grepl("=", arg, fixed = TRUE)) {
        key <- sub("=.*$", "", arg)
        val <- sub("^[^=]*=", "", arg)
        if (key %in% c("biocdeps", "out", "output")) biocdeps <- val
    } else {
        biocdeps <- arg
    }
}

.exclude_packages <- function() {
    inst <- installed.packages()
    inst[inst[, "Priority"] %in% "base", "Package"]
}
exclude <- .exclude_packages()
db <- available.packages(repos = BiocManager::repositories())

softpkgs <- available.packages(repos = BiocManager::repositories()["BioCsoft"])[, 1]
annpkgs <- available.packages(repos = BiocManager::repositories()["BioCann"])[, 1]
exppkgs <- available.packages(repos = BiocManager::repositories()["BioCexp"])[, 1]

## An unreachable repository comes back as an empty list rather than an error,
## which would silently produce a graph with most of Bioconductor missing.
if (length(softpkgs) == 0 || length(annpkgs) == 0 || length(exppkgs) == 0)
    stop("empty package list from Bioconductor -- network problem?")

allbiocpkgs <- unique(sort(c(softpkgs, annpkgs, exppkgs)))

pkgdeps <- tools::package_dependencies(
    allbiocpkgs, db = db, recursive = "strong", which = "strong"
)
pkgdeps <- lapply(pkgdeps, function(x) { x[!(x %in% exclude)] })

biocpkgdeps <- c()

for (p in names(pkgdeps)) {
    biocpkgdeps[[p]] <- pkgdeps[[p]][pkgdeps[[p]] %in% allbiocpkgs]
}

## Anything that shows up as a dependency also needs an entry of its own,
## otherwise the build loop can never mark it done.
allappearingbioc <- unique(sort(unlist(biocpkgdeps)))
existingkeys <- names(biocpkgdeps)
toadd <- allappearingbioc[!(allappearingbioc %in% existingkeys)]

while (length(toadd) > 0) {
    for (p in toadd) {
        biocpkgdeps[[p]] <- pkgdeps[[p]][pkgdeps[[p]] %in% allbiocpkgs]
    }

    allappearingbioc <- unique(sort(unlist(biocpkgdeps)))
    existingkeys <- names(biocpkgdeps)
    toadd <- allappearingbioc[!(allappearingbioc %in% existingkeys)]
}

library(jsonlite)
fileConn <- file(biocdeps)
writeLines(prettify(toJSON(biocpkgdeps)), fileConn)
close(fileConn)

cat(sprintf("wrote %s (%d packages)\n", biocdeps, length(biocpkgdeps)))
