classdef PipelineConfig < handle
    % PIPELINECONFIG - Standardized configuration object for fMRI analysis
    %
    % This class centralizes study-specific parameters, directory settings,
    % imaging constants, feature extraction preferences, and run-specific
    % timing logic. The goal is to keep the rest of the pipeline modular,
    % while preserving enough flexibility for more complex neuroscience
    % workflows.
    %
    % Author: Anel Zhunussova

    properties
        %% Directory Paths
        ProjectRoot              % Path to repository/project root
        RawDataDir               % Path to preprocessed participant-level data
        ResultsDir               % Path where extracted/model outputs are saved
        FiguresDir               % Path for visual outputs
        MetadataDir              % Path for metadata / behavioral files

        %% Study Details
        StudyName                % String identifier for the analysis
        ExampleParadigm          % Example task/paradigm label
        TR = 0.46                % Repetition Time (seconds)

        %% Imaging Assets
        AtlasName                % Atlas filename stem (without .nii)
        MaskName                 % Gray matter mask filename
        FilePattern              % Prefix/pattern to find BOLD images
        DenoisingMethod          % Label for nuisance strategy / denoising

        %% Participants and Runs
        Participants             % Cell array of subject IDs
        RunLabels                % Cell array of run labels, e.g. {'task','baseline'}

        %% Feature Extraction
        SupportedMethods         % Available extraction methods
        DefaultMethods           % Default extraction methods

        %% Run-Specific Timing / Binning
        RunConfig                % Struct with one field per run type

        %% Modeling Preferences
        AnalysisMode             % e.g. 'subjectwise', 'population'
        GroupingVariable         % e.g. 'subject_id'
        CVScheme                 % e.g. 'loso', 'groupkfold'

        %% General Processing Options
        SaveIntermediate = true
        OverwriteOutputs = false
        Verbose = true
    end

    methods
        function obj = PipelineConfig(varargin)
            % Constructor: initializes with defaults and allows optional overrides

            %% Default folder structure
            obj.ProjectRoot = '.';
            obj.RawDataDir = fullfile(obj.ProjectRoot, 'data', 'preprocessed');
            obj.ResultsDir = fullfile(obj.ProjectRoot, 'results');
            obj.FiguresDir = fullfile(obj.ProjectRoot, 'figures');
            obj.MetadataDir = fullfile(obj.ProjectRoot, 'data', 'metadata');

            %% Default study details
            obj.StudyName = 'Example_fMRI_TimeSeries_Pipeline';
            obj.ExampleParadigm = 'sustained_pain';

            %% Default imaging assets
            obj.AtlasName = 'Schaefer_265';
            obj.MaskName = 'gray_matter_mask.nii';
            obj.FilePattern = 'swra';
            obj.DenoisingMethod = 'standard';

            %% Default participants and runs
            obj.Participants = {};
            obj.RunLabels = {'task', 'baseline'};

            %% Default feature extraction options
            obj.SupportedMethods = {'roi_dcc', 'hrf_roi', 'hrf_voxel'};
            obj.DefaultMethods = {'roi_dcc', 'hrf_roi'};

            %% Default modeling preferences
            obj.AnalysisMode = 'subjectwise';
            obj.GroupingVariable = 'subject_id';
            obj.CVScheme = 'loso';

            %% Default run timing configuration
            obj.RunConfig = struct();

            obj.RunConfig.task = struct( ...
                'StartTR', 1, ...
                'MaxTR', inf, ...
                'WindowSizeTR', 20, ...
                'NumBins', 10, ...
                'CutStartSec', 0, ...
                'CutMaxTR', inf, ...
                'LeadInSec', [], ...
                'LeadInDurationSec', [] ...
            );

            obj.RunConfig.baseline = struct( ...
                'StartTR', 1, ...
                'MaxTR', inf, ...
                'WindowSizeTR', 20, ...
                'NumBins', 10 ...
            );

            %% Optional overrides from name-value pairs
            if ~isempty(varargin)
                if mod(numel(varargin), 2) ~= 0
                    error('PipelineConfig inputs must be provided as name-value pairs.');
                end

                for i = 1:2:numel(varargin)
                    prop_name = varargin{i};
                    prop_val = varargin{i + 1};

                    if isprop(obj, prop_name)
                        obj.(prop_name) = prop_val;
                    else
                        error('Unknown PipelineConfig property: %s', prop_name);
                    end
                end
            end
        end

        function validate_paths(obj)
            % Ensures that critical project folders exist or are creatable

            if ~exist(obj.RawDataDir, 'dir')
                error('RawDataDir not found: %s', obj.RawDataDir);
            end

            if ~exist(obj.ResultsDir, 'dir')
                mkdir(obj.ResultsDir);
            end

            if ~exist(obj.FiguresDir, 'dir')
                mkdir(obj.FiguresDir);
            end

            if ~exist(obj.MetadataDir, 'dir')
                mkdir(obj.MetadataDir);
            end
        end

        function validate_core_fields(obj)
            % Checks that essential fields are properly configured

            required_text = {'StudyName', 'AtlasName', 'MaskName', ...
                             'FilePattern', 'DenoisingMethod'};

            for i = 1:numel(required_text)
                value = obj.(required_text{i});
                if ~(ischar(value) || isstring(value)) || strlength(string(value)) == 0
                    error('Invalid or empty config field: %s', required_text{i});
                end
            end

            if isempty(obj.Participants) || ~iscell(obj.Participants)
                error('Participants must be a non-empty cell array.');
            end

            if isempty(obj.RunLabels) || ~iscell(obj.RunLabels)
                error('RunLabels must be a non-empty cell array.');
            end

            if isempty(obj.SupportedMethods) || ~iscell(obj.SupportedMethods)
                error('SupportedMethods must be a non-empty cell array.');
            end

            if isempty(obj.DefaultMethods) || ~iscell(obj.DefaultMethods)
                error('DefaultMethods must be a non-empty cell array.');
            end

            if ~isstruct(obj.RunConfig) || isempty(fieldnames(obj.RunConfig))
                error('RunConfig must be a non-empty struct.');
            end

            if ~isscalar(obj.TR) || obj.TR <= 0
                error('TR must be a positive scalar.');
            end
        end

        function validate_run_config(obj)
            % Checks that each run label has a valid timing configuration

            for i = 1:numel(obj.RunLabels)
                run_name = obj.RunLabels{i};

                if ~isfield(obj.RunConfig, run_name)
                    error('RunConfig is missing an entry for run label: %s', run_name);
                end

                cfg = obj.RunConfig.(run_name);
                required_fields = {'StartTR', 'MaxTR', 'WindowSizeTR', 'NumBins'};

                for j = 1:numel(required_fields)
                    if ~isfield(cfg, required_fields{j})
                        error('RunConfig.%s is missing field: %s', run_name, required_fields{j});
                    end
                end

                numeric_fields = {'StartTR', 'MaxTR', 'WindowSizeTR', 'NumBins'};
                for j = 1:numel(numeric_fields)
                    value = cfg.(numeric_fields{j});
                    if ~isscalar(value) || ~isnumeric(value)
                        error('RunConfig.%s.%s must be a numeric scalar.', ...
                            run_name, numeric_fields{j});
                    end
                end
            end
        end

        function validate_all(obj)
            % Full configuration check before running pipeline components

            obj.validate_paths();
            obj.validate_core_fields();
            obj.validate_run_config();
        end

        function cfg = get_run_config(obj, run_label)
            % Convenience method to retrieve one run configuration safely

            if ~isfield(obj.RunConfig, run_label)
                error('RunConfig entry not found for run label: %s', run_label);
            end

            cfg = obj.RunConfig.(run_label);
        end

        function print_summary(obj)
            % Prints a brief summary of the active configuration

            fprintf('\n=== Pipeline Configuration Summary ===\n');
            fprintf('Study Name       : %s\n', obj.StudyName);
            fprintf('Example Paradigm : %s\n', obj.ExampleParadigm);
            fprintf('TR               : %.3f\n', obj.TR);
            fprintf('Atlas            : %s\n', obj.AtlasName);
            fprintf('Mask             : %s\n', obj.MaskName);
            fprintf('Denoising        : %s\n', obj.DenoisingMethod);
            fprintf('Participants     : %d\n', numel(obj.Participants));
            fprintf('Run Labels       : %s\n', strjoin(obj.RunLabels, ', '));
            fprintf('Methods          : %s\n', strjoin(obj.DefaultMethods, ', '));
            fprintf('Analysis Mode    : %s\n', obj.AnalysisMode);
            fprintf('CV Scheme        : %s\n', obj.CVScheme);
            fprintf('======================================\n\n');
        end
    end
end
