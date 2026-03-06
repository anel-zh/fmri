%% S4 - Evaluation and Visualization
%
% This script executes the final phase: interpreting the trained model.
%
% Steps:
%   1. Load CV results and final model weights.
%   2. Visualize Actual vs. Predicted pain scores.
%   3. Identify and plot the most predictive brain regions.

clear; clc;
addpath(genpath('../functions'));

%% 1. Load Results
load('../results/final_model_results.mat'); % loads 'stats', 'cv_results', 'model_weights'
example_capsaicin_config; % To get Atlas/Study metadata

%% 2. Initialize Visualizer
viz = ResultVisualizer();

%% 3. Plot Performance
% Generate the regression scatter plot
viz.plot_prediction_scatter(stats, cv_results, cfg.StudyName);
saveas(gcf, '../results/actual_vs_predicted.png');

%% 4. Interpret Features
% Create dummy labels for ROIs if a label file isn't provided
% In a real project, these would be loaded from the Atlas metadata
n_rois = length(model_weights);
labels = arrayfun(@(x) sprintf('Region %d', x), 1:n_rois, 'UniformOutput', false);

% Visualize the top 15 most important regions
viz.plot_roi_importance(model_weights, labels, 15);
saveas(gcf, '../results/roi_importance.png');

fprintf('Analysis complete. Figures saved to the results folder.\n');
