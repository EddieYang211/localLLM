#' AG News classification sample
#'
#' A 100-row subset of the AG News Topic Classification dataset consisting of
#' 25 documents from each of the four classes (World, Sports, Business,
#' Sci/Tech). The sample is intended for quick demonstrations and tests without
#' requiring the full external dataset.
#'
#' @format A data frame with 100 rows and 3 character columns:
#' \describe{
#'   \item{class}{News topic label (\code{"World"}, \code{"Sports"}, \code{"Business"}, or \code{"Sci/Tech"}).}
#'   \item{title}{Headline of the news article.}
#'   \item{description}{Short description for the article.}
#' }
#'
#' @details
#' The sample was obtained from \code{textdata::dataset_ag_news()} (Zhang et al.,
#' 2015) using a fixed random seed to ensure reproducibility. It is provided
#' solely for illustrative purposes.
#'
#' @source Zhang, X., Zhao, J., & LeCun, Y. (2015). "Character-level Convolutional
#' Networks for Text Classification." arXiv:1509.01626. Original data distributed
#' via the AG News Topic Classification dataset.
#'
#' @seealso [textdata::dataset_ag_news()]
#'
#' @docType data
#' @keywords datasets
#' @name ag_news_sample
#' @usage data(ag_news_sample)
"ag_news_sample"
