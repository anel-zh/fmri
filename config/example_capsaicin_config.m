% EXAMPLE_CAPSAICIN_CONFIG - Configuration setup for capsaicin time-series analysis
%
% This script initializes a PipelineConfig object with parameters specific 
% to the Capsaicin sustained pain paradigm.

cfg = PipelineConfig();

%% 1. Project Metadata
cfg.StudyName = 'Capsaicin_Time_Series';
cfg.TR = 0.46;
cfg.AtlasName = 'glasser_atlas'; % Example atlas name
cfg.FilePattern = 'swra';        % Typical prefix for preprocessed data
cfg.DenoisingMethod = '24_nuisance_regressors';

%% 2. Directory Pathing (Adjust to your local environment)
cfg.RawDataDir = '/path/to/your/nas_storage';
cfg.BaseDir    = '/path/to/your/local_project_folder';
cfg.ResultsDir = fullfile(cfg.BaseDir, 'results');

%% 3. Binning & Windowing Parameters
% Parameters for 'same_time_window' mode
cfg.Binning.Task.BinCount = 15;
cfg.Binning.Task.WindowSizeTR = 95;

cfg.Binning.Baseline.BinCount = 8;
cfg.Binning.Baseline.WindowSizeTR = 95;

%% 4. Sustained Pain Thresholds (Genericized)
cfg.TR_Threshold  = 1510;  % Point at which we treat the run as "long"
cfg.BaselineMaxTR = 794;   % Maximum TRs to consider for resting/baseline runs

%% 5. Participant List
cfg.Participants = {'sub-01', 'sub-02', 'sub-04', 'sub-05'}; % Example list

% Validation check
cfg.validate_paths();

fprintf('Configuration for "%s" loaded successfully.\n', cfg.StudyName);
