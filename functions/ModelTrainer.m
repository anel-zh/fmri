classdef ModelTrainer < handle
    % MODELTRAINER - Handles cross-validated predictive modeling for fMRI
    %
    % This class implements regularized regression (Lasso/Elastic Net)
    % with Group-based Cross-Validation to predict continuous variables 
    % (e.g., pain ratings) from brain features.
    %
    % Author: Anel Zhunussova

    properties
        Alpha = 1           % 1 for Lasso, ~0.5 for Elastic Net
        CVFolds             % Number of folds or 'LOSO'
        ModelWeights        % Coefficients from the trained model
        Intercept           % Model intercept
    end

    methods
        function obj = ModelTrainer(cv_type)
            % Constructor: Sets the cross-validation strategy
            obj.CVFolds = cv_type;
        end

        function [stats, results] = run_cross_validation(obj, X, y, metadata)
            % Executes Group-based Cross-Validation to assess generalization.
            % Metadata is used to ensure all samples from one subject 
            % stay within the same fold, preventing data leakage.

            subs = unique(metadata.sub_id);
            n_subs = numel(subs);
            
            predictions = zeros(size(y));
            fprintf('Starting %s Cross-Validation for %d subjects...\n', obj.CVFolds, n_subs);

            for i = 1:n_subs
                % Define Test set (Current Subject) and Training set (All others)
                test_idx = strcmp(metadata.sub_id, subs{i});
                train_idx = ~test_idx;

                X_train = X(train_idx, :);
                y_train = y(train_idx);
                X_test  = X(test_idx, :);

                % I use Lasso with internal CV to find the optimal Lambda
                [B, FitInfo] = lasso(X_train, y_train, 'Alpha', obj.Alpha, 'CV', 5);
                
                % Select weights at the minimum expected deviance
                idx_min = FitInfo.IndexMinMSE;
                current_weights = B(:, idx_min);
                current_intercept = FitInfo.Intercept(idx_min);

                % Predict on the held-out subject
                predictions(test_idx) = (X_test * current_weights) + current_intercept;
                
                fprintf('Processed Subject %d/%d\n', i, n_subs);
            end

            % Compute performance metrics
            results.actual = y;
            results.predicted = predictions;
            stats = obj.calculate_stats(y, predictions);
        end

        function train_final_model(obj, X, y)
            % Trains the final model on the full dataset to extract weights.
            fprintf('Training final model on full dataset...\n');
            [B, FitInfo] = lasso(X, y, 'Alpha', obj.Alpha, 'CV', 5);
            
            obj.ModelWeights = B(:, FitInfo.IndexMinMSE);
            obj.Intercept = FitInfo.Intercept(FitInfo.IndexMinMSE);
        end
    end

    methods (Access = private)
        function stats = calculate_stats(~, actual, predicted)
            % Helper to compute standard regression metrics
            stats.rmse = sqrt(mean((actual - predicted).^2));
            stats.mae  = mean(abs(actual - predicted));
            r_mat = corrcoef(actual, predicted);
            stats.r_corr = r_mat(1,2);
            stats.r_squared = stats.r_corr^2;
        end
    end
end
