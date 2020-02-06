function model = mTRFtrain(stim,resp,fs,dir,tmin,tmax,lambda,varargin)
%MTRFTRAIN  mTRF-Toolbox model training.
%   MODEL = MTRFTRAIN(STIM,RESP,FS,DIR,TMIN,TMAX,LAMBDA) trains a forward
%   encoding model (stimulus to neural response) or a backward decoding
%   model (neural response to stimulus) using time-lagged input features.
%   Pass in 1 for DIR to fit a forward model, or -1 to fit a backward
%   model. STIM and RESP are matrices or cell arrays containing
%   corresponding trials of continuous training data. FS is a scalar
%   specifying the sample rate in Hertz, and TMIN and TMAX are scalars
%   specifying the minimum and maximum time lags in milliseconds. For
%   backward models, MTRFTRAIN automatically reverses the time lags. LAMBDA
%   is a scalar specifying the regularization parameter for controlling
%   overfitting.
%
%   MTRFTRAIN returns a structure with the following fields:
%       'w'         -- normalized model weights (xvar-by-nlag-by-yvar)
%       'b'         -- normalized bias term (1-by-nlag-by-yvar)
%       't'         -- time lags (ms)
%       'fs'        -- sample rate (Hz)
%       'dir'       -- direction of causality (forward=1, backward=-1)
%       'type'      -- model type (multi-lag, single-lag)
%
%   MTRFTRAIN normalizes the model weights and regularization matrix by the
%   sampling interval (1/FS) to produce consistent scaling and smoothing of
%   the weights across different sample rates (Lalor et al., 2006).
%
%   If STIM or RESP are matrices, it is assumed that the rows correspond to
%   observations and the columns to variables, unless otherwise stated via
%   the 'dim' parameter (see below). If they are vectors, it is assumed
%   that the first non-singleton dimension corresponds to observations.
%   STIM and RESP must have the same number of observations.
%
%   If STIM and RESP are cell arrays containing multiple trials, the
%   covariance matrices of each trial are summed to produce one model. STIM
%   and RESP must contain the same number of trials.
%
%   MODEL = MTRFTRAIN(...,'PARAM1',VAL1,'PARAM2',VAL2,...) specifies
%   additional parameters and their values. Valid parameters are the
%   following:
%
%       Parameter   Value
%       'dim'       A scalar specifying the dimension to work along: pass
%                   in 1 to work along the columns (default), or 2 to work
%                   along the rows. Applies to both STIM and RESP.
%       'method'    A string specifying the regularization method to use:
%                       'ridge'     ridge regression (default): suitable
%                                   for multivariate input features
%                       'Tikhonov'  Tikhonov regularization: dampens fast
%                                   oscillatory components of the weights
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
%
%   See mTRFdemos for examples of use.
%
%   See also MTRFPREDICT, MTRFTRANSFORM, MTRFCROSSVAL.
%
%   mTRF-Toolbox https://github.com/mickcrosse/mTRF-Toolbox

%   References:
%      [1] Crosse MC, Di Liberto GM, Bednar A, Lalor EC (2016) The
%          multivariate temporal response function (mTRF) toolbox: a MATLAB
%          toolbox for relating neural signals to continuous stimuli. Front
%          Hum Neurosci 10:604.
%      [2] Lalor EC, Pearlmutter BA, Reilly RB, McDarby G, Foxe JJ (2006)
%          The VESPA: a method for the rapid estimation of a visual evoked
%          potential. NeuroImage 32:1549-1561.

%   Authors: Mick Crosse, Giovanni Di Liberto, Nate Zuk, Edmund Lalor
%   Contact: mickcrosse@gmail.com, edmundlalor@gmail.com
%   Lalor Lab, Trinity College Dublin, IRELAND
%   Apr 2014; Last revision: 05-Feb-2020

% Parse input arguments
arg = parsevarargin(varargin);

% Validate parameter values
if ~isnumeric(fs) || ~isscalar(fs) || fs <= 0
    error('FS argument must be a positive numeric scalar.')
elseif ~isnumeric([tmin,tmax]) || ~isscalar(tmin) || ~isscalar(tmax)
    error('TMIN and TMAX arguments must be numeric scalars.')
elseif tmin > tmax
    error('The value of TMIN must be less than that of TMAX.')
elseif ~isnumeric(lambda) || ~isscalar(lambda) || lambda < 0
    error('LAMBDA argument must be a positive numeric scalar.')
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

% Format data in cells column-wise
[x,xobs,xvar] = formatcells(x,arg.dim);
[y,yobs,yvar] = formatcells(y,arg.dim);

% Check equal number of observations
if ~isequal(xobs,yobs)
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
nlag = numel(lags);
xvar = unique(xvar);
yvar = unique(yvar);
switch arg.type
    case 'multi'
        mvar = xvar*nlag+1;
    case 'single'
        mvar = xvar+1;
end

% Compute covariance matrices
[Cxx,Cxy] = olscovmat(x,y,lags,arg.type,arg.split,arg.zeropad);

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
        lambda = 0;
end
M = lambda*M/delta;

% Fit model
switch arg.type
    case 'multi'
        w = (Cxx + M)\Cxy;
    case 'single'
        w = zeros(xvar+1,nlag,yvar);
        for i = 1:nlag
            w(:,i,:) = (Cxx(:,:,i) + M)\Cxy(:,:,i);
        end
end

% Normalize weights by sampling interval
w = w/delta;

% Format output arguments
model = struct('w',reshape(w(2:end,:,:),[xvar,nlag,yvar]),'b',w(1,:,:),...
    't',lags/fs*1e3,'fs',fs,'dir',dir,'type',arg.type);