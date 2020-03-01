function single_lag_analysis
%SINGLE_LAG_ANALYSIS  Single-lag analysis example.
%   SINGLE_LAG_ANALYSIS loads an example dataset and trains a set of
%   single-lag neural decoders that reconstruct stimulus features (speech
%   envelope) from 2 minutes of 128-channel EEG data as per O'Sullivan et
%   al (2015).
%
%   Example data is loaded from SPEECH_DATA.MAT and consists of the
%   following variables:
%       'stim'      a vector containing the speech spectrogram, obtained by
%                   band-pass filtering the speech signal into 128
%                   logarithmically spaced frequency bands between 100
%                   and 4000Hz, taking the Hilbert transform at each band
%                   and averaging over every 8 neighbouring bands.
%       'resp'      a matrix containing 2 minutes of 128-channel EEG data
%                   filtered between 0.5 and 15 Hz
%       'fs'        the sample rate of STIM and RESP (128Hz)
%       'factor'    the BioSemi EEG normalization factor for converting the
%                   TRF to microvolts (524.288mV / 2^24bits)
%
%   mTRF-Toolbox https://github.com/mickcrosse/mTRF-Toolbox

%   References:
%      [1] O'Sullivan JA, Power AJ, Mesgarani N, Rajaram S, Foxe JJ, Shinn-
%          Cunningham BG, Slaney M, Shamma SA, Lalor EC (2015) Attentional
%          Selection in a Cocktail Party Environment Can Be Decoded from
%          Single-Trial EEG. Cereb Cortex 25(7):1697-1706.

%   Authors: Mick Crosse <mickcrosse@gmail.com>
%   Copyright 2014-2020 Lalor Lab, Trinity College Dublin.

% Load data
load('data/speech_data.mat','stim','resp','fs');

% Normalize data
stim = sum(stim,2);
resp = resp/std(resp(:));

% Downsample data
fsNew = 64;
stim = resample(stim,fsNew,fs);
resp = resample(resp,fsNew,fs);
fs = fsNew;

% ---Create training/test sets---

% Define cross-validation folds
nfold = 10;
batch = ceil(size(stim,1)/nfold);

% Training set
stimtrain = cell(nfold,1);
resptrain = cell(nfold,1);
for i = 1:nfold
    idx = batch*(i-1)+1:min(batch*i,size(resp,1));
    stimtrain{i} = stim(idx,:);
    resptrain{i} = resp(idx,:);
end

% ---Cross-validation---

% Model hyperparameters
dir = -1;
tmin = 0;
tmax = 1000;
lambda = 10.^-2;

% Run single-lag cross-validation
[stats,t] = mTRFcrossval(stimtrain,resptrain,fs,dir,tmin,tmax,...
    lambda,'type','single','zeropad',0);

% Compute mean and variance
macc = squeeze(mean(stats.acc))';
vacc = squeeze(var(stats.acc))';
merr = squeeze(mean(stats.err))';
verr = squeeze(var(stats.err))';

% Compute variance bound
xacc = [-fliplr(t),-t];
xerr = [-fliplr(t),-t];
yacc = [fliplr(macc-sqrt(vacc/nfold)),macc+sqrt(vacc/nfold)];
yerr = [fliplr(merr-sqrt(verr/nfold)),merr+sqrt(verr/nfold)];

% Plot accuracy
figure
subplot(1,2,1)
h = fill(xacc,yacc,'b','edgecolor','none'); hold on
set(h,'facealpha',0.2), xlim([tmin,tmax])
plot(-fliplr(t),fliplr(macc),'linewidth',2), hold off
title('Reconstruction Accuracy')
xlabel('Time lag (ms)')
ylabel('Correlation')
axis square, grid on

% Plot error
subplot(1,2,2)
h = fill(xerr,yerr,'b','edgecolor','none'); hold on
set(h,'facealpha',0.2), xlim([tmin,tmax])
plot(-fliplr(t),fliplr(merr),'linewidth',2), hold off
title('Reconstruction Error')
xlabel('Time lag (ms)')
ylabel('MSE')
axis square, grid on