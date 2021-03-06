#' @importFrom Rcpp evalCpp
#' @useDynLib uca, .registration = TRUE
NULL


#' center
#' 
#' Convenient function to center the data, rather than typing `scale' or `sweep`
#' 
#' @param X a matrix
#' @return centered data matrix X
#' @export
#' 
center_f <- function(X){
  column_means <- colMeans(X)
  return(sweep(X, 2, column_means, "-"))
}

#' broken_PCA
#' 
#' calculate SVD of a product of matrices by using svd and QR decompositions
#' 
#' @param left left side of a product
#' @param right right side of a product
#' @param nv number of unique components
#' @return top nv eigenvalues and associated eigenvectors
#' 
broken_svd_R = function(left, right, nv){
  svd_right <- svd(right,nv = 0)
  qr_left_U <- qr(left %*% svd_right$u)
  
  RS_svd <- arma_svd( t(t(qr.R(qr_left_U)) * svd_right$d))
  u = qr.Q(qr_left_U) %*% RS_svd$u
  
  eigenvalues <- colSums(u * (left %*% (right %*% u))) #calculates diag(crossprod(u, left) %*% (right %*%u))
  top_eig_vals <- order(eigenvalues, decreasing = T)[1:nv]
  list(values = eigenvalues[top_eig_vals],
       vectors = u[,top_eig_vals])
}


#' bisection2
#' 
#' compute the UCA for single background using SVD and QR. good for bigger data where loading the covariance matrix is difficult
#' 
#' @param A a n1xp data matrix
#' @param B a n2xp data matrix
#' @param limit upperbound for the lagrange multiplier.
#' @param maxit maximum iterations
#' @param tol tolerance for convergence criteria
#' @return list of tau, largest eigenvalue, and score
 
bisection2 = function(A, B, limit = 20L, maxit = 1E5L, tol = 1E-6){
  right <- rbind(A , B)
  svd_right <- arma_svd(right)
  t_A = t(A); 
  t_B = t(B);
  
  svd_right_check <- arma_svd(A)
  
  f_val <- vector(mode = "list", length = 2L)
  f_val[[1]] <- multiple_score_calc_cpp(left = t_A,
                                    right = A,
                                    right_u = svd_right_check$u,
                                    right_d = svd_right_check$d,
                                    tau = 0,
                                    B = B)
  og_upper_lim <- f_val[[2]]$tau <- limit
  
  if(f_val[[1]]$score >= 0){
    warning("Redundant Constraint: Lagrange Multiplier is negative. Setting lambda to 0 \n");
    return(f_val[[1]]);
  }else{
    
    for(iter in 1L:maxit){
      limit <- c(f_val[[1]]$tau, f_val[[2]]$tau)
      if( limit[2] - limit[1] < tol * limit[1]) break;
      if(iter == maxit) warning("maximum iteration reached: solution may not be optimal \n");
      
      lambda <- (0.5*sum(limit))
      tau_score = multiple_score_calc_cpp(left = cbind(t_A, -(lambda*t_B)),
                                      right = right,
                                      right_u = svd_right$u,
                                      right_d = svd_right$d,
                                      tau = lambda,
                                      B = B)
      
      if(tau_score$score < 0){
        f_val[[1]] = tau_score
      }else{
        f_val[[2]] = tau_score
      }
    }  

    if(round(tau_score$tau) == og_upper_lim){
      warning("Lagrange Multiplier is near upperbound. Consider increasing the upperbound.(default is 20)  \n")
    }
    return(f_val[[ which.min(abs(c(f_val[[1]]$score, f_val[[2]]$score))) ]]) 
  }
}



#' magic_eigen_multiple
#' 
#' Solve for the optimal lagrange multiplier for the jth background. used only when multiple backgrounds exist.
#' 
#' @param B_focus a nxp data matrix of the background we're solving lagrangian for
#' @param t_A precomputed A transpose
#' @param t_B precomputed B transpose
#' @param right precomputed right long matrix: rbind(A, B)
#' @param svd_right precomputed svd of right matrix
#' @param lambda a j dimensional vector with possible lagrange multipliers for each background data matrix
#' @param j the specific background you're solving for
#' @param limit upperbound for the lagrange multiplier.
#' @param maxit maximum iterations
#' @param tol tolerance for convergence criteria
#' @return list of tau, largest eigenvalue, and score
magic_eigen_multiple = function(B_focus, t_A, t_B, right, svd_right, lambda, j, limit = 20L, maxit = 1E5, tol = 1E-6){
  
  #constants that don't really change if focused on j-th background
  old_right <- t(do.call(cbind, c(list(t_A),  t_B[-j]))) #for some reason, faster than rbind due to memory allocation.
  lambda_B <- Map("*", -lambda, t_B)
  old_left <- do.call(cbind, c(list(t_A), lambda_B[-j]))
  svd_right_check <- arma_svd(old_right)

    #checking bounds 
  f_val <- vector(mode = "list", length = 2L)
  f_val[[1]] <- multiple_score_calc_cpp(left = old_left,
                                    right = old_right,
                                    right_u = svd_right_check$u,
                                    right_d = svd_right_check$d,
                                    tau = 0,
                                    B = B_focus)
  og_upper_lim <- f_val[[2]]$tau <- limit
  
  if(f_val[[1]]$score >= 0){
    warning("Redundant Constraint: Lagrange Multiplier is negative. Setting lambda to 0 \n");
    return(f_val[[1]]);
  }else{
    for(iter in 1:maxit){
      limit <- c(f_val[[1]]$tau, f_val[[2]]$tau)
      if( limit[2] - limit[1] < tol * limit[1]) break;
      if(iter == maxit) warning("maximum iteration reached: solution may not be optimal \n");
      
      lambda_B[[j]] = (-0.5*sum(limit)) * t_B[[j]]
      
      tau_score = multiple_score_calc_cpp(left = do.call(cbind, c(list(t_A), lambda_B)),
                                      right = right,
                                      right_u = svd_right$u,
                                      right_d = svd_right$d,
                                      tau = 0.5*sum(limit),
                                      B = B_focus )
      
      if(tau_score$score < 0){
       f_val[[1]] <- tau_score
      }else{
       f_val[[2]] <- tau_score
      }
  }
      if(round(tau_score$tau) == og_upper_lim){
        warning("Lagrange Multiplier is near upperbound. Consider increasing the upperbound.(default is 20) \n")
      }
      return(f_val[[ which.min(abs(c(f_val[[1]]$score, f_val[[2]]$score))) ]]) 
    }
}




#' bisection2.multiple
#' 
#' Solving for the unique components using SVD and QR in the instance of multiple backgrounds.
#' 
#' @param A  Target Data Matrix. n1 x p dimensions
#' @param B  List of k Background Data Matrix. n_k x p dimensions
#' @param lambda contrastive parameters if known. used to start algorithm. defaults to NULL
#' @param nv number of uca components to calculate
#' @param algo which algorithm to use. default algo == "bisection". If algo = "optim", L-BFGS-S optimization is used instead. algo== "optim" can improve speed
#' @param max_iter maximum number of iterations before giving up
#' @param tol convergence criteria for coordinate descent
#' @return list of tau, largest eigenvalue, and score
bisection2.multiple <- function(A, B, lambda=NULL, nv = 2L, max_iter=1E5L, tol = 1E-6, algo = "bisection", ...){
  
  #initialize starting point if one isn't supplied. greedy start
  if(length(lambda) == 0){
    #we use A and B here instead of divided b/c they divide in bisection2 function
    # do not initialize the first one since it just gets overwritten in step 1 of coordinate descent.
    lambda = sapply(seq_along(B), function(zz){optim_bfgs2(A, B[[zz]], ...)$tau})
  }
  
  t_A <- t(A)
  t_B <- lapply(B, t)
  right <- t(do.call(cbind, c(list(t_A), t_B)))
  svd_right <- arma_svd(right)
  
  score = Inf; 
  
  #coordinate descent
  if(algo == "bisection"){
    for(i in 1L:max_iter){
      old.score <- score
      for (j in seq_along(B)){
        #calculate the optimal lagrange multiplier for each background j
        bisection_j <- magic_eigen_multiple(B[[j]], t_A, t_B, right, svd_right, lambda, j, ...)
        lambda[j] <- bisection_j$tau
      }
      score <- sum(bisection_j$values, lambda)
      if( abs(old.score - score) < tol * abs(old.score)) break;
      #print(paste("iteration", i))
    }
  }else if(algo == "optim"){
    for(i in 1L:max_iter){
      old.score <- score
      for (j in seq_along(B)){
        #calculate the optimal lagrange multiplier for each background j
        bisection_j <- optim_bfgs_multiple(B[[j]], t_A, t_B, right, svd_right, lambda, j, ...)
        lambda[j] <- bisection_j$tau
      }
      score <- sum(bisection_j$values, lambda)
      if( abs(old.score - score) < tol * abs(old.score)) break;
      #print(paste("iteration", i))
    }
  }else{
    stop(paste("algo",algo," not recognized"))
  }
    left <- do.call(cbind, c(list(t_A), Map("*", -lambda, t_B)))
    final_res <- broken_svd_cpp(left, right, nv)
    
    return(list(values = final_res$values, vectors = final_res$vectors, tau = lambda))
}

