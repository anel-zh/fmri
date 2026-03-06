classdef ResultVisualizer < handle
    % RESULTVISUALIZER - Generates diagnostic and results plots for fMRI models
    %
    % This class provides methods to visualize model performance through 
    % scatter plots and to interpret model importance through ROI weight 
    % distributions.
    %
    % Author: Anel Zhunussova

    properties
        FigSettings = struct('FontSize', 12, 'LineWidth', 2, 'Colors', lines(7))
    end

    methods
        function plot_prediction_scatter(obj, stats, cv_results, study_name)
            % Generates a scatter plot of Actual vs. Predicted pain ratings.
            % Includes a regression line and performance metrics in the title.
            
            figure('Color', 'w', 'Name', 'Actual vs. Predicted');
            hold on;
            
            % Plot individual data points
            scatter(cv_results.actual, cv_results.predicted, 40, 'filled', ...
                'MarkerFaceAlpha', 0.6, 'MarkerFaceColor', obj.FigSettings.Colors(1, :));
            
            % Add the identity line (perfect prediction)
            min_val = min([cv_results.actual; cv_results.predicted]);
            max_val = max([cv_results.actual; cv_results.predicted]);
            plot([min_val max_val], [min_val max_val], 'k--', 'LineWidth', 1.5);
            
            % Add a linear trendline
            p = polyfit(cv_results.actual, cv_results.predicted, 1);
            plot(cv_results.actual, polyval(p, cv_results.actual), 'r', 'LineWidth', 2);
            
            xlabel('Actual Pain Rating');
            ylabel('Predicted Pain Rating');
            title(sprintf('%s\nr = %.3f | RMSE = %.3f', ...
                strrep(study_name, '_', ' '), stats.r_corr, stats.rmse));
            
            grid on;
            set(gca, 'FontSize', obj.FigSettings.FontSize);
        end

        function plot_roi_importance(obj, weights, atlas_labels, top_n)
            % Visualizes the most predictive ROI weights.
            % Useful for identifying the "Neural Signature" of the model.
            
            [sorted_w, idx] = sort(abs(weights), 'descend');
            top_idx = idx(1:top_n);
            
            figure('Color', 'w', 'Name', 'Top Predictive Regions');
            barh(weights(top_idx), 'FaceColor', obj.FigSettings.Colors(2, :));
            
            set(gca, 'YTick', 1:top_n, 'YTickLabel', atlas_labels(top_idx));
            set(gca, 'YDir', 'reverse');
            
            xlabel('Model Coefficient (Importance)');
            title(sprintf('Top %d Predictive Features', top_n));
            grid on;
            set(gca, 'FontSize', obj.FigSettings.FontSize);
        end
    end
end
