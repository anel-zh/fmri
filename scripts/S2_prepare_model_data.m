%% S2 - Data Preparation & Aggregation
%
% This script aggregates individual subject features into a single dataset
% ready for machine learning.
%
% Steps:
%   1. Load Configuration and extracted results.
%   2. Align brain features (X) with pain ratings (y).
%   3. Save the aggregated dataset for Phase 3 (Modeling).

clear; clc;
addpath(genpath('../functions'));
addpath(genpath('../config'));

% 1. Setup
example_capsaicin_config; 

% 2. Load Pain Ratings
% In this example, we assume ratings are stored in a pre-processed .mat file.
% For a portfolio, you could also load this from a CSV.
load(fullfile(cfg.BaseDir, 'data', 'capsaicin_ratings.mat')); % loads 'pain_scores'

% 3. Assemble HRF Activation Dataset
[X_hrf, y_hrf, meta_hrf] = DataAssembler(cfg, 'hrf_beta', pain_scores);

% 4. Assemble Connectivity Dataset (Optional)
[X_dcc, y_dcc, meta_dcc] = DataAssembler(cfg, 'dcc', pain_scores);

% 5. Save Model-Ready Data
% Saving into the results directory to keep the project organized.
save_path = fullfile(cfg.ResultsDir, 'model_ready_data.mat');
save(save_path, 'X_hrf', 'y_hrf', 'meta_hrf', 'X_dcc', 'y_dcc', 'meta_dcc');

fprintf('Data prepared and saved to: %s\n', save_path);
