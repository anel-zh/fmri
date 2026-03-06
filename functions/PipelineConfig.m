classdef PipelineConfig < handle
    % PIPELINECONFIG - Standardized configuration object for fMRI analysis
    %
    % This class centralizes all study-specific parameters, including file 
    % paths, imaging constants, and binning preferences. This ensures that 
    % the processing functions remain agnostic to the specific dataset.
    %
    % Author: Anel Zhunussova

    properties
        % Directory Paths
        RawDataDir          % Path to the parent folder of participants
        BaseDir             % Path to the project root
        ResultsDir          % Path where output files will be saved
        
        % Study Parameters
        StudyName           % String identifier (e.g., 'Capsaicin_Study')
        TR = 0.46           % Repetition Time (seconds)
        AtlasName           % Filename of the atlas (.nii)
        FilePattern         % Pattern to find BOLD images (e.g., 'swra')
        DenoisingMethod     % String describing the denoising (e.g., 'standard')
        
        % Participant Management
        Participants        % Cell array of subject IDs
        
        % Binning & Windowing Logic
        Binning             % Structure containing window sizes and bin counts
        
        % Processing Constants
        TR_Threshold        % TR limit to distinguish long/short scans
        BaselineMaxTR       % Limit for baseline/resting runs
    end

    methods
        function obj = PipelineConfig()
            % Constructor: Initializes with default empty structures
            obj.Binning = struct();
        end

        function validate_paths(obj)
            % Method to ensure all critical directories exist before processing
            if ~exist(obj.RawDataDir, 'dir')
                error('RawDataDir not found: %s', obj.RawDataDir);
            end
            if ~exist(obj.BaseDir, 'dir')
                mkdir(obj.BaseDir); % Create if doesn't exist
            end
        end
    end
end
