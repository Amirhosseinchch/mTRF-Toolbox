function model = mTRFmultitrain(stim,resp1,resp2,fs,dir,tmin,tmax,lambda,varargin)
%MTRFMULTITRAIN  mTRF model training for multisensory additive models.
%   MODEL = MTRFMULTITRAIN(STIM,RESP1,RESP2,FS,DIR,TMIN,TMAX,LAMBDA) trains
%   a forward encoding model (stimulus to neural response) or a backward
%   decoding model (neural response to stimulus) using time-lagged input
%   features for building a model of multisensory processing. Models are
%   trained on the sum of the unisensory responses RESP1 and RESP2 (i.e.,
%   the additive model of multisensory processing), as per Crosse et al.
%   (2015). Pass in 1 for DIR to fit a forward model, or -1 to fit a
%   backward model. STIM, RESP1 and RESP2 are matrices or cell arrays
%   containing corresponding trials of continuous training data. FS is a
%   scalar specifying the sample rate in Hertz, and TMIN and TMAX are
%   scalars specifying the minimum and maximum time lags in milliseconds.
%   For backward models, MTRFMULTITRAIN automatically reverses the time
%   lags. LAMBDA is a scalar specifying the regularization parameter for
%   controlling overfitting.
%
%   MTRFMULTITRAIN returns the additive model in a structure with the
%   following fields:
%       'w'         -- normalized model weights (xvar-by-nlag-by-yvar)
%       'b'         -- normalized bias term (1-by-nlag-by-yvar)
%       't'         -- time lags (ms)
%       'fs'        -- sample rate (Hz)
%       'dir'       -- direction of causality (forward=1, backward=-1)
%       'type'      -- type of model (multi-lag, single-lag)
%
%   MTRFMULTITRAIN normalizes the model weights and regularization matrix
%   by the sampling interval (1/FS) to produce consistent scaling and
%   smoothing of the weights across different sample rates (Lalor et al.,
%   2006).
%
%   If STIM, RESP1 or RESP2 are matrices, it is assumed that the rows
%   correspond to observations and the columns to variables, unless
%   otherwise stated via the 'dim' parameter (see below). If they are
%   vectors, it is assumed that the first non-singleton dimension
%   orresponds to observations. STIM, RESP1 and RESP2 must have the same
%   number of observations.
%
%   If STIM, RESP1 or RESP2 are cell arrays containing multiple trials, the
%   covariance matrices of each trial are summed to produce one model.
%   STIM, RESP1 and RESP2 must contain the same number of trials.
%
%   [...] = MTRFMULTITRAIN(...,'PARAM1',VAL1,'PARAM2',VAL2,...) specifies
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
%
%   See mTRFdemos for examples of use.
%
%   See also MTRFPREDICT, MTRFTRANSFORM, MTRFMULTICROSSVAL.
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
%      [3] Lalor EC, Pearlmutter BA, Reilly RB, McDarby G, Foxe JJ (2006)
%          The VESPA: a method for the rapid estimation of a visual evoked
%          potential. NeuroImage 32:1549-1561.

%   Authors: Mick Crosse, Giovanni Di Liberto, Nate Zuk, Edmund Lalor
%   Contact: mickcrosse@gmail.com, edmundlalor@gmail.com
%   Lalor Lab, Trinity College Dublin, IRELAND
%   Apr 2014; Last revision: 05-Feb-2020

% Parse input arguments
arg = parsevarargin(varargin);

% Validate input parameters
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
    x = stim;
elseif dir == -1
    y = stim;
    [tmin,tmax] = deal(tmax,tmin);
else
    error('DIR argument must have a value of 1 or -1.')
end

% Format data in cell arrays
[z1,zobs1,zvar1] = formatcells(resp1,arg.dim);
[z2,zobs2,zvar2] = formatcells(resp2,arg.dim);
if dir == 1
    [x,xobs,xvar] = formatcells(x,arg.dim);
    if ~isequal(zvar1,zvar2)
        error(['RESP1 and RESP2 arguments must have the same number of '...
            'variables.'])
    else
        yvar = zvar1;
    end
elseif dir == -1
    [y,yobs,yvar] = formatcells(y,arg.dim);
    if ~isequal(zvar1,zvar2)
        error(['RESP1 and RESP2 arguments must have the same number of '...
            'variables.'])
    else
        xvar = zvar1;
    end
end

% Check equal number of observations
if dir == 1
    if ~isequal(xobs,zobs1,zobs2)
        error(['STIM and RESP arguments must have the same number of '...
            'observations.'])
    end
elseif dir == -1
    if ~isequal(yobs,zobs1,zobs2)
        error(['STIM and RESP arguments must have the same number of '...
            'observations.'])
    end
end

% Convert time lags to samples
tmin = floor(tmin/1e3*fs*dir);
tmax = ceil(tmax/1e3*fs*dir);
lags = tmin:tmax;

% Compute sampling interval
delta = 1/fs;

% Get dimensions
nlag = numel(lags);
if dir == 1
    xvar = unique(xvar);
elseif dir == -1
    yvar = unique(yvar);
end
switch arg.type
    case 'multi'
        mvar = xvar*nlag+1;
    case 'single'
        mvar = xvar+1;
end

% Compute covariance matrices
if dir == 1
    [Cxx,Cxy1,Cxy2] = mlscovmat(x,z1,z2,lags,arg.type,arg.split,arg.zeropad);
elseif dir == -1
    [Cxx1,Cxy1] = olscovmat(z1,y,lags,arg.type,arg.split,arg.zeropad);
    [Cxx2,Cxy2] = olscovmat(z2,y,lags,arg.type,arg.split,arg.zeropad);
end

% Compute covariances for additive model
if dir == 1
    Cxx = Cxx + Cxx;
    Cxy = Cxy1 + Cxy2;
elseif dir == -1
    Cxx = Cxx1 + Cxx2;
    Cxy = Cxy1 + Cxy2;
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
        lambda = 0;
end
M = lambda*M/delta;

% Fit additive linear model
switch arg.type
    case 'multi'
        w = (Cxx + M)\Cxy/delta;
    case 'single'
        w = zeros(xvar+1,nlag,yvar);
        for i = 1:nlag
            w(:,i,:) = (Cxx(:,:,i) + M)\Cxy(:,:,i)/delta;
        end
end

% Account for superposition
w = w*2;

% Format output arguments
model = struct('w',reshape(w(2:end,:,:),[xvar,nlag,yvar]),'b',w(1,:,:),...
    't',lags/fs*1e3,'fs',fs,'dir',dir,'type',arg.type);