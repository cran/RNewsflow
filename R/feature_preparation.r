#' (experimental) Automatically infer queries from combinations of terms in a dtm
#'
#' Prepares query terms with high sparsity. Returns two matrices: a query and lookup dtm.
#' Can either be used with one dtm as input (which becomes both the query and lookup dtm) or
#' with a dtm and ref_dtm (reference), in which case dtm represents the queries and ref_dtm the lookup dtm.
#' 
#' The query dtm will contain the weighted term scores of the queries,
#' and the lookup dtm will contain binary values for whether or not terms occured.
#' This is designed to be used with the document.compare or newsflow.compare functions to compare the query matrix to the lookup matrix,
#' using the special 'query_lookup' similarity measure. 
#'
#' Performs two operations. 
#' First, clusters of very similar columns (high cosine similarity) can be merged into a single column.
#' This is an OR (union) combination, meaning that if at least one column is nonzero, the value will be one.
#' Second, all columns will be combined to get the co-occurences (AND, or intersect). 
#' 
#' To keep the vocabulary size manageable, only terms with at least min_docfreq (minimum document frequency) and max_docprob (max document probability) are returned.
#' If a ref_dtm is given, the ref_dtm will be used to compute the docfreq and docprob values, used for filtering and weighting.
#'
#' @param dtm          A quanteda \link[quanteda]{dfm}
#' @param ref_dtm      Optionally, another quanteda \link[quanteda]{dfm}. If given, the ref_dtm will be used to calculate the docfreq/docprob scores.
#' @param min_docfreq  The minimum frequency for terms or combinations of terms
#' @param max_docprob  The maximum probability (document frequency / N) for terms or combinations of terms
#' @param weight       Determine how to weight the queries (if ref_dtm is used, uses the idf of the ref_dtm). 
#'                     Default is "binary" (does/does not occur). "tfidf" uses common tf-idf weighting. "docprob" scores the query term as the probability that it occurs in a document in the lookup dtm (note that here rarer terms have a lower value).
#'                     The ref_dfm will always be binary.
#' @param min_obs_exp  The minimum ratio of the observed and expected frequency of a term combination
#' @param union_sim_thres If given, a number between 0 and 1, used as the cosine similarity threshold for combining clusters of terms 
#' @param combine_all  If True, combine all terms. If False (default), terms that are included as unigrams (i.e. that are within the min_docfreq and max_docprob) are not combined with other terms.
#' @param only_dtm_combs Only include term combinations that occur in dtm. This makes sense if we are only interested in assymetric similarity measures based on the query
#' @param verbose      If true, report progress
#'
#' @return a list with a query dtm and lookup dtm.
#' @export
#'
#' @examples
#'  q = create_queries(rnewsflow_dfm, min_docfreq = 2, union_sim_thres = 0.9, 
#'                     max_docprob = 0.05, verbose = FALSE)
#'  head(colnames(q$query_dtm),100)
create_queries <- function(dtm, ref_dtm=NULL, min_docfreq=2, max_docprob=0.001, weight=c('tfidf','binary'), min_obs_exp=NA, union_sim_thres=NA, verbose=F, combine_all=T, only_dtm_combs=T) {
  weight = match.arg(weight)
  if (!methods::is(dtm, 'dfm')) stop('dtm has to be a quanteda dfm')
  if (!is.null(ref_dtm) && !methods::is(dtm, 'dfm')) stop('ref_dtm has to be a quanteda dfm')
  
  if (!is.null(ref_dtm)) {
    voc = colnames(ref_dtm)[Matrix::colSums(ref_dtm) >= min_docfreq]
    voc = intersect(colnames(dtm), voc)
    m = ref_dtm[,voc]
  } else {
    m = dtm[,Matrix::colSums(dtm > 0) > min_docfreq]
  }
  if (min_docfreq < 0) stop('min docfreq must be zero or higher')
  if (max_docprob <= 0 || max_docprob > 1) stop('max_docprob must be a value between 0 and 1')
  
  if (!is.na(union_sim_thres)) {
    if (union_sim_thres <= 0 || union_sim_thres > 1) stop('Union sim thres must be a value between 0 and 1')
    if (verbose) message('Computing clusters of similar terms')
    simmat1 = term_occur_sim(m, union_sim_thres, verbose=verbose)
    m = term_union(m, methods::as(simmat1,'dgCMatrix'), as_dfm=F)
  }
  
  if (verbose) message('Computing term combinations')
  simmat2 = term_cooccurence_docprob(m, max_docfreq = max_docprob * nrow(m), min_obs_exp=min_obs_exp,
                                    min_docfreq=min_docfreq, verbose=verbose)


  if (verbose) message('Building new dtm')
  if (!is.null(ref_dtm)) {
    m_ref = m ## remember dtm_ref
    
    m = dtm[,voc]
    if (!is.na(union_sim_thres)) {
      m = term_union(m, methods::as(simmat1,'dgCMatrix'), as_dfm = F, verbose = F)
      voc = intersect(colnames(m), colnames(simmat2))
      m = m[,voc]
      simmat2 = simmat2[voc,voc]
    }
    
    if (only_dtm_combs) {
      simmat_filter = term_cooccurence_docprob(m, max_docfreq = nrow(m), min_obs_exp=min_obs_exp,
                                       min_docfreq=1, verbose=F)
      nz = which(simmat2 > 0)
      dropval = nz[simmat_filter[nz] == 0]
      simmat2[dropval] = 0
      simmat2 = Matrix::drop0(simmat2)
    }
    
    if (!combine_all) simmat2 = rm_comb_if_diag(simmat2)
    m = term_intersect(methods::as(m, 'dgCMatrix'), methods::as(simmat2, 'dgCMatrix'), as_dfm=F, verbose=F)
    
    if (verbose) message('Building new reference dtm')
    m_ref = m_ref[,voc]
    m_ref = term_intersect(methods::as(m_ref, 'dgCMatrix'), methods::as(simmat2, 'dgCMatrix'), as_dfm=F, verbose=F)
    
  } else {
    simmat2 = rm_comb_if_diag(simmat2)
    m = term_intersect(methods::as(m, 'dgCMatrix'), methods::as(simmat2, 'dgCMatrix'), as_dfm=F)
    m_ref = NULL
  }
  
  if (!ncol(m) == 0) m = weight_queries(m, m_ref, weight)

  m = quanteda::as.dfm(m)
  quanteda::docvars(m) = quanteda::docvars(dtm)
  
  if (!is.null(m_ref)) {
    m_ref = quanteda::as.dfm(m_ref > 0)
    quanteda::docvars(m_ref) = quanteda::docvars(ref_dtm)
  } else {
    m_ref = m > 0
  }
  
  list(query_dtm=m, ref_dtm=m_ref)
}

weight_queries <- function(dfm_x, dfm_y=NULL, weight) {
  if (weight == 'binary') return(dfm_x > 0)
  
  if (is.null(dfm_y)) dfm_y = dfm_x
  ts = Matrix::colSums(dfm_y > 0)  
  ts = ts[match(colnames(dfm_x), names(ts))]
  ts[is.na(ts)] = 0
  
  if (weight == 'docprob') {
    dprob = (ts / nrow(dfm_y))
    return(t(t(dfm_x > 0) * dprob))
  }
  if (weight == 'tfidf') {
    idf = log(1 + (nrow(dfm_y) / (ts+1)))
    return(t(t(dfm_x > 0) * idf))
  }
}

match_simmat_terms <- function(dtm, simmat) {
  if (!all(colnames(dtm) %in% colnames(simmat))) stop('not all terms in dtm are in  simmat')
  if (!ncol(dtm) == ncol(simmat)) {
    simmat = simmat[colnames(dtm), colnames(dtm)]
  } else {
    if (!all(colnames(dtm) == colnames(simmat))) {
      simmat = simmat[colnames(dtm), colnames(dtm)]
    }
  }
  simmat
}

#' Combine terms in a dtm
#' 
#' Given a dtm and a similarity (adjacency) matrix, group clusters of similar terms (simmat > 0) into a single column.
#' Column names will be concatenated, with a "|" seperator (read as OR)
#'
#' @param dtm          A quanteda \link[quanteda]{dfm} or a dgCMatrix.
#' @param simmat       A similarity matrix in dgCMatrix format. For instance, created with \link{term_char_sim}
#' @param as_dfm       If True, return as quanteda dfm
#' @param verbose      If True, report progress
#'
#' @return  A dgCMatrix or quanteda dfm
#' @export
#' 
#' @examples 
#' dfm = quanteda::dfm(c('That guy Gadaffi','Do you mean Kadaffi?',
#'                       'Nah more like Gadaffel','What Gargamel?'))
#' simmat = term_char_sim(colnames(dfm), same_start=0)
#' term_union(dfm, simmat, verbose = FALSE)
term_union <- function(dtm, simmat, as_dfm=T, verbose=F) {
  if (methods::is(dtm, "DocumentTermMatrix")) stop('this function does not work for tm DocumentTermMatrix class')
  #simmat = match_simmat_terms(dtm, simmat)
  dtm = pad_dfm(dtm, colnames(simmat))
  
  parentheses = grepl('[&|]', colnames(dtm))
  ml = term_union_cpp(dtm, simmat, colnames(dtm), parentheses, verbose)
  colnames(ml$m) = ml$colnames
  rownames(ml$m) = rownames(dtm)
  ml$m = ml$m[,colSums(ml$m) > 0]
  
  if (as_dfm && methods::is(dtm, 'dfm')) {
    m = quanteda::as.dfm(ml$m > 0)
    quanteda::docvars(m) = quanteda::docvars(dtm)
    return(m)
  } else {
    return(ml$m > 0)
  }
}

#' Combine terms in a dtm
#' 
#' Given a dtm and a similarity (adjacency) matrix, create a new column for each nonzero cell in the
#' similarity matrix. For the term combinations  (everything except the diagonal) the column names will be
#' pasted together with a "&" separator (read as AND)
#'
#' @param dtm          A quanteda \link[quanteda]{dfm} or a dgCMatrix.
#' @param simmat       A similarity matrix in dgCMatrix format. For instance, created with \link{term_char_sim}
#' @param as_dfm       If True, return as quanteda dfm
#' @param verbose      If True, report progress
#'
#' @return  A dgCMatrix or quanteda dfm
#' @export
term_intersect <- function(dtm, simmat, as_dfm=T, verbose=F) {
  if (methods::is(dtm, "DocumentTermMatrix")) stop('this function does not work for tm DocumentTermMatrix class')
  #simmat = match_simmat_terms(dtm, simmat)
  dtm = pad_dfm(dtm, colnames(simmat))
  
  parentheses = grepl('[&|]', colnames(dtm))
  ml = term_intersect_cpp(dtm, simmat, colnames(dtm), parentheses, verbose)
  colnames(ml$m) = ml$colnames
  rownames(ml$m) = rownames(dtm)
  ml$m = ml$m[,Matrix::colSums(ml$m) > 0]
  
  if (as_dfm && methods::is(dtm, 'dfm')) {
    m = quanteda::as.dfm(ml$m > 0)
    quanteda::docvars(m) = quanteda::docvars(dtm)
    return(dtm)
  } else {
    return(ml$m > 0)
  }
}

term_occur_sim <- function(m, min_cos, verbose=F) {
  simmat = tcrossprod_sparse(t(m), min_value = min_cos, normalize='l2', verbose=verbose) > 0
  methods::as(simmat, 'dgCMatrix')
}

## create a matrix with document probabilities (docfreq / n) for all column combinations
## max_docfreq is used to only keep sufficiently rare combinations
## typically, min_docfreq is used to drop very sparse terms, and max_docfreq is used to drop terms that are too common to be informative.
term_cooccurence_docprob <- function(m, max_docfreq, min_docfreq=NULL, min_obs_exp=NA, verbose=F) {
  simmat = tcrossprod_sparse(methods::as(t(m > 0), 'dgCMatrix'), min_value=min_docfreq, max_value = max_docfreq, verbose=verbose)
  
  if (!is.na(min_obs_exp)) {
    simmat = methods::as(simmat, 'dgTMatrix')
    prob = Matrix::colMeans(m > 0)
    exp = prob[simmat@i+1] * prob[simmat@j+1] * nrow(m)
    simmat@x[(simmat@x / exp) < min_obs_exp] = 0
    simmat = Matrix::drop0(simmat)
  }
  
  methods::as(simmat, 'dgCMatrix')
}

## if the docfreq of a term is lower than max_docfreq
## its combinations with other terms are ignored. This allows us to only include combinations
## for terms that are not informative enough on their own
rm_comb_if_diag <- function(simmat) {
  d = diag(simmat)
  has_diag = d > 0
  if (any(has_diag)) {
    simmat[,has_diag] = 0
    simmat[has_diag,] = 0
    simmat = Matrix::drop0(simmat)
    diag(simmat) = d
  }
  simmat
}

char_grams <- function(x, type=c('tri','bi'), pad=T, drop_non_alpha=T, min_length=3) {
  type = match.arg(type)
  voc = x
  if (!pad && type == 'tri' && min_length < 3) stop('cannot use trigrams if length < 3 and pad = F')
  if (!pad && type == 'bi' && min_length < 2) stop('cannot use bigrams if length < 3 and pad = F')
  if (drop_non_alpha) x[!grepl('[a-zA-Z]', x)] = ''
  uni = stringi::stri_split_boundaries(x, type='character')
  uni = lapply(uni, FUN=function(x) {
    if (length(x) < min_length) return(c())
    if (pad) {
      if (type == 'bi') return(paste(c('lb', x), c(x, 'rb'), sep='_'))
      if (type == 'tri') return(paste(c('lb','lb', x), c('lb',x,'rb'), c(x, 'rb','rb'), sep='_'))
    } else {
      if (type == 'bi') return(paste(c(x[-1]), x[-length(x)], sep='_'))
      if (type == 'tri') return(paste(x[-(1:2)], x[-length(x)][-1], x[-(length(x) - c(1,0))], sep='_'))
    }
  })
  n = sapply(uni, length)
  bi = data.frame(bigram=unlist(uni), i = rep(1:length(uni), times=n))
  bi_voc = unique(bi$bigram)
  bi = Matrix::spMatrix(nrow = length(x), ncol = length(bi_voc), 
                   i = bi$i, j = match(bi$bigram, bi_voc), x = rep(1, nrow(bi)))
  rownames(bi) = voc
  methods::as(bi, 'dgCMatrix')
}


#' Find terms with similar spelling
#'
#' A quick, language agnostic way for finding terms with similar spelling. 
#' Calculates similarity as percentage of a terms bigram's or trigram's that also occur in the other term. 
#' The percentage has to be above the given threshold for both terms (unless allow_asym = T)  
#'
#' @param voc            A character vector that gives the vocabulary (e.g., colnames of a dtm)
#' @param type           Either "bi" (bigrams) or "tri" (trigrams)
#' @param min_overlap    The minimal overlap percentage. Works together with max_diff to determine required overlap
#' @param max_diff       The maximum number of bi/tri-grams that is different
#' @param pad            If True, pad the left size (ls) and right side (rs) of bi/tri-grams. So, trigrams for "pad" would be: "ls_ls_p", "ls_p_a", "p_a_d", "a_d_rs", "d_rs_rs".
#' @param as_lower       If True, ignore case
#' @param same_start     Should terms start with the same character(s)? Given as a number for the number of same characters. (also greatly speeds up calculation)
#' @param drop_non_alpha If True, ignore non alpha terms (e.g., numbers, punctuation). They will appear in the output matrix, but only with zeros.
#' @param min_length     The minimum number of characters in a term. Terms with fewer characters are ignored. They will appear in the output matrix, but only with zeros.
#' @param allow_asym     If True, the match only needs to be true for at least one term. In practice, this means that "America" would match perfectly with "Southern-America".
#' @param verbose        If True, report progress
#'
#' @return  A similarity matrix in the dgCMatrix format
#' @export
#'
#' @examples
#' dfm = quanteda::dfm(c('That guy Gadaffi','Do you mean Kadaffi?',
#'                       'Nah more like Gadaffel','What Gargamel?'))
#' simmat = term_char_sim(colnames(dfm), same_start=0)
#' term_union(dfm, simmat, verbose = FALSE)
term_char_sim <- function(voc, type=c('tri','bi'), min_overlap=2/3, max_diff=4, pad=F, as_lower=T, same_start=1, drop_non_alpha=T, min_length=5, allow_asym=F, verbose=T) {
  type = match.arg(type)
  if (!methods::is(voc, 'character')) stop('voc must be a character vector')
  if (as_lower) voc = tolower(voc)
  m = char_grams(voc, type=type, pad=pad, drop_non_alpha = drop_non_alpha, min_length=min_length)  ## sparse matrix of bigrams
  
  max_diff_pct = (Matrix::rowSums(m) - max_diff) / Matrix::rowSums(m)
  min_overlap = ifelse(min_overlap < max_diff_pct, max_diff_pct, min_overlap)
  if (same_start > 0) {
    group = substr(rownames(m), start = 0, stop = same_start)
    simmat = tcrossprod_sparse(m, rowsum_div = T, group = group, crossfun = 'min', diag=F, min_value=min_overlap, verbose=verbose)
  } else {
    simmat = tcrossprod_sparse(m, rowsum_div = T, crossfun = 'min', diag=F, min_value=min_overlap, verbose=verbose)
  }
  if (!allow_asym) simmat = tril(simmat>0) * tril(t(simmat>0)) ## both need to match, because otherwise 
  diag(simmat) = 1
  methods::as(simmat, 'dgCMatrix')
}


get_doc_terms <- function(dtm, docname) {
  r = dtm[quanteda::docnames(dtm) == docname]
  if (nrow(r) == 0) stop('docname is not a document in dtm')
  cs = colSums(r)
  cs[cs > 0]
}

get_overlap_terms <- function(dtm, doc.x, doc.y, dtm.y=dtm) {
  tx = get_doc_terms(dtm, doc.x)
  ty = get_doc_terms(dtm.y, doc.y)
  intersect(names(tx), names(ty))
}
