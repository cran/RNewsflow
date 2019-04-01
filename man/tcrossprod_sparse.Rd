% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/crossprod.r
\name{tcrossprod_sparse}
\alias{tcrossprod_sparse}
\title{The tcrossprod function for sparse matrices, for people that like drowning in parameters}
\usage{
tcrossprod_sparse(m, m2 = NULL, min_value = NULL, max_value = NULL,
  only_upper = F, diag = T, top_n = NULL, rowsum_div = F,
  zscore = F, normalize = c("none", "l2", "softl2"),
  crossfun = c("prod", "min", "softprod", "maxproduct"), group = NULL,
  group2 = NULL, date = NULL, date2 = NULL, lwindow = -1,
  rwindow = 1, date_unit = c("days", "hours", "minutes", "seconds"),
  simmat = NULL, simmat_thres = NULL, batchsize = 1000,
  verbose = F)
}
\arguments{
\item{m}{A dgCMatrix}

\item{m2}{A dgCMatrix}

\item{min_value}{Optionally, a numerical value, specifying the threshold for including a score in the output.}

\item{max_value}{Optionally, a numerical value for the upper limit for including a score in the output.}

\item{only_upper}{if true, only the upper triangle of the matrix is returned. Only possible for symmetrical output (m and m2 have same number of columns)}

\item{diag}{if false, the diagonal of the matrix is not returned. Only possible for symmetrical output (m and m2 have same number of columns)}

\item{top_n}{an integer, specifying the top number of strongest scores for each column in m}

\item{rowsum_div}{if true, divide crossproduct by column sums of m. (this has to happen within the loop for min_value and top_n filtering)}

\item{zscore}{if true, transform the similarity scores for each row in m to z-scores. The min_value and max_value filters will in that case apply to the zscore value.}

\item{normalize}{normalize rows by a given norm score. Default is 'none' (no normalization). 'l2' is the l2 norm (use in combination with 'prod' crossfun for cosine similarity). 'l2soft' is the adaptation of l2 for soft similarity (use in combination with 'softprod' crossfun for soft cosine)}

\item{crossfun}{The function used in the vector operations. 
Normally this is the "prod", for product (dot product). 
Here we also allow the "min", for minimum value. 
We use this in our document overlap_pct score.
In addition, there is the (experimental) softprod, that can be used in combination with softl2 normalization to get the soft cosine similarity.
And, the "maxproduct" is a special case used in the query_lookup measure, that uses product but only returns the score of the strongest matching term.}

\item{group}{Optionally, a character vector that specifies a group (e.g., source) for each row in m. If given, only pairs of rows with the same group are calculated.}

\item{group2}{If m2 and group are used, group2 has to be used to specify the groups for the rows in m2 (otherwise group will be ignored)}

\item{date}{Optionally, a character vector that specifies a date for each row in m. If given, only pairs of rows within a given date range (see lwindow, rwindow and date_unit) are calculated.}

\item{date2}{If m2 and date are used, date2 has to be used to specify the date for the rows in m2 (otherwise date will be ignored)}

\item{lwindow}{If date (and date2) are used, lwindow determines the left side of the date window. e.g. -10 means that rows are only matched with rows for which date is within 10 [date_units] before.}

\item{rwindow}{Like lwindow, but for the right side. e.g. an lwindow of -1 and rwindow of 1, with date_unit is "days", means that only rows are matched for which the dates are within a 1 day distance}

\item{date_unit}{The date unit used in lwindow and rwindow. Supports "days", "hours", "minutes" and "seconds". Note that refers to the time distance between two rows ("days" doesn't refer to calendar days, but to a time of 24 hours)}

\item{simmat}{if softcos is used, a symmetric matrix with terms that indicates the similarity of terms (i.e. adjacency matrix). If NULL, a cosine similarity matrix will be created on the go}

\item{simmat_thres}{if softcos is used, a threshold for the term similarity.}

\item{batchsize}{If group and/or date are used, size of batches.}

\item{verbose}{if TRUE, report progress}
}
\value{
A dgCMatrix
}
\description{
tcrossprod with benefits. Enables limiting row combinations to within specified groups 
and date windows, and filters results that do not pass the threshold on the fly.
To achieve this, options for similarity measures are included in the function.
For example, to get the cosine similarity, you can normalize with "l2" and use the "prod" (product) function for the
}
\details{
This function is called by the document comparison functions (documents.compare, newsflow.compare, delete.duplicates).
We only expose it here for additional flexibility, and because it could be usefull outside of the purpose of this package.
}
\examples{
set.seed(1)
m = Matrix::rsparsematrix(5,10,0.5)
tcrossprod_sparse(m, min_value = 0, only_upper = FALSE, diag = TRUE)
tcrossprod_sparse(m, min_value = 0, only_upper = FALSE, diag = FALSE)
tcrossprod_sparse(m, min_value = 0, only_upper = TRUE, diag = FALSE)
tcrossprod_sparse(m, min_value = 0.2, only_upper = TRUE, diag = FALSE)
tcrossprod_sparse(m, min_value = 0, only_upper = TRUE, diag = FALSE, top_n = 1)
}