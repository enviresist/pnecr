rm(list=ls())

library("bbmle")
library("boot")
set.seed(1)

# output directory
odir <- "output"

# cost database
db <- read.table("../1_databases/db_cost.tsv", header=T, sep="\t")

# filter data
cost <- db[db$resistance_type == "plasmid", "cost"]
cost <- cost[is.finite(cost)]

# drop outliers
print(paste("Records before:",length(cost)))
print(paste("IQR rule range:",paste(IQR(cost) + c(-1.5, 1.5)*IQR(cost),
  collapse=" ... ")))
cost <- cost[abs(cost) <= 0.25]
print(paste("Records remaining:",length(cost)))

# NOTE: a possible data transformation would be
#       z = -log(1 - cost) = -log(fitnessRatio)
# but there was no significant improvement in the fit


svg(paste0(odir,"/cost_fitted.svg"), width=5.5, height=5)

# initialize plot with empirical quantiles; the particular
#   probability levels can be chosen arbitrarily
tmp <- c(0.01, 0.02, 0.05, 0.1, 0.2, 0.33)
probabilities <- c(tmp, 0.5, 1 - rev(tmp))
plot(quantile(cost, probs=probabilities), probabilities, pch=20,
  xlab="Cost associated with AMR plasmid",
#  ylab=expression(paste("Probability (",X <= x,")"))
  ylab="Cumulative distribution function"
)
rm(tmp, probabilities)

# mixture distribution model: a weighted sum of a normal distribution
# component and an exponential distribution component.
# Note: Replacing the exponential component by a beta-distribution
#   might be conceptially better because it is confined to the 0...1
#   interval. But since the largest reasonable cost is far below 1,
#   there is no advantage from using a more complex beta-model.

# distribution model used for plotting
model <- function(pars, cost) {
  pars["f"] * pnorm(q=cost, mean=0, sd=pars["sd"]) +
    (1-pars["f"]) * pexp(q=cost, rate=pars["rate"])
}

# objective function for MLE fitting
objfun <- function(f, sd, rate, cost) {
  lik <- f * dnorm(x=cost, mean=0, sd=sd) +
    (1-f) * dexp(x=cost, rate=rate)
  -1 * sum(log(lik))
}

# MLE fitting: the reason for using bbmle::mle2 is that this
# function returns all necessary outputs for computing confidence
# intervals for the parameters by likelihood profiling 
guess <- list(f=0.3, sd=0.05, rate=12)
fit <- bbmle::mle2(minuslogl=objfun, start=guess, data=list(cost=cost))
print("fitted parameters:")
print(coef(fit))

# add fitted mixture distribution and individual components to plot
cost.line <- seq(-0.5, 1, 0.01)
lines(cost.line, model(pars=coef(fit), cost=cost.line))
lines(cost.line, pnorm(q=cost.line, mean=0, sd=coef(fit)["sd"]), lty=3, col="blue")
lines(cost.line, pexp(q=cost.line, rate=coef(fit)["rate"]), lty=4, col="red")
legend("bottomright", bty="n",
  pch=c(20,NA,NA,NA),
  lty=c(NA,1,3,4),
  col=c("black","black","blue","red"),
  legend=c("Empirical quantiles","Fitted mixture distrib.",
    "Gaussian component","Exponential component")
)
graphics.off()

# confidence intervals of distribution parameters
ci.param <- confint(fit)

# table of the exponential distribution component
p <- c(0.01, 0.02, 0.05, 0.1, 0.25, 0.5)
x <- data.frame(
  Probability=p,
  Cost=signif(qexp(p=p, rate=coef(fit)["rate"]), 2),
  # CI of cost estimates obtained from CI of fitted parameter
  `95% CI (using profile lik.)`=paste(
    signif(qexp(p=p, rate=ci.param["rate",2]), 2),
    signif(qexp(p=p, rate=ci.param["rate",1]), 2), sep=" - "),
  check.names=F
)

# alternative CI of cost obtained by bootstrapping
fn <- function(cost, indices) {
  fit <- bbmle::mle2(minuslogl=objfun, start=guess,
    data=list(cost=cost[indices]))
  p <- c(0.01, 0.02, 0.05, 0.1, 0.25, 0.5)
  q <- qexp(p=p, rate=coef(fit)["rate"])  # quantiles of cost
  names(q) <- p
  q
}
b <- boot(data=cost, statistic=fn, R=250, sim="ordinary", stype="i")
ci.boot <- NULL
for (i in 1:length(b$t0)) {
  p <- names(b$t0[i])
  bci <- boot.ci(b, conf=0.95, type="norm", index=i)$normal
  ci.boot <- rbind(ci.boot, data.frame(
    Probability=as.numeric(rownames(bci)[1]),
    `95% CI (using bootstrap)`=paste(
       signif(bci[1,2], 2),
       signif(bci[1,3], 2), sep=" - "),
    check.names=F)
  )
}

# merge tables
x <- merge(x, ci.boot, by="Probability")

write.table(x, file=paste0(odir,"/cost_quantiles.tsv"), col.names=T, row.names=F,
  quote=F, sep="\t")
