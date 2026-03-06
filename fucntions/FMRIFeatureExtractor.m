classdef FMRIFeatureExtractor < handle
    % FMRIFEATUREEXTRACTOR - Core engine for fMRI time-series feature extraction
    %
    % This class manages the transformation of raw fMRI BOLD images into 
    % predictive features. It supports ROI-based signal extraction, Dynamic 
    % Conditional Correlation (DCC), and single-trial HRF regression.
    %
    % The logic is optimized for sustained pain paradigms where temporal 
    % binning is required to capture the evolution of the neural response.
    %
    % Author: Anel Zhunussova

    properties
        Config          % PipelineConfig object
        MaskPath        % Path to gray matter mask
        AtlasPath       % Path to atlas image
    end

    methods
        function obj = FMRIFeatureExtractor(config_obj)
            % Constructor: Connects the config object and validates assets
            obj.Config = config_obj;
            
            % Locate required imaging assets on the MATLAB path
            obj.MaskPath = which('gray_matter_mask.nii');
            obj.AtlasPath = which([obj.Config.AtlasName '.nii']);
            
            if isempty(obj.MaskPath), error('Gray matter mask not found.'); end
            if isempty(obj.AtlasPath), error('Atlas file not found: %s', obj.Config.AtlasName); end
        end

        function run_extraction(obj, varargin)
            % Main execution loop. Iterates through participants and run types
            % defined in the configuration.
            
            p = inputParser;
            addParameter(p, 'Methods', {'roi_dcc', 'hrf_beta'}, @iscell);
            addParameter(p, 'Runs', {'task', 'baseline'}, @iscell);
            addParameter(p, 'ApplyDurationCut', false, @islogical);
            parse(p, varargin{:});
            args = p.Results;

            for i = 1:numel(obj.Config.Participants)
                sub_id = obj.Config.Participants{i};
                fprintf('--- Processing Subject: %s ---\n', sub_id);
                
                % Create subject-specific output structure
                sub_out_dir = obj.init_output_dirs(sub_id);
                
                % Process each run type (e.g., Capsaicin vs. Resting State)
                for r = 1:numel(args.Runs)
                    obj.process_run(sub_id, args.Runs{r}, sub_out_dir, args);
                end
            end
        end
    end

    %% Internal Processing Logic
    methods (Access = private)

        function out_dir = init_output_dirs(obj, sub_id)
            % Establish a standardized results hierarchy
            folder_name = sprintf('%s_%s', obj.Config.DenoisingMethod, obj.Config.AtlasName);
            out_dir = fullfile(obj.Config.ResultsDir, folder_name, sub_id);
            
            if ~exist(fullfile(out_dir, 'Activation'), 'dir'), mkdir(fullfile(out_dir, 'Activation')); end
            if ~exist(out_dir, 'DCC', 'dir'), mkdir(fullfile(out_dir, 'DCC')); end
        end

        function process_run(obj, sub_id, run_type, out_dir, args)
            % Handles file IO, nuisance regression, and algorithm execution
            sub_func_dir = fullfile(obj.Config.RawDataDir, sub_id, 'func');
            
            % Search for BOLD files matching the config pattern
            pattern = sprintf('%s*%s*_bold.nii', obj.Config.FilePattern, run_type);
            files = dir(fullfile(sub_func_dir, pattern));
            
            for f = 1:numel(files)
                run_path = fullfile(sub_func_dir, files(f).name);
                [~, run_name] = fileparts(files(f).name);
                
                % Load and Denoise BOLD data
                fmri_obj = fmri_data(run_path, obj.MaskPath);
                fmri_obj = obj.apply_denoising(fmri_obj, sub_id, run_type);
                
                % Algorithm 1: Connectivity (ROI Mean + DCC)
                if ismember('roi_dcc', args.Methods)
                    obj.extract_connectivity(fmri_obj, out_dir, run_name);
                end
                
                % Algorithm 2: Activation (HRF Regression)
                if ismember('hrf_beta', args.Methods)
                    obj.extract_hrf_betas(fmri_obj, out_dir, run_type, run_name, args.ApplyDurationCut);
                end
            end
        end

        function dat = apply_denoising(obj, dat, sub_id, run_type)
            % Loads nuisance covariates matching the denoising method in config
            nuis_file = sprintf('nuisance_%s_%s.mat', obj.Config.DenoisingMethod, run_type);
            nuis_path = fullfile(obj.Config.RawDataDir, sub_id, 'nuisance_mat', nuis_file);
            
            if exist(nuis_path, 'file')
                nuis_struct = load(nuis_path);
                dat.covariates = nuis_struct.R;
            else
                warning('Nuisance file not found for %s: %s', sub_id, nuis_file);
            end
        end

        function extract_connectivity(obj, fmri_obj, out_dir, run_name)
            % Extracts ROI time-series and computes Dynamic Conditional Correlation
            [~, roi_obj] = canlab_connectivity_preproc(fmri_obj, 'windsorize', 5, ...
                'lpf', 0.1, obj.Config.TR, 'extract_roi', obj.AtlasPath, 'no_plots');
            
            roi_data = roi_obj{1}.dat;
            save(fullfile(out_dir, 'Activation', ['roi_ts_' run_name '.mat']), 'roi_data');
            
            % Compute DCC (Connectivity)
            dcc_data = DCC_jj(roi_data, 'simple', 'whiten');
            save(fullfile(out_dir, 'DCC', ['dcc_' run_name '.mat']), 'dcc_data');
        end

        function extract_hrf_betas(obj, fmri_obj, out_dir, run_type, run_name, cut_dur)
            % Executes single-trial regression based on the MINT binning logic
            total_TRs = size(fmri_obj.dat, 2);
            onsets = obj.calculate_mint_onsets(total_TRs, run_type, cut_dur);
            
            % Generate Single-Trial Design Matrix
            X = plotDesign_mint(onsets, [], obj.Config.TR, total_TRs * obj.Config.TR, ...
                'samefig', spm_hrf(obj.Config.TR), 'singletrial');
            
            % Regression Loop for each bin
            num_bins = numel(onsets);
            betas = [];
            for b = 1:num_bins
                [~, ~, ~, ~, r_beta] = canlab_connectivity_preproc(fmri_obj, ...
                    'windsorize', 5, 'lpf', 0.1, obj.Config.TR, 'extract_roi', obj.AtlasPath, ...
                    'no_plots', 'regressors', X(:, b));
                betas(:, b) = r_beta{1}.dat;
            end
            
            save(fullfile(out_dir, 'Activation', ['hrf_betas_' run_name '.mat']), 'betas');
        end

        function onsets = calculate_mint_onsets(obj, total_TR, run_type, cut_dur)
            % Implements the temporal windowing logic for sustained pain.
            % Thresholds and window sizes are pulled from the Config object.
            
            if contains(run_type, 'baseline') || contains(run_type, 'rest')
                params = obj.Config.Binning.Baseline;
                start_tr = 1;
                end_tr = min(total_TR, obj.Config.BaselineMaxTR);
            else
                params = obj.Config.Binning.Task;
                thresh = obj.Config.TR_Threshold;
                
                if cut_dur
                    % Handle non-stationary onset shifts in capsaicin data
                    s_sec = obj.iff(total_TR > thresh, 104.6, 74.6);
                    start_tr = round(s_sec / obj.Config.TR) + 1;
                    end_tr = obj.iff(total_TR > thresh, thresh, total_TR);
                else
                    start_tr = obj.iff(total_TR > thresh, round(30/obj.Config.TR)+1, 1);
                    end_tr = total_TR;
                end
            end

            % Define windows
            win_sz = params.WindowSizeTR;
            n_bins = floor((end_tr - start_tr + 1) / win_sz);
            
            starts = start_tr + (0:(n_bins-1)) * win_sz;
            onsets = cell(n_bins, 1);
            for b = 1:n_bins
                onsets{b} = [(starts(b)-1)*obj.Config.TR, win_sz*obj.Config.TR];
            end

            % Lead-in bin for sustained pain paradigms
            if cut_dur && ~contains(run_type, 'baseline')
                lead_start = obj.iff(total_TR > obj.Config.TR_Threshold, 30, 0);
                onsets = [[lead_start, 20.0]; onsets];
            end
        end

        function val = iff(~, cond, t, f), if cond, val = t; else, val = f; end, end
    end
end
