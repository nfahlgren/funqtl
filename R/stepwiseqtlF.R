#' Stepwise selection for multiple QTL in function valued trait data
#'
#'
#' Extension of the R/qtl function \code{\link[qtl]{stepwiseqtl}}. Performs
#' forward/backward selection to identify a multiple QTL model for function
#' valued trait data, with model choice made via a penalized LOD score, with
#' separate penalties on main effects and interactions.
#'
#'
#' @param cross An object of class \code{"cross"}. See \code{\link[qtl]{read.cross}} for details.
#' @param chr Optional vector indicating the chromosomes to consider in search
#' for QTL.  This should be a vector of character strings referring to
#' chromosomes by name; numeric values are converted to strings.  Refer to
#' chromosomes with a preceding \code{"-"} to have all chromosomes but those
#' considered.  A logical (TRUE/FALSE) vector may also be used.
#' @param pheno.cols Columns in the phenotype matrix to be used as the
#' phenotype.
#' @param usec Which method to use (\code{"slod"} or \code{"mlod"})
#' @param qtl Optional QTL object (of class \code{"qtl"}, as created by \code{\link[qtl]{makeqtl}})
#' to use as a starting point.
#' @param formula Optional formula to define the QTL model to be used as a
#' starting point.
#' @param max.qtl Maximum number of QTL to which forward selection should
#' proceed.
#' @param covar Data frame of additive covariates.
#' @param method Indicates whether to use multiple imputation or Haley-Knott
#' regression.
#' @param incl.markers If FALSE, do calculations only at points on an evenly
#' spaced grid.
#' @param refine.locations If TRUE, use \code{\link{refineqtlF}} to refine the QTL locations
#' after each step of forward and backward selection.
#' @param additive.only If TRUE, allow only additive QTL models; if FALSE,
#' consider also pairwise interactions among QTL.
#' @param penalties Vector of three values indicating the penalty on main
#' effects and heavy and light penalties on interactions.  See the Details
#' below. If missing, default values are used that are based on simulations of
#' backcrosses and intercrosses with genomes modeled after that of the mouse.
#' @param keeptrace If TRUE, keep information on the sequence of models visited
#' through the course of forward and backward selection as an attribute to the
#' output.
#' @param verbose If TRUE, give feedback about progress.  If \code{verbose} is an
#' integer > 1, even more information is printed.
#' @return
#'
#' The output is a representation of the best model, as measured by the
#' penalized LOD score (see Details), among all models visited.  This is QTL
#' object (of class \code{"qtl"}, as produced by \code{\link[qtl]{makeqtl}}), with attributes
#' \code{"formula"}, indicating the model formula, and \code{"pLOD"} indicating the
#' penalized LOD score.
#'
#' If \code{keeptrace=TRUE}, the output will contain an attribute \code{"trace"}
#' containing information on the best model at each step of forward and
#' backward elimination.  This is a list of objects of class \code{"compactqtl"},
#' which is similar to a QTL object (as produced by \code{\link[qtl]{makeqtl}}) but containing
#' just a vector of chromosome IDs and positions for the QTL.  Each will also
#' have attributes \code{"formula"} (containing the model formula) and \code{"pLOD"}
#' (containing the penalized LOD score.
#' @author Il-Youp Kwak, <email: ikwak2@@stat.wisc.edu>
#' @seealso \code{\link{refineqtlF}}, \code{\link{addqtlF}}
#' @export
#' @references Manichaikul, A., Moon, J. Y., Sen, S, Yandell, B. S. and Broman,
#' K. W. (2009) A model selection approach for the identification of
#' quantitative trait loci in experimental crosses, allowing epistasis.
#' _Genetics_, *181*, 1077-1086.
#'
#' Broman, K. W. and Speed, T. P. (2002) A model selection approach for the
#' identification of quantitative trait loci in experimental crosses (with
#' discussion). _J Roy Stat Soc B_ *64*, 641-656, 731-775.
#'
#' Haley, C. S. and Knott, S. A. (1992) A simple regression method for mapping
#' quantitative trait loci in line crosses using flanking markers.  _Heredity_
#' *69*, 315-324.
#'
#' Zeng, Z.-B., Kao, C.-H. and Basten, C. J. (1999) Estimating the genetic
#' architecture of quantitative traits.  _Genetical Research_, *74*, 279-289.
#' @examples
#' data(simspal)
#' \dontshow{simspal <- subset(simspal,chr=c(1,3,4), ind=1:50)}
#' # Genotype probabilities for H-K
#' simspal <- calc.genoprob(simspal, step=0)
#' phe <- 1:nphe(simspal)
#' \dontshow{phe <- 80:82}
#' qtlslod <- stepwiseqtlF(simspal, pheno.cols = phe, max.qtl = 4, usec = "slod",
#'                         method = "hk", penalties = c(2.36, 2.76, 2) )
stepwiseqtlF <- function (cross, chr, pheno.cols, qtl, usec=c("slod","mlod"), formula, max.qtl = 10,
                          covar = NULL, method = c("hk", "imp"),
                          incl.markers = TRUE, refine.locations = TRUE,
                          additive.only = TRUE, penalties,
                          keeptrace = FALSE, verbose = TRUE)
{
  method <- match.arg(method)
  usec <- match.arg(usec)

  if(missing(pheno.cols))
    pheno.cols = 1:nphe(cross)
  
  
  
  if(!all(pheno.cols %in% 1:nphe(cross)))
    stop("pheno.cols should be in a range of 1 to ", nphe(cross))

  pheno <- cross$pheno[,pheno.cols,drop=FALSE]

  if(!additive.only) {
      additive.only <- TRUE
      warning("The package only support additive model.\n")
  }

  
  if(!("cross" %in% class(cross)))
    stop("Input should have class \"cross\".")

  if(!missing(chr))
    cross <- subset(cross, chr)

  # make sure that covar is a data frame
  if(!missing(covar) && !is.data.frame(covar))
    covar <- as.data.frame(covar)

  # check qtl and formula inputs
  if(!missing(qtl)) {
    if (!("qtl" %in% class(qtl)))
      stop("The qtl argument must be an object of class \"qtl\".")
    m <- is.na(match(qtl$chr, names(cross$geno)))
    if (any(m)) {
      wh <- qtl$chr[m]
      if (length(wh) > 1)
        stop("Chromosomes ", paste(wh, collapse = ", "),
             " (in QTL object) not in cross object.")
      else stop("Chromosome ", wh, " (in QTL object) not in cross object.")
    }
    if(missing(formula)) {
      if(!is.null(covar)) {
        if(!is.data.frame(covar)) covar <- as.data.frame(covar)
        formula <- paste("y ~ ", paste(names(covar),
                                       collapse = "+"), "+")
      }
      else formula <- "y ~ "
      formula <- paste(formula, paste(paste("Q", 1:length(qtl$chr),
                                            sep = ""), collapse = "+"))
    }
    else {
      temp <- qtl::checkStepwiseqtlStart(qtl, formula, covar)
      qtl <- temp$qtl
      formula <- temp$formula
    }
    startatnull <- FALSE
  }
  else {
    if (!missing(formula))
      warning("formula ignored if qtl is not provided.")
    startatnull <- TRUE
  }
  if (!startatnull)
    qtl$name <- qtl$altname

  if (method == "imp") {
    if (!("draws" %in% names(cross$geno[[1]]))) {
      if ("prob" %in% names(cross$geno[[1]])) {
        warning("The cross doesn't contain imputations; using method=\"hk\".")
        method <- "hk"
      }
      else stop("You need to first run sim.geno.")
    }
  }
  else {
    if (!("prob" %in% names(cross$geno[[1]]))) {
      if ("draws" %in% names(cross$geno[[1]])) {
        warning("The cross doesn't contain QTL genotype probabilities; using method=\"imp\".")
        method <- "imp"
      }
      else stop("You need to first run calc.genoprob.")
    }
  }
  if (method == "imp")
    qtlmethod <- "draws"
  else qtlmethod <- "prob"
  if (!missing(qtl) && qtl$n.ind != nind(cross)) {
    warning("No. individuals in qtl object doesn't match that in the input cross; re-creating qtl object.")
    if (method == "imp")
      qtl <- makeqtl(cross, qtl$chr, qtl$pos, qtl$name,
                     what = "draws")
    else qtl <- makeqtl(cross, qtl$chr, qtl$pos, qtl$name,
                        what = "prob")
  }
  if (!missing(qtl) && method == "imp" && dim(qtl$geno)[3] !=
      dim(cross$geno[[1]]$draws)[3]) {
    warning("No. imputations in qtl object doesn't match that in the input cross; re-creating qtl object.")
    qtl <- makeqtl(cross, qtl$chr, qtl$pos, qtl$name, what = "draws")
  }
  if (!startatnull) {
    if (method == "imp" && !("geno" %in% names(qtl)))
      stop("The qtl object doesn't contain imputations; re-run makeqtl with what=\"draws\".")
    else if (method == "hk" && !("prob" %in% names(qtl)))
      stop("The qtl object doesn't contain QTL genotype probabilities; re-run makeqtl with what=\"prob\".")
  }

  # deal with missing data
  if(!is.null(covar))
    phcovar <- cbind(pheno, covar)
  else phcovar <- as.data.frame(pheno, stringsAsFactors = TRUE)
  hasmissing <- apply(phcovar, 1, function(a) any(is.na(a)))
  if (all(hasmissing))
    stop("All individuals are missing phenotypes or covariates.")
  if (any(hasmissing)) {
    pheno <- pheno[!hasmissing,,drop=FALSE]
    cross <- subset(cross, ind = !hasmissing)
    if (!is.null(covar))
      covar <- covar[!hasmissing, , drop = FALSE]
    if (!startatnull) {
      if (method == "imp")
        qtl$geno <- qtl$geno[!hasmissing, , , drop = FALSE]
      else {
        for (i in seq(along = qtl$prob)) qtl$prob[[i]] <- qtl$prob[[i]][!hasmissing,
                        , drop = FALSE]
      }
      qtl$n.ind <- sum(!hasmissing)
    }
  }

  if( any(diag(var(pheno)) == 0 ) )
       stop( "There is a phenotype with no variability.")  

  if (max.qtl < 1)
    stop("Need max.qtl > 0 if we are to scan for qtl")

  # null log likelihood and initial formula
  if (is.null(covar)) {
    lod0 <- rep(0, length(pheno.cols))
    if (startatnull)
      firstformula <- y ~ Q1
    else firstformula <- formula
  }
  else {
    rss0 <- colSums(as.matrix(lm(as.matrix(pheno) ~ as.matrix(covar))$resid^2, na.rm=TRUE))
    rss00 <- colSums(as.matrix(lm(as.matrix(pheno) ~ 1)$resid^2, na.rm=TRUE))
    lod0 <- nrow(pheno)/2 * log10(rss00/rss0)

    if (startatnull)
      firstformula <- as.formula(paste("y~",
                                       paste(names(covar), collapse = "+"),
                                       "+", "Q1"))
    else firstformula <- formula
  }

  # check penalties
  if (length(penalties) != 3) {
    if(length(penalties) == 1) {
      if(additive.only)
        penalties <- c(penalties, Inf, Inf)
      else stop("You must include a penalty for interaction terms.")
    }
    else {
      if (length(penalties) == 2)
        penalties <- penalties[c(1, 2, 2)]
      else {
        warning("penalties should have length 3")
        penalties <- penalties[1:3]
      }
    }
  }

  if(verbose > 2) verbose.scan <- TRUE
  else verbose.scan <- FALSE

  # start QTL analysis
  curbest <- NULL
  curbestplod <- 0
  if (verbose) cat(" -Initial scan\n")
  if (startatnull) {
    if (additive.only || max.qtl == 1 ) {
      out <- scanoneF(cross, pheno.cols = pheno.cols, method = method,
                      model = "normal", addcovar = covar)
      if( usec == "slod") {
        lod <- max(out[, 3], na.rm = TRUE)
        curplod <- calc.plod(lod, c(1, 0, 0), penalties = penalties)
        wh <- which(!is.na(out[, 3]) & out[, 3] == lod)
      }
      if( usec == "mlod") {
        lod <- max(out[, 4], na.rm = TRUE)
        curplod <- calc.plod(lod, c(1, 0, 0), penalties = penalties)
        wh <- which(!is.na(out[, 4]) & out[, 4] == lod)
      }

      if (length(wh) > 1)
        wh <- sample(wh, 1)
      qtl <- makeqtl(cross, as.character(out[wh, 1]), out[wh,
                                                          2], "Q1", what = qtlmethod)
      formula <- firstformula
      n.qtl <- 1
    }
    else {
      out <- scantwoF(cross, pheno.cols = pheno.cols, usec=usec, method = method,
                      model = "normal", incl.markers = incl.markers,
                      addcovar = covar, verbose = verbose.scan)
      lod <- out$lod
      lod1 <- max(diag(lod), na.rm = TRUE)
      plod1 <- calc.plod(lod1, c(1, 0, 0), penalties = penalties)
      loda <- max(lod[upper.tri(lod)], na.rm = TRUE)
      ploda <- calc.plod(loda, c(2, 0, 0), penalties = penalties)
      lodf <- max(lod[lower.tri(lod)], na.rm = TRUE)
      plodf <- calc.plod(lodf, c(2, 0, 1), penalties = penalties)
      if (plod1 > ploda && plod1 > plodf) {
        wh <- which(!is.na(diag(lod)) & diag(lod) ==
                    lod1)
        if (length(wh) > 1)
          wh <- sample(wh, 1)
        m <- out$map[wh, ]
        qtl <- makeqtl(cross, as.character(m[1, 1]),
                       m[1, 2], "Q1", what = qtlmethod)
        formula <- firstformula
        n.qtl <- 1
        lod <- lod1
        curplod <- plod1
      }
      else if (ploda > plodf) {
        temp <- max(out, what = "add")
        if (nrow(temp) > 1)
          temp <- temp[sample(1:nrow(temp), 1), ]
        qtl <- makeqtl(cross, c(as.character(temp[1,
                                                  1]), as.character(temp[1, 2])), c(temp[1, 3],
                                                                                    temp[1, 4]), c("Q1", "Q2"), what = qtlmethod)
        formula <- as.formula(paste(qtl::deparseQTLformula(firstformula),
                                    "+Q2", sep = ""))
        curplod <- ploda
        lod <- loda
        n.qtl <- 2
      }
      else {
        temp <- max(out, what = "full")
        if (nrow(temp) > 1)
          temp <- temp[sample(1:nrow(temp), 1), ]
        qtl <- makeqtl(cross, c(as.character(temp[1,
                                                  1]), as.character(temp[1, 2])), c(temp[1, 3],
                                                                                    temp[1, 4]), c("Q1", "Q2"), what = qtlmethod)
        formula <- as.formula(paste(qtl::deparseQTLformula(firstformula),
                                    "+Q2+Q1:Q2", sep = ""))
        curplod <- plodf
        lod <- lodf
        n.qtl <- 2
      }
    }
  }
  else {
    if (verbose)
      cat(" ---Starting at a model with", length(qtl$chr),
          "QTL\n")
    if (refine.locations) {
      if (verbose)
        cat(" ---Refining positions\n")
      rqtl <- refineqtlF(cross, pheno.cols = pheno.cols, qtl = qtl,
                         covar = covar, formula = formula, method = method,
                         verbose = verbose.scan, incl.markers = incl.markers,
                         keeplodprofile = FALSE, usec = usec)
      if (any(rqtl$pos != qtl$pos)) {
        if (verbose)
          cat(" ---  Moved a bit\n")
      }
      qtl <- rqtl
    }


    res.full = NULL;
    qtl$name <- qtl$altname

    # calculate penalized LOD
    lod <- fitqtlF(cross=cross, pheno.cols=pheno.cols, qtl=qtl, formula=formula,
                   covar=covar, method=method, lod0=lod0)
    lod <- ifelse(usec=="slod", mean(lod), max(lod))
    curplod <- calc.plod(lod, qtl::countqtlterms(formula, ignore.covar = TRUE),
                         penalties = penalties)
    attr(qtl, "pLOD") <- curplod
    n.qtl <- length(qtl$chr)
  }
  attr(qtl, "formula") <- qtl::deparseQTLformula(formula)
  attr(qtl, "pLOD") <- curplod
  if (curplod > 0) {
    curbest <- qtl
    curbestplod <- curplod
    if (verbose)
      cat("** new best ** (pLOD increased by ",
          round(curplod, 4), ")\n", sep = "")
  }
  if (keeptrace) {
    temp <- list(chr = qtl$chr, pos = qtl$pos)
    attr(temp, "formula") <- qtl::deparseQTLformula(formula)
    attr(temp, "pLOD") <- curplod
    class(temp) <- c("compactqtl", "list")
    thetrace <- list(`0` = temp)
  }
  if (verbose)
    cat("    no.qtl = ", n.qtl, "  pLOD =", curplod, "  formula:",
        qtl::deparseQTLformula(formula), "\n")
  if (verbose > 1)
    cat("         qtl:", paste(qtl$chr, round(qtl$pos, 1),
                               sep = "@"), "\n")
  i <- 0
  while (n.qtl < max.qtl) {
    i <- i + 1
    if (verbose) {
      cat(" -Step", i, "\n")
      cat(" ---Scanning for additive qtl\n")
    }
    out <- addqtlF(cross, pheno.cols = pheno.cols, qtl = qtl,
                   covar = covar, formula = formula, method = method,
                   incl.markers = incl.markers, verbose = verbose.scan)

    if(usec=="slod") {
      curlod <- max(out[, 3], na.rm = TRUE)
      wh <- which(!is.na(out[, 3]) & out[, 3] == curlod)
    }
    if(usec=="mlod") {
      curlod <- max(out[, 4], na.rm = TRUE)
      wh <- which(!is.na(out[, 4]) & out[, 4] == curlod)
    }

    if (length(wh) > 1) wh <- sample(wh, 1)
    curqtl <- addtoqtl(cross, qtl, as.character(out[wh, 1]),
                       out[wh, 2], paste("Q", n.qtl + 1, sep = ""))
    curformula <- as.formula(paste(qtl::deparseQTLformula(formula),
                                   "+Q", n.qtl + 1, sep = ""))

    # re-calculate LOD
    curlod <- fitqtlF(cross=cross, pheno.cols=pheno.cols, qtl=curqtl, formula=curformula,
                      covar=covar, method=method, lod0=lod0)
    curlod <- ifelse(usec=="slod", mean(curlod), max(curlod))
    curplod <- calc.plod(curlod, qtl::countqtlterms(curformula, ignore.covar = TRUE),
                         penalties = penalties)
    if (verbose)  cat("        plod =", curplod, "\n")

    curnqtl <- n.qtl + 1
    if (!additive.only) {
      for (j in 1:n.qtl) {
        if (verbose)
          cat(" ---Scanning for QTL interacting with Q",
              j, "\n", sep = "")
        thisformula <- as.formula(paste(qtl::deparseQTLformula(formula),
                                        "+Q", n.qtl + 1, "+Q", j, ":Q", n.qtl + 1,
                                        sep = ""))
        out <- addqtlF(cross, pheno.cols = pheno.cols, qtl = qtl,
                       covar = covar, formula = thisformula, method = method,
                       incl.markers = incl.markers, verbose = verbose.scan)


        if(usec=="slod") {
          thislod <- max(out[, 3], na.rm = TRUE)
          wh <- which(!is.na(out[, 3]) & out[, 3] == thislod)
        }
        if(usec=="mlod") {
          thislod <- max(out[, 4], na.rm = TRUE)
          wh <- which(!is.na(out[, 4]) & out[, 4] == thislod)
        }

        if (length(wh) > 1)
          wh <- sample(wh, 1)
        thisqtl <- addtoqtl(cross, qtl, as.character(out[wh, 1]), out[wh, 2], paste("Q", n.qtl + 1, sep = ""))
        thislod <- thislod + lod
        thisplod <- calc.plod(thislod, qtl::countqtlterms(thisformula,
                                                          ignore.covar = TRUE), penalties = penalties)
        if (verbose)
          cat("        plod =", thisplod, "\n")
        if (thisplod > curplod) {
          curformula <- thisformula
          curplod <- thisplod
          curlod <- thislod
          curqtl <- thisqtl
          curnqtl <- n.qtl + 1
        }
      }
      if (n.qtl > 1) {
        if (verbose)
          cat(" ---Look for additional interactions\n")

        temp <- addint(cross, pheno.col = pheno.cols[1], qtl,
                       covar = covar,
                       formula = formula, method = method,
                       qtl.only = TRUE,
                       verbose = verbose.scan)
        if(!is.null(temp)) {

          lodlod <- NULL;
          for(ii in pheno.cols) {
            lodlod <- cbind(lodlod, addint(cross, pheno.col = ii, qtl,
                                           covar = covar,
                                           formula = formula, method = method,
                                           qtl.only = TRUE,
                                           verbose = verbose.scan)[,3] )
          }
          if(usec=="slod") {
            if(!(is.matrix(lodlod))) {
              lodlod <- mean(lodlod)
            } else {
              lodlod <- apply(lodlod,1,mean)
            }
            thislod <- max(lodlod, na.rm=TRUE)
          }

          if(usec=="mlod") {
            if(!(is.matrix(lodlod))) {
              lodlod <- max(lodlod)
            } else {
              lodlod <- apply(lodlod,1,max)
            }
            thislod <- max(lodlod, na.rm=TRUE)
          }



          wh <- which(!is.na(lodlod) & lodlod == thislod)
          if (length(wh) > 1)
            wh <- sample(wh, 1)
          thisformula <- as.formula(paste(qtl::deparseQTLformula(formula),
                                          "+", rownames(temp)[wh]))
          thislod <- thislod + lod
          thisplod <- calc.plod(thislod, qtl::countqtlterms(thisformula,
                                                            ignore.covar = TRUE), penalties = penalties)
          if (verbose)
            cat("        plod =", thisplod, "\n")
          if (thisplod > curplod) {
            curformula <- thisformula
            curplod <- thisplod
            curlod <- thislod
            curqtl <- qtl
            curnqtl <- n.qtl
          }
        }
      }
    }
    qtl <- curqtl
    n.qtl <- curnqtl
    attr(qtl, "formula") <- qtl::deparseQTLformula(curformula)
    attr(qtl, "pLOD") <- curplod
    formula <- curformula
    lod <- curlod
    if (refine.locations) {
      if (verbose)
        cat(" ---Refining positions\n")
      rqtl <- refineqtlF(cross, pheno.cols = pheno.cols, qtl = qtl,
                         covar = covar, formula = formula, method = method,
                         verbose = verbose.scan, incl.markers = incl.markers,
                         keeplodprofile = FALSE, usec = usec)
      if (any(rqtl$pos != qtl$pos)) {
        if (verbose) cat(" ---  Moved a bit\n")
        qtl <- rqtl

        lod <- fitqtlF(cross=cross, pheno.cols=pheno.cols, qtl=qtl, formula=formula,
                       covar=covar, method=method, lod0=lod0)
        lod <- ifelse(usec=="slod", mean(lod), max(lod))

        curplod <- calc.plod(lod, qtl::countqtlterms(formula, ignore.covar = TRUE),
                             penalties = penalties)
        attr(qtl, "pLOD") <- curplod
      }
    }

    if (verbose)
      cat("    no.qtl = ", n.qtl, "  pLOD =", curplod,
          "  formula:", qtl::deparseQTLformula(formula), "\n")
    if (verbose > 1)
      cat("         qtl:", paste(qtl$chr, round(qtl$pos,
                                                1), sep = "@"), "\n")
    if (curplod > curbestplod) {
      if (verbose)
        cat("** new best ** (pLOD increased by ", round(curplod -
                                                        curbestplod, 4), ")\n", sep = "")
      curbest <- qtl
      curbestplod <- curplod
    }
    if (keeptrace) {
      temp <- list(chr = qtl$chr, pos = qtl$pos)
      attr(temp, "formula") <- qtl::deparseQTLformula(formula)
      attr(temp, "pLOD") <- curplod
      class(temp) <- c("compactqtl", "list")
      temp <- list(temp)
      names(temp) <- i
      thetrace <- c(thetrace, temp)
    }
    if (n.qtl >= max.qtl)
      break
  }

  if (verbose)
    cat(" -Starting backward deletion\n")
  while (n.qtl > 1) {
    i <- i + 1

    qtl$name <- qtl$altname
    out2 <- fitqtl(cross, pheno.col=pheno.cols[1], qtl, covar = covar, formula = formula,
                   method = method, model = "normal", dropone = TRUE, get.ests = FALSE,
                   run.checks = FALSE)$result.drop
    termnames <- rownames(out2)
    row2save <- c(grep("^[Qq][0-9]+$", termnames), grep("^[Qq][0-9]+:[Qq][0-9]+$", termnames))
    termnames <- termnames[row2save]

    lodbyphe <- out2[row2save,3]
    for(ii in pheno.cols[-1]) {
      tmp <- fitqtl(cross, pheno.col=ii, qtl, covar = covar,
                     formula = formula, method = method,
                     model = "normal", dropone = TRUE, get.ests = FALSE,
                     run.checks = FALSE)$result.drop[row2save, 3]
      lodbyphe <- cbind(lodbyphe, tmp)
    }

    if(usec=="slod") thelod <- rowMeans(lodbyphe)
    else thelod <- apply(lodbyphe, 1, max)

    minlod <- min(thelod, na.rm = TRUE)
    term2drop <- which(!is.na(thelod) & thelod == minlod)
    if(length(term2drop) > 1) term2drop <- sample(term2drop, 1) # handle ties

    todrop <- termnames[term2drop]
    if(verbose) cat(" ---Dropping", todrop, "\n")
    if(length(grep(":", todrop)) > 0) {
      theterms <- attr(terms(formula), "factors")
      wh <- colnames(theterms) == todrop
      if (!any(wh))
        stop("Confusion about what interation to drop!")
      theterms <- colnames(theterms)[!wh]
      formula <- as.formula(paste("y~", paste(theterms, collapse = "+")))
    }
    else {
      numtodrop <- as.numeric(substr(todrop, 2, nchar(todrop)))
      theterms <- attr(terms(formula), "factors")
      cn <- colnames(theterms)
      g <- c(grep(paste("^[Qq]", numtodrop, "$", sep = ""),
                  cn), grep(paste("^[Qq]", numtodrop, ":", sep = ""),
                            cn), grep(paste(":[Qq]", numtodrop, "$", sep = ""),
                                      cn))
      cn <- cn[-g]
      formula <- as.formula(paste("y~", paste(cn, collapse = "+")))
      if (n.qtl > numtodrop) {
        for (j in (numtodrop + 1):n.qtl) formula <- qtl::reviseqtlnuminformula(formula,
                                                                               j, j - 1)
      }
      qtl <- dropfromqtl(qtl, index = numtodrop)
      qtl$name <- qtl$altname <- paste("Q", 1:qtl$n.qtl,
                                       sep = "")
      n.qtl <- n.qtl - 1
    }

    # re-calculate LOD for model
    lod <- fitqtlF(cross=cross, pheno.cols=pheno.cols, qtl=qtl, formula=formula,
                   covar=covar, method=method, lod0=lod0)
    lod <- ifelse(usec=="slod", mean(lod), max(lod))
    curplod <- calc.plod(lod, qtl::countqtlterms(formula, ignore.covar = TRUE),
                         penalties = penalties)

    if (verbose)
      cat("    no.qtl = ", n.qtl, "  pLOD =", curplod,
          "  formula:", qtl::deparseQTLformula(formula), "\n")
    if (verbose > 1)
      cat("         qtl:", paste(qtl$chr, round(qtl$pos,
                                                1), sep = ":"), "\n")
    attr(qtl, "formula") <- qtl::deparseQTLformula(formula)
    attr(qtl, "pLOD") <- curplod
    if (refine.locations) {
      if (verbose)
        cat(" ---Refining positions\n")
      if (!is.null(qtl)) {
        rqtl <- refineqtlF(cross, pheno.cols = pheno.cols,
                           qtl = qtl, covar = covar, formula = formula,
                           method = method, verbose = verbose.scan, incl.markers = incl.markers,
                           keeplodprofile = FALSE, usec = usec)
        if (any(rqtl$pos != qtl$pos)) {
          if (verbose)
            cat(" ---  Moved a bit\n")
          qtl <- rqtl

          lod <- fitqtlF(cross=cross, pheno.cols=pheno.cols, qtl=qtl, formula=formula,
                         covar=covar, method=method, lod0=lod0)
          lod <- ifelse(usec=="slod", mean(lod), max(lod))

          curplod <- calc.plod(lod, qtl::countqtlterms(formula, ignore.covar = TRUE),
                               penalties = penalties)
          attr(qtl, "pLOD") <- curplod
        }
      }
    }
    if (curplod > curbestplod) {
      if (verbose)
        cat("** new best ** (pLOD increased by ", round(curplod -
                                                        curbestplod, 4), ")\n", sep = "")
      curbestplod <- curplod
      curbest <- qtl
    }
    if (keeptrace) {
      temp <- list(chr = qtl$chr, pos = qtl$pos)
      attr(temp, "formula") <- qtl::deparseQTLformula(formula)
      attr(temp, "pLOD") <- curplod
      class(temp) <- c("compactqtl", "list")
      temp <- list(temp)
      names(temp) <- i
      thetrace <- c(thetrace, temp)
    }
  }

  if (!is.null(curbest)) {
    chr <- curbest$chr
    pos <- curbest$pos
    o <- order(factor(chr, levels = names(cross$geno)), pos)
    qtl <- makeqtl(cross, chr[o], pos[o], what = qtlmethod)
    formula <- as.formula(attr(curbest, "formula"))
    if (length(chr) > 1) {
      n.qtl <- length(chr)
      for (i in 1:n.qtl) formula <- qtl::reviseqtlnuminformula(formula, i, n.qtl + i)
      for (i in 1:n.qtl) formula <- qtl::reviseqtlnuminformula(formula, n.qtl + o[i], i)
    }
    attr(qtl, "formula") <- qtl::deparseQTLformula(formula)
    attr(qtl, "pLOD") <- attr(curbest, "pLOD")
    curbest <- qtl
  }
  else {
    curbest <- numeric(0)
    class(curbest) <- "qtl"
    attr(curbest, "pLOD") <- 0
  }
  if (keeptrace)
    attr(curbest, "trace") <- thetrace
  attr(curbest, "formula") <- qtl::deparseQTLformula(attr(curbest, "formula"), TRUE)
  curbest
}
