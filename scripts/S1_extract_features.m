%% S1 - Feature Extraction Pipeline
%
% This script executes Phase 1 of the analysis: transforming raw fMRI BOLD 
% signals into neural features.
%
% Steps:
%   1. Load the study configuration (Paths, TR, Binning settings).
%   2. Initialize the FMRIFeatureExtractor engine.
%   3. Run Dynamic Connectivity (DCC) and HRF Activation extraction.
%
% Author: Anel Zhunussova

%% 1. Environment Setup
clear; clc;

% Add project folders to path to ensure classes and functions are visible
addpath(genpath('../functions'));
addpath(genpath('../config'));

%% 2. Load Configuration
% Here, the capsaicin-specific settings are loaded into a PipelineConfig object.
example_capsaicin_config; 

%% 3. Initialize Extraction Engine
% The extractor is initialized using the cfg object. This ensures all 
% subsequent processing adheres to the specified TR and Atlas settings.
extractor = FMRIFeatureExtractor(cfg);

%% 4. Execute Extraction
% The pipeline is configured to extract both connectivity and activation 
% features. 'ApplyDurationCut' is enabled to account for the non-stationary 
% nature of the capsaicin sustained pain paradigm.

fprintf('Starting Feature Extraction for: %s\n', cfg.StudyName);

extractor.run_extraction(...
    'Runs', {'task', 'baseline'}, ...
    'Methods', {'roi_dcc', 'hrf_beta'}, ...
    'ApplyDurationCut', true ...
);

fprintf('Phase 1 Complete. Features are saved in: %s\n', cfg.ResultsDir);
