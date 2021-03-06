# redefine S3 as S4 classes for proper handling as part of the 'mtergm' class
setOldClass(c("ergm", "ergm"))

# an S4 class for btergm objects
setClass(Class = "mtergm", 
    slots = c(
        coef = "numeric", 
        se = "numeric", 
        pval = "numeric", 
        nobs = "numeric", 
        time.steps = "numeric",
        formula = "formula",
        formula2 = "character", 
        auto.adjust = "logical", 
        offset = "logical", 
        directed = "logical", 
        bipartite = "logical", 
        estimate = "character", 
        loglik = "numeric", 
        aic = "numeric", 
        bic = "numeric", 
        ergm = "ergm", 
        nvertices = "matrix", 
        data = "list"
    ), 
    validity = function(object) {
        if (!"numeric" %in% class(object@coef)) {
          stop("'coef' must be a 'numeric' vector.")
        }
        if (!"numeric" %in% class(object@se)) {
          stop("'se' must be a 'numeric' vector.")
        }
        if (!"numeric" %in% class(object@pval)) {
          stop("'pval' must be a 'numeric' vector.")
        }
        if (!is.numeric(object@nobs)) {
          stop("'nobs' must be a numeric value of length 1.")
        }
        if (!is.numeric(object@time.steps)) {
          stop("'time.steps' must be a numeric value of length 1.")
        }
        if (!"formula" %in% class(object@formula)) {
          stop("'formula' is not a 'formula' object.")
        }
        if (length(object@coef) != length(object@se)) {
          stop("Number of terms differs between 'coef' and 'se'")
        }
        if (length(object@coef) != length(object@pval)) {
          stop("Number of terms differs between 'coef' and 'pval'")
        }
        if (length(object@loglik) > 1) {
          stop("'loglik' must be a numeric value of length 1.")
        }
        if (length(object@aic) > 1) {
          stop("'aic' must be a numeric value of length 1.")
        }
        if (length(object@bic) > 1) {
          stop("'bic' must be a numeric value of length 1.")
        }
        return(TRUE)
    }
)


# constructor for btergm objects
createMtergm <- function(coef, se, pval, nobs, time.steps, formula, formula2, 
    auto.adjust, offset, directed, bipartite, estimate, loglik, aic, bic, 
    ergm = ergm, nvertices, data) {
  new("mtergm", coef = coef, se = se, pval = pval, nobs = nobs, 
      time.steps = time.steps, formula = formula, formula2 = formula2, 
      auto.adjust = auto.adjust, offset = offset, directed = directed, 
      bipartite = bipartite, estimate = estimate, loglik = loglik, aic = aic, 
      bic = bic, ergm = ergm, nvertices = nvertices, data = data)
}


# define show method for pretty output of btergm objects
setMethod(f = "show", signature = "mtergm", definition = function(object) {
    message("MLE Coefficients:")
    print(object@coef)
  }
)


# define coef method for extracting coefficients from btergm objects
setMethod(f = "coef", signature = "mtergm", definition = function(object, 
      invlogit = FALSE, ...) {
    if (invlogit == FALSE) {
      return(object@coef)
    } else {
      return(1 / (1 + exp(-object@coef)))
    }
  }
)


# define nobs method for extracting number of observations from btergm objects
setMethod(f = "nobs", signature = "mtergm", definition = function(object) {
    n <- object@nobs
    t <- object@time.steps
    return(c("Number of time steps" = t, "Number of observations" = n))
  }
)


# function which can extract the number of time steps
timesteps.mtergm <- function(object) {
  return(object@time.steps)
}


# define summary method for pretty output of mtergm objects
setMethod(f = "summary", signature = "mtergm", definition = function(object, 
    ...) {
    message(paste(rep("=", 26), collapse=""))
    message("Summary of model fit")
    message(paste(rep("=", 26), collapse=""))
    message(paste("\nFormula:  ", gsub("\\s+", " ", 
        paste(deparse(object@formula), collapse = "")), "\n"))
    message(paste("Time steps:", object@time.steps, "\n"))
    
    message("Monte Carlo MLE Results:")
    cmat <- cbind(object@coef, object@se, object@coef / object@se, object@pval)
    colnames(cmat) <- c("Estimate", "Std. Error", "t value", "Pr(>|t|)")
    printCoefmat(cmat, cs.ind = 1:2, tst.ind = 3)
  }
)


# MCMC MLE estimation function (basically a wrapper for the ergm function)
mtergm <- function(formula, constraints = ~ ., returndata = FALSE, 
    verbose = TRUE, ...) {
  
  # call tergmprepare and integrate results as a child environment in the chain
  l <- tergmprepare(formula = formula, offset = FALSE, blockdiag = TRUE, 
      verbose = verbose)
  for (i in 1:length(l$covnames)) {
    assign(l$covnames[i], l[[l$covnames[i]]])
  }
  assign("offsmat", l$offsmat)
  form <- as.formula(l$form, env = environment())
  
  # compile data for creating an mtergm object later; return if necessary
  data <- list()
  for (i in 1:length(l$covnames)) {
    data[[l$covnames[i]]] <- l[[l$covnames[i]]]
  }
  data$offsmat <- l$offsmat
  if (returndata == TRUE) {
    message("Returning a list with data.")
    return(data)
  }
  
  if (verbose == TRUE) {
    message("Estimating...")
    e <- ergm(form, offset.coef = -Inf, constraints = constraints, 
        eval.loglik = TRUE, ...)
  } else {
    e <- suppressMessages(ergm(form, offset.coef = -Inf, 
        constraints = constraints, eval.loglik = TRUE, ...))
  }
  
  # get coefficients and other details
  cf <- coef(e)
  mat <- as.matrix(l$networks)
  if (l$bipartite == TRUE) {
    dyads <- sum(1 - l$offsmat)
  } else {
    dyads <- sum(1 - l$offsmat) - nrow(mat)
  }
  rdf <- dyads - length(cf)
  asyse <- vcov(e, sources = "all")
  se <- sqrt(diag(asyse))
  tval <- e$coef / se
  pval <- 2 * pt(q = abs(tval), df = rdf, lower.tail = FALSE)
  
  # create mtergm object
  object <- createMtergm(
      coef = cf[-length(cf)],  # do not include NA value for offset matrix
      se = se[-length(se)], 
      pval = pval[-length(pval)], 
      nobs = dyads, 
      time.steps = l$time.steps,
      formula = formula, 
      formula2 = l$form, 
      auto.adjust = l$auto.adjust, 
      offset = TRUE, 
      directed = l$directed, 
      bipartite = l$bipartite, 
      estimate = e$estimate,  # MLE or MPLE
      loglik = e$mle.lik[1], 
      aic = AIC(e), 
      bic = BIC(e), 
      ergm = e, 
      nvertices = l$nvertices, 
      data = data
  )
  
  if (verbose == TRUE) {
    message("Done.")
  }
  
  return(object)
}
