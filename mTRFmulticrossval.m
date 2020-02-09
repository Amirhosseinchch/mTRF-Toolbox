function [stats,t] = mTRFmulticrossval(stim,resp,resp1,resp2,fs,dir,tmin,tmax,lambda,varargin)
%MTRFMULTICROSSVAL  mTRF cross-validation for multisensory additive models.
%   STATS = MTRFMULTICROSSVAL(STIM,RESP,RESP1,RESP2,FS,DIR,TMIN,TMAX,LAMBDA)
%   cross validates a forward encoding model (stimulus to neural response)
%   or a backward decoding model (neural response to stimulus) over
%   multiple trials of data for a multisensory experiment. Models are
%   trained on the sum of the unisensory responses (additive model), and
%   validated on the multisensory responses as per Crosse et al. (2015).
%   Pass in 1 for DIR to validate a forward model, or -1 to validate a
%   backward model. STIM, RESP, RESP1 and RESP2 are cell arrays containing
%   corresponding trials of continuous data. RESP are the responses to the
%   multisensory condition, RESP1 are the responses to the first unisensory
%   condition and RESP2 the responses to the second unisensory condition.
%   FS is a scalar specifying the sample rate in Hertz, and TMIN  and TMAX
%   are scalars specifying the minimum and maximum time lags in
%   milliseconds. For backward models, MTRFMULTICROSSVAL automatically
%   reverses the time lags. LAMBDA is a scalar or vector of regularization
%   values to be validated and controls overfitting.
%
%   STATS = MTRFMULTICROSSVAL(...) returns the cross-validation statistics
%   in a structure with the following fields:
%       'r'         -- the correlation coefficients between the predicted
%                      and observed variables (ntrial-by-nlambda-by-yvar)
%       'p'         -- the probabilities of the correlation coefficients
%       'rmse'      -- the root-mean-square error between the predicted and
%                      observed variables (ntrial-by-nlambda-by-yvar)
%
%   MTRFMULTICROSSVAL performs a leave-one-out cross-validation over all
%   trials. To achieve a k-fold cross-validation, arrange STIM, RESP, RESP1
%   and RESP2 in k-by-1 cell arrays. The number of folds can also be
%   increased by an integer factor using the 'split' parameter (see below).
%
%   If STIM, RESP, RESP1 or RESP2 contain matrices, it is assumed that the
%   rows correspond to observations and the columns to variables, unless
%   otherwise stated via the 'dim' parameter (see below). If they contain
%   vectors, it is assumed that the first non-singleton dimension
%   corresponds to observations. Each trial of STIM, RESP, RESP1 or RESP2
%   must have the same number of observations.
%
%   [STATS,T] = MTRFMULTICROSSVAL(...) returns a vector containing the time
%   lags used in milliseconds. These data are useful for interpreting the
%   results of single-lag models.
%
%   [...] = MTRFMULTICROSSVAL(...,'PARAM1',VAL1,'PARAM2',VAL2,...)
%   specifies additional parameters and their values. Valid parameters are
%   the following:
%
%       Parameter   Value
%       'dim'       A scalar specifying the dimension to work along: pass
%                   in 1 to work along the columns (default), or 2 to work
%                   along the rows. Applies to both STIM and RESP.
%       'method'    A string specifying the regularization method to use:
%                       'ridge'     ridge regression (default): suitable
%                                   for multivariate input features
%                       'Tikhonov'  Tikhonov regularization: dampens fast
%                                   oscillatory components of the solution
%                                   but may cause cross-channel leakage for
%                                   multivariate input features
%                       'ols'       ordinary least squares: equivalent to
%                                   setting LAMBDA=0 (no regularization)
%       'type'      A string specifying type of model to fit:
%                       'multi'     use all lags simultaneously to fit a
%                                   multi-lag model (default)
%                       'single'    use each lag individually to fit
%                                   separate single-lag models
%       'split'     A scalar specifying the number of segments in which to
%                   split each trial of data when computing the covariance
%                   matrices. This is useful for reducing memory usage on
%                   large datasets. By default, the entire trial is used.
%       'zeropad'   A numeric or logical specifying whether to zero-pad the
%                   outer rows of the design matrix or delete them: pass in
%                   1 to zero-pad them (default), or 0 to delete them.
%       'fast'      A numeric or logical specifying whether to use the fast
%                   cross-validation method (requires more memory) or the
%                   slower method (requires less memory): pass in 1 to use
%                   the fast method (default) or 0 to use the slower
%                   method. Note, both methods are numerically equivalent.
%
%   Notes:
%   It is not recommended to use cross-validation as a way of testing model
%   performance. Models should be tested on separate, held-out data after
%   cross-validation using the mTRFpredict function.
%   Discontinuous trials of data should not be concatenated prior to cross-
%   validation as this will introduce artifacts in places where time lags
%   cross over trial boundaries. Each trial should be input as an
%   individual cell of continuous data and MTRFMULTICROSSVAL will zero-pad
%   the trial boundaries appropriately.
%
%   See mTRFdemos for examples of use.
%
%   See also MTRFTRAIN, MTRFPREDICT, MTRFTRANSFORM, MTRFAADCROSSVAL.
%
%   mTRF-Toolbox https://github.com/mickcrosse/mTRF-Toolbox

%   References:
%      [1] Crosse MC, Di Liberto GM, Bednar A, Lalor EC (2016) The
%          multivariate temporal response function (mTRF) toolbox: a MATLAB
%          toolbox for relating neural signals to continuous stimuli. Front
%          Hum Neurosci 10:604.
%      [2] Crosse MC, Butler JS, Lalor EC (2015) Congruent Visual Speech
%          Enhances Cortical Entrainment to Continuous Auditory Speech in
%          Noise-Free Conditions. J Neurosci 35(42):14195-14204.

%   Authors: Mick Crosse, Giovanni Di Liberto, Nate Zuk, Edmund Lalor
%   Contact: mickcrosse@gmail.com, edmundlalor@gmail.com
%   Lalor Lab, Trinity College Dublin, IRELAND
%   Jan 2020; Last revision: 08-Feb-2020

% Parse input arguments
arg = parsevarargin(varargin);

% Validate input parameters
if ~isnumeric(fs) || ~isscalar(fs) || fs <= 0
    error('FS argument must be a positive numeric scalar.')
elseif ~isnumeric([tmin,tmax]) || ~isscalar(tmin) || ~isscalar(tmax)
    error('TMIN and TMAX arguments must be numeric scalars.')
elseif tmin > tmax
    error('The value of TMIN must be less than that of TMAX.')
elseif ~isnumeric(lambda) || any(lambda < 0)
    error('LAMBDA argument must be positive numeric values.')
end

% Define X and Y variables
if dir == 1
    x = stim; y = resp;
elseif dir == -1
    x = resp; y = stim;
    [tmin,tmax] = deal(tmax,tmin);
else
    error('DIR argument must have a value of 1 or -1.')
end

% Format data in cell arrays
[x,xobs,xvar] = formatcells(x,arg.dim);
[y,yobs,yvar] = formatcells(y,arg.dim);
[z1,zobs1,~] = formatcells(resp1,arg.dim);
[z2,zobs2,~] = formatcells(resp2,arg.dim);

% Check equal number of observations
if ~isequal(xobs,yobs,zobs1,zobs2)
    error(['STIM and RESP arguments must have the same number of '...
        'observations.'])
end

% Convert time lags to samples
tmin = floor(tmin/1e3*fs*dir);
tmax = ceil(tmax/1e3*fs*dir);
lags = tmin:tmax;

% Compute sampling interval
delta = 1/fs;

% Get dimensions
xvar = unique(xvar);
yvar = unique(yvar);
switch arg.type
    case 'multi'
        mvar = xvar*numel(lags)+1;
        nlag = 1;
    case 'single'
        mvar = xvar+1;
        nlag = numel(lags);
end
ntrial = numel(x);
nbatch = ntrial*arg.split;
nlambda = numel(lambda);

% Compute unisensory covariance matrices
if dir == 1
    if arg.fast
        [CXX,CXY1,CXY2] = mlscovmat(x,z1,z2,lags,arg.type,arg.split,arg.zeropad,0);
    else
        [CXX,CXY1,CXY2] = mlscovmat(x,z1,z2,lags,arg.type,arg.split,arg.zeropad,1);
    end
elseif dir == -1
    if arg.fast
        [CXX1,CXY1] = olscovmat(z1,y,lags,arg.type,arg.split,arg.zeropad,0);
        [CXX2,CXY2] = olscovmat(z2,y,lags,arg.type,arg.split,arg.zeropad,0);
    else
        [CXX1,CXY1] = olscovmat(z1,y,lags,arg.type,arg.split,arg.zeropad,1);
        [CXX2,CXY2] = olscovmat(z2,y,lags,arg.type,arg.split,arg.zeropad,1);
    end
end

% Compute additive covariance matrices
if dir == 1
    if arg.fast
        for i = 1:nbatch
            CXX{i} = CXX{i} + CXX{i};
            CXY{i} = CXY1{i} + CXY2{i};
        end
    else
        CXX = CXX + CXX;
        CXY = CXY1 + CXY2;
    end
elseif dir == -1
    if arg.fast
        for i = 1:nbatch
            CXX{i} = CXX1{i} + CXX2{i};
            CXY{i} = CXY1{i} + CXY2{i};
        end
    else
        CXX = CXX1 + CXX2;
        CXY = CXY1 + CXY2;
    end
end

% Set up sparse regularization matrix
M = sparse(eye(mvar));
switch arg.method
    case 'ridge'
        M(1,1) = 0;
    case 'Tikhonov'
        M = M - 0.5*(diag(ones(mvar-1,1),1)+diag(ones(mvar-1,1),-1));
        M([mvar+2,end]) = 0.5;
        M([1,2,mvar+1]) = 0;
    case 'ols'
        lambda(:) = 0;
end
M = M/delta;

% Initialize performance variables
r = zeros(ntrial*arg.split,nlambda,yvar,nlag);
p = zeros(ntrial*arg.split,nlambda,yvar,nlag);
rmse = zeros(ntrial*arg.split,nlambda,yvar,nlag);

% Leave-one-out cross-validation
n = 0;
for i = 1:ntrial
    
    % Max segment size
    nseg = ceil(xobs(i)/arg.split);
    
    for j = 1:arg.split
        
        n = n+1;
        
        % Segment indices
        iseg = nseg*(j-1)+1:min(nseg*j,xobs(i));
        
        % Multisensory validation set
        [xlag,idx] = lagGen(x{i}(iseg,:),lags,arg.zeropad);
        xlag = [ones(numel(idx),1),xlag]; %#ok<*AGROW>
        
        if arg.fast % fast method
            
            % Unisensory training set
            idx = 1:nbatch; idx(n) = [];
            Cxx = 0; Cxy = 0;
            for k = idx
                Cxx = Cxx + CXX{k};
                Cxy = Cxy + CXY{k};
            end
            
        else % memory-efficient method
            
            % Unisensory left-out set
            [z1lag,idx] = lagGen(x{i}(iseg,:),lags,arg.zeropad);
            z1lag = [ones(numel(idx),1),z1lag];
            [z2lag,idx] = lagGen(x{i}(iseg,:),lags,arg.zeropad);
            z2lag = [ones(numel(idx),1),z2lag];
            
            % Unisensory training set
            Cxx = CXX - z1lag'*z1lag - z2lag'*z2lag;
            Cxy = CXY - z1lag'*y{i}(iseg(idx),:) - z2lag'*y{i}(iseg(idx),:);
            
        end
        
        % Remove zero-padded indices
        if ~arg.zeropad
            iseg = iseg(1+max(0,lags(end)):end+min(0,lags(1)));
        end
        
        for k = 1:nlambda
            
            switch arg.type
                
                case 'multi'
                    
                    % Fit additive linear model
                    w = (Cxx + lambda(k)*M)\Cxy;
                    
                    % Account for superposition
                    w = w*2;
                    
                    % Predict multisensory output
                    pred = xlag*w;
                    
                    % Measure performance
                    [rt,pt] = corr(y{i}(iseg,:),pred);
                    r(n,k,:) = diag(rt);
                    p(n,k,:) = diag(pt);
                    rmse(n,k,:) = sqrt(mean((y{i}(iseg,:) - pred).^2,1))';
                    
                case 'single'
                    
                    for l = 1:nlag
                        
                        % Fit additive linear model
                        w = (Cxx(:,:,l) + lambda(k)*M)\Cxy(:,:,l);
                        
                        % Account for superposition
                        w = w*2;
                        
                        % Predict multisensory output
                        ilag = [1,xvar*(l-1)+2:xvar*l+1];
                        pred = xlag(:,ilag)*w;
                        
                        % Measure performance
                        [rt,pt] = corr(y{i}(iseg,:),pred);
                        r(n,k,:,l) = diag(rt);
                        p(n,k,:,l) = diag(pt);
                        rmse(n,k,:,l) = sqrt(mean((y{i}(iseg,:) - ...
                            pred).^2,1))';
                        
                    end
                    
            end
            
        end
        
    end
    
end

% Format output arguments
stats = struct('r',r,'p',p,'rmse',rmse);
if nargout > 1
    t = lags/fs*1e3;
end