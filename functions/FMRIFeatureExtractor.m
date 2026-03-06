classdef FMRIFeatureExtractor < handle
    % FMRIFEATUREEXTRACTOR - Core engine for fMRI time-series feature extraction
    %
    % This class manages the transformation of preprocessed fMRI BOLD images
    % into predictive features. It supports ROI-based signal extraction,
    % Dynamic Conditional Correlation (DCC), and single-trial HRF regression.
    %
    % The implementation is designed to remain reusable across sustained pain
    % and related task-based pipelines while preserving the time-series logic
    % from the original project.
    %
    % Author: Anel Zhunussova

    properties
        Config      % PipelineConfig object
        MaskPath    % Path to gray matter mask
        AtlasPath   % Path to atlas image
    end

    methods
        function obj = FMRIFeatureExtractor(config_obj)
            % Constructor: connects the config object and validates assets

            obj.Config = config_obj;
            obj.validate_config();

            obj.MaskPath = which(obj.Config.MaskName);
            obj.AtlasPath = which([obj.Config.AtlasName '.nii']);

            if isempty(obj.MaskPath)
                error('Gray matter mask not found: %s', obj.Config.MaskName);
            end

            if isempty(obj.AtlasPath)
                error('Atlas file not found: %s.nii', obj.Config.AtlasName);
            end
        end

        function run_extraction(obj, varargin)
            % Main execution loop.
            % Iterates through participants and configured run types.

            p = inputParser;
            addParameter(p, 'Methods', {'roi_dcc', 'hrf_roi'}, @iscell);
            addParameter(p, 'Runs', obj.Config.RunLabels, @iscell);
            addParameter(p, 'ApplyDurationCut', false, @islogical);
            addParameter(p, 'FolderSuffix', '', @(x) ischar(x) || isstring(x));
            parse(p, varargin{:});
            args = p.Results;

            for i = 1:numel(obj.Config.Participants)
                sub_id = obj.Config.Participants{i};
                fprintf('--- Processing Subject: %s ---\n', sub_id);

                sub_out_dir = obj.init_output_dirs(sub_id, args.FolderSuffix);

                for r = 1:numel(args.Runs)
                    run_type = args.Runs{r};
                    obj.process_run_type(sub_id, run_type, sub_out_dir, args);
                end
            end
        end
    end

    methods (Access = private)

        function validate_config(obj)
            % Checks that required configuration fields exist

            required_fields = { ...
                'RawDataDir', 'ResultsDir', 'Participants', 'RunLabels', ...
                'AtlasName', 'MaskName', 'FilePattern', 'DenoisingMethod', ...
                'TR', 'RunConfig'};

            for i = 1:numel(required_fields)
                if ~isprop(obj.Config, required_fields{i})
                    error('Missing required config property: %s', required_fields{i});
                end
            end
        end

        function out_dir = init_output_dirs(obj, sub_id, suffix)
            % Establishes a standardized results hierarchy

            suffix = char(string(suffix));

            if isempty(strtrim(suffix))
                folder_name = sprintf('%s_%s', ...
                    obj.Config.DenoisingMethod, obj.Config.AtlasName);
            else
                folder_name = sprintf('%s_%s_%s', ...
                    obj.Config.DenoisingMethod, obj.Config.AtlasName, suffix);
            end

            out_dir = fullfile(obj.Config.ResultsDir, folder_name, sub_id, 'data');

            activation_dir = fullfile(out_dir, 'Activation');
            dcc_dir = fullfile(out_dir, 'DCC');

            if ~exist(activation_dir, 'dir')
                mkdir(activation_dir);
            end

            if ~exist(dcc_dir, 'dir')
                mkdir(dcc_dir);
            end
        end

        function process_run_type(obj, sub_id, run_type, out_dir, args)
            % Handles file discovery and per-run processing

            sub_func_dir = fullfile(obj.Config.RawDataDir, sub_id, 'func');

            if ~exist(sub_func_dir, 'dir')
                warning('Functional directory not found for subject: %s', sub_id);
                return;
            end

            pattern = sprintf('%s*%s*_bold.nii', obj.Config.FilePattern, run_type);
            files = dir(fullfile(sub_func_dir, pattern));

            if isempty(files)
                warning('No matching runs found for %s | run type: %s', sub_id, run_type);
                return;
            end

            for f = 1:numel(files)
                run_file = files(f).name;
                run_path = fullfile(files(f).folder, run_file);
                run_name = obj.strip_ext(run_file);

                fprintf('   Processing run: %s\n', run_name);

                fmri_obj = fmri_data(run_path, obj.MaskPath);
                fmri_obj = obj.apply_denoising(fmri_obj, sub_id, run_type, run_name);

                if ismember('roi_dcc', args.Methods)
                    obj.extract_connectivity(fmri_obj, out_dir, run_name);
                end

                if ismember('hrf_roi', args.Methods)
                    obj.extract_hrf_betas(fmri_obj, out_dir, run_type, run_name, ...
                        args.ApplyDurationCut, 'roi');
                end

                if ismember('hrf_voxel', args.Methods)
                    obj.extract_hrf_betas(fmri_obj, out_dir, run_type, run_name, ...
                        args.ApplyDurationCut, 'voxel');
                end
            end
        end

        function dat = apply_denoising(obj, dat, sub_id, run_type, run_name)
            % Loads nuisance covariates matching the configured denoising method

            nuis_candidates = { ...
                sprintf('nuisance_%s_%s_%s.mat', obj.Config.DenoisingMethod, run_type, run_name), ...
                sprintf('nuisance_%s_%s.mat', obj.Config.DenoisingMethod, run_type)};

            nuis_dir = fullfile(obj.Config.RawDataDir, sub_id, 'nuisance_mat');
            nuis_path = '';

            for i = 1:numel(nuis_candidates)
                candidate_path = fullfile(nuis_dir, nuis_candidates{i});
                if exist(candidate_path, 'file')
                    nuis_path = candidate_path;
                    break;
                end
            end

            if isempty(nuis_path)
                warning('Nuisance file not found for %s (%s). Proceeding without covariates.', ...
                    sub_id, run_type);
                return;
            end

            nuis_struct = load(nuis_path);

            if ~isfield(nuis_struct, 'R')
                error('Nuisance file does not contain variable R: %s', nuis_path);
            end

            if size(nuis_struct.R, 1) ~= size(dat.dat, 2)
                error(['Nuisance matrix row count does not match number of TRs. ' ...
                       'File: %s'], nuis_path);
            end

            dat.covariates = nuis_struct.R;
        end

        function extract_connectivity(obj, fmri_obj, out_dir, run_name)
            % Extracts ROI time series and computes Dynamic Conditional Correlation

            [~, roi_obj] = canlab_connectivity_preproc( ...
                fmri_obj, ...
                'windsorize', 5, ...
                'lpf', 0.1, obj.Config.TR, ...
                'extract_roi', obj.AtlasPath, ...
                'no_plots');

            roi_data = roi_obj{1}.dat;

            save(fullfile(out_dir, 'Activation', ['roi_ts_' run_name '.mat']), ...
                'roi_data', '-v7.3');

            dcc_data = DCC_jj(roi_data, 'simple', 'whiten');

            save(fullfile(out_dir, 'DCC', ['dcc_' run_name '.mat']), ...
                'dcc_data', '-v7.3');
        end

        function extract_hrf_betas(obj, fmri_obj, out_dir, run_type, run_name, cut_dur, beta_mode)
            % Executes single-trial regression for ROI or voxel outputs

            total_TRs = size(fmri_obj.dat, 2);
            onsets = obj.calculate_onsets(total_TRs, run_type, cut_dur);

            if isempty(onsets)
                warning('No valid onsets generated for run: %s', run_name);
                return;
            end

            X = plotDesign_mint( ...
                onsets, [], obj.Config.TR, total_TRs * obj.Config.TR, ...
                'samefig', spm_hrf(obj.Config.TR), 'singletrial');

            num_bins = numel(onsets);

            if strcmp(beta_mode, 'roi')
                [~, ~, ~, ~, r_beta] = canlab_connectivity_preproc( ...
                    fmri_obj, ...
                    'windsorize', 5, ...
                    'lpf', 0.1, obj.Config.TR, ...
                    'extract_roi', obj.AtlasPath, ...
                    'no_plots', ...
                    'regressors', X(:, 1));

                betas = zeros(size(r_beta{1}.dat, 1), num_bins);

            elseif strcmp(beta_mode, 'voxel')
                [~, ~, ~, v_beta] = canlab_connectivity_preproc( ...
                    fmri_obj, ...
                    'windsorize', 5, ...
                    'lpf', 0.1, obj.Config.TR, ...
                    'extract_roi', obj.AtlasPath, ...
                    'no_plots', ...
                    'regressors', X(:, 1));

                betas = zeros(size(v_beta.dat, 1), num_bins);

            else
                error('Unknown beta mode: %s', beta_mode);
            end

            for b = 1:num_bins
                [~, ~, ~, v_beta, r_beta] = canlab_connectivity_preproc( ...
                    fmri_obj, ...
                    'windsorize', 5, ...
                    'lpf', 0.1, obj.Config.TR, ...
                    'extract_roi', obj.AtlasPath, ...
                    'no_plots', ...
                    'regressors', X(:, b));

                if strcmp(beta_mode, 'roi')
                    betas(:, b) = r_beta{1}.dat;
                else
                    betas(:, b) = v_beta.dat;
                end
            end

            save_name = sprintf('hrf_%s_%s.mat', beta_mode, run_name);
            save(fullfile(out_dir, 'Activation', save_name), 'betas', '-v7.3');
        end

        function onsets = calculate_onsets(obj, total_TR, run_type, cut_dur)
            % Generates temporal windows based on run-specific configuration

            run_cfg = obj.get_run_config(run_type);

            start_tr = run_cfg.StartTR;
            end_tr = min(total_TR, run_cfg.MaxTR);

            if cut_dur && isfield(run_cfg, 'CutStartSec')
                start_tr = round(run_cfg.CutStartSec / obj.Config.TR) + 1;
            end

            if cut_dur && isfield(run_cfg, 'CutMaxTR')
                end_tr = min(end_tr, run_cfg.CutMaxTR);
            end

            if end_tr < start_tr
                warning('Invalid onset window for run type: %s', run_type);
                onsets = {};
                return;
            end

            window_size = run_cfg.WindowSizeTR;
            requested_bins = run_cfg.NumBins;

            max_possible_bins = floor((end_tr - start_tr + 1) / window_size);
            num_bins = min(requested_bins, max_possible_bins);

            if num_bins < 1
                warning('No complete bins available for run type: %s', run_type);
                onsets = {};
                return;
            end

            starts = start_tr + (0:(num_bins - 1)) * window_size;
            onsets = cell(num_bins, 1);

            for b = 1:num_bins
                onsets{b} = [(starts(b) - 1) * obj.Config.TR, ...
                             window_size * obj.Config.TR];
            end

            if cut_dur && isfield(run_cfg, 'LeadInSec') && ~isempty(run_cfg.LeadInSec)
                onsets = [{[run_cfg.LeadInSec, run_cfg.LeadInDurationSec]}; onsets];
            end
        end

        function run_cfg = get_run_config(obj, run_type)
            % Retrieves the timing configuration for a specific run type

            cfg_names = fieldnames(obj.Config.RunConfig);
            match_idx = strcmpi(cfg_names, run_type);

            if ~any(match_idx)
                error('No RunConfig entry found for run type: %s', run_type);
            end

            run_cfg = obj.Config.RunConfig.(cfg_names{find(match_idx, 1)});
        end

        function stem = strip_ext(~, filename)
            % Removes .nii or .nii.gz extension for cleaner output naming

            stem = filename;

            if endsWith(stem, '.nii.gz')
                stem = erase(stem, '.nii.gz');
            elseif endsWith(stem, '.nii')
                stem = erase(stem, '.nii');
            end
        end
    end
end
