function [X, y, metadata] = DataAssembler(cfg, feature_type, pain_scores)
% DATAASSEMBLER - Aggregates extracted fMRI features into a model-ready format
%
% This function iterates through the results directory, loads the 
% features extracted in Phase 1, and assembles them into a single 
% feature matrix (X). It ensures that brain data is correctly paired 
% with behavioral pain ratings (y).
%
% Inputs:
%   cfg          - PipelineConfig object
%   feature_type - 'hrf_beta' or 'dcc'
%   pain_scores  - A structure or table containing ratings per participant/bin
%
% Outputs:
%   X            - [Observations x Features] matrix
%   y            - [Observations x 1] response vector
%   metadata     - Structure containing subject and bin mapping

    fprintf('Assembling model data for feature type: %s\n', feature_type);
    
    X = [];
    y = [];
    metadata.sub_id = {};
    metadata.bin_index = [];

    % Define result folder based on config
    folder_name = sprintf('%s_%s', cfg.DenoisingMethod, cfg.AtlasName);
    base_results = fullfile(cfg.ResultsDir, folder_name);

    for i = 1:numel(cfg.Participants)
        sub_id = cfg.Participants{i};
        sub_dir = fullfile(base_results, sub_id, 'data');
        
        % 1. Locate the correct feature file
        if strcmp(feature_type, 'hrf_beta')
            file_pattern = 'hrf_betas_*.mat';
            var_name = 'betas';
        else
            file_pattern = 'dcc_*.mat';
            var_name = 'dcc_data';
        end
        
        f_list = dir(fullfile(sub_dir, 'Activation', file_pattern));
        if strcmp(feature_type, 'dcc')
            f_list = dir(fullfile(sub_dir, 'DCC', file_pattern));
        end

        for f = 1:numel(f_list)
            data_struct = load(fullfile(f_list(f).folder, f_list(f).name));
            raw_features = data_struct.(var_name);
            
            % 2. Process features based on type
            % HRF Betas: [ROIs x Bins] -> Transpose to [Bins x ROIs]
            % DCC: [ROIs x ROIs x Bins] -> Flatten to [Bins x Unique Connections]
            
            if strcmp(feature_type, 'hrf_beta')
                current_X = raw_features'; % Now [Bins x ROIs]
            else
                current_X = obj.flatten_connectivity(raw_features);
            end
            
            % 3. Align with Pain Scores
            % Assumes pain_scores is organized by [subject][run][bins]
            if isfield(pain_scores, sub_id)
                current_y = pain_scores.(sub_id).ratings;
                
                % Ensure X and y match in length (number of bins)
                n_bins = min(size(current_X, 1), length(current_y));
                
                X = [X; current_X(1:n_bins, :)];
                y = [y; current_y(1:n_bins)];
                
                % Track metadata for cross-validation later
                metadata.sub_id = [metadata.sub_id; repmat({sub_id}, n_bins, 1)];
                metadata.bin_index = [metadata.bin_index; (1:n_bins)'];
            end
        end
    end
    
    fprintf('Assembly complete. Final Matrix Size: %d observations x %d features.\n', size(X, 1), size(X, 2));
end

function flattened = flatten_connectivity(dcc_cube)
    % Helper to extract the unique (upper triangle) connections from a DCC matrix
    % Input: [ROIs x ROIs x Bins]
    [n_roi, ~, n_bins] = size(dcc_cube);
    idx = triu(true(n_roi), 1); % Mask for upper triangle
    
    flattened = [];
    for b = 1:n_bins
        frame = dcc_cube(:,:,b);
        flattened(b, :) = frame(idx)';
    end
end
