%% S3 - Model Training & Cross-Validation
%
% This script executes Phase 3: Building a multivariate model to predict 
% pain intensity from fMRI features.
%
% Steps:
%   1. Load model-ready data (X and y).
%   2. Initialize the ModelTrainer with Leave-One-Subject-Out (LOSO) CV.
%   3. Train the model and calculate performance stats.
%   4. Save the results and final model weights.

clear; clc;
addpath(genpath('../functions'));

%% 1. Load Data
load('../results/model_ready_data.mat'); % Loads X_hrf, y_hrf, meta_hrf

%% 2. Initialize Trainer
% I chose LOSO-CV as it is the gold standard for verifying that an 
% fMRI model generalizes to new individuals.
trainer = ModelTrainer('LOSO');

%% 3. Run Cross-Validation
% Here, the HRF-based activation features are used for prediction.
[stats, cv_results] = trainer.run_cross_validation(X_hrf, y_hrf, meta_hrf);

fprintf('\n--- Prediction Performance ---\n');
fprintf('Correlation (r): %.3f\n', stats.r_corr);
fprintf('RMSE: %.3f\n', stats.rmse);

%% 4. Extract Final Model
% Training on the full dataset to obtain the final "Neural Signature" weights.
trainer.train_final_model(X_hrf, y_hrf);
model_weights = trainer.ModelWeights;

%% 5. Save Results
save('../results/final_model_results.mat', 'stats', 'cv_results', 'model_weights');
fprintf('\nResults saved to results/final_model_results.mat\n');
