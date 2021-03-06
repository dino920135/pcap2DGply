% This code convert the .pcap file from Velodyne Lidar to .pcd file for
% each frame with velodyneFileReader().
% 
% Project support: NLSC2020
% Author: Tsai Syun
% Update time: 2020.05.04 
% Other functions: /lib
%   calcN.ma
%   GpsConstants.m
%   JulianDay.m
%   LeapSeconds.m
%   plh2xyz.m
%   Utc2Gps.m
% 
% The issue of initial time jump across hours between the file name and
% .pcap was not fixed

clearvars -except pcDirName trDirName
clc
close all
% defaultPath = '/home/tsaisyun/DATA/';
defaultPath = '/home/tsaisyun/DATA';
if ~exist('pcDirName','var')
    pcDirName = defaultPath;
elseif pcDirName == 0
    pcDirName = defaultPath;
end
if ~exist('trDirName','var')
    trDirName = defaultPath;
elseif trDirName == 0
    trDirName = defaultPath;
end
addpath('lib')
%% SETTINGS
AutoGetStartTime = 1;   % auto get start time from .pcap file name
timeInterval = [1 inf];
UTF_timeZone = 8;       % time zone of the collected data
deviceModel = 'VLP16';  % Velodyne LiDAR Model
saveFile = 1;           % Save File or NOT
pcFilter = 1;           % Filter point cloud with XY bounding box
Seg_DG = 1;
Zupt_only = 1;

filterPlane = ...
    {[12.41 -18.20
12.52 -18.29
25.20 -23.1
24.97 -23.50]};
filterMinZ = 22.71;

if pcFilter == 1
    savePath = 'Seg/';
else
    savePath = 'PLY/';      % path to save .pcd file
end

boresigh = [1168.9 -199.8 -3435.9];
leverarm = [64.5 -27.8 0];
%% READ FILES
% PCAP file
[pcFileName,pcDirName] = uigetfile({...
    '*.pcap','PCAP Files(*.pcap)';'*.*','All Files(*.*)'},'Choose PCAP File',pcDirName);
if pcFileName == 0, disp('No file is selected.'); return; end

veloReader = velodyneFileReader([pcDirName,pcFileName],deviceModel);

if AutoGetStartTime == 1
    tmpCell = strsplit(pcFileName, {'-','_'});
    utcStr = zeros(1,6);
    for i = 1:6
        utcStr(i) = str2num(tmpCell{i});
    end
%     check start time
    sec = mod(seconds(veloReader.CurrentTime),60);
    min = floor(mod(minutes(veloReader.CurrentTime),60));
    if min - utcStr(5) > 30
        utcStr(4) = utcStr(4) - 1;
    elseif min - utcStr(5) < -30
        utcStr(4) = utcStr(4) + 1;
    end
    utcStr(5:6) = [min, sec];
        
end

% Trajectory file
[trFileName,trDirName] = uigetfile({...
    '*.txt','Trajectory Files(*.txt)';'*.*','All Files(*.*)'},'Choose Trajectory File',trDirName);
if trFileName == 0, disp('No file is selected.'); return; end
pose = importdata([trDirName, trFileName], ' ', 30);
addR = 0;
% Heading Continious for interpolation
for i = 1:length(pose.data)-1
    if (pose.data(i+1, 10) + addR - pose.data(i, 10)) < -180
        addR = addR + 360;
    elseif (pose.data(i+1, 10) + addR - pose.data(i, 10)) > 180
        addR = addR - 360;
    end
    pose.data(i + 1, 10) = pose.data(i + 1, 10) + addR;
end


%% Time alignment
crossHr = 0;

veloTime = [veloReader.StartTime, veloReader.StartTime:...
    veloReader.Duration / veloReader.NumberOfFrames:...
    veloReader.StartTime + veloReader.Duration]';
veloGPST = [0; zeros(veloReader.NumberOfFrames,1)];
for i = 2:veloReader.NumberOfFrames + 1
    sec = mod(seconds(veloTime(i,1)),60);
    min = floor(mod(minutes(veloTime(i)),60));

    utcStr(5:6) = [min,sec];
    [GPST, ~] = Utc2Gps(utcStr);    
    veloGPST(i) = GPST(2) - UTF_timeZone*3600;
    % check time continue
    if abs(veloGPST(i) - veloGPST(i-1) + 3600) <= 10
        crossHr = floor((veloGPST(i-1) - veloGPST(i)) / 3599);
    end
    veloGPST(i) = veloGPST(i) + crossHr * 3600;        
end
veloTime(1) = [];
veloGPST(1) = [];
% LLH 2 ENU
pose.data(:, 2:4) = plh2enu(pose.data(1, 2:4), pose.data(:, 2:4));
% interpolation
transENU = interp1(pose.data(:,1), pose.data(:,2:end), veloGPST);
clear transNEU;
%% SHOW POINT CLOUDS & SAVE .PLY
xlimits = [-120 120];
ylimits = [-120 120];
zlimits = [-20 20];

player = pcplayer(xlimits,ylimits,zlimits);

xlabel(player.Axes,'X (m)');
ylabel(player.Axes,'Y (m)');
zlabel(player.Axes,'Z (m)');

veloReader.CurrentTime = veloReader.StartTime;
frameCount = 0;

while(hasFrame(veloReader) && player.isOpen() && frameCount < length(veloGPST)-1)
    frameCount = frameCount + 1;
    ptCloudObj = readFrame(veloReader);
    
    % Skip frames not inside interested interval (timeInterval)
    if ~any( (frameCount > timeInterval(:,1)) & (frameCount < timeInterval(:,2)))
        continue;
    end
    % Skip frame by ZUPT
    if norm(transENU(frameCount, 4:5)) > 0.02
        continue;
    end
    % Check timestamp repeat
    if (transENU(frameCount+1, 1)-transENU(frameCount, 1)) <=0
        continue;
    end
    
    homoXYZ = [reshape(ptCloudObj.Location(:,:,1), [], 1)';     % X-Point clouds sequenced by line ID No. in one row 1
        reshape(ptCloudObj.Location(:,:,2), [], 1)';            % Y-Point clouds sequenced by line ID No. in one row 2
        reshape(ptCloudObj.Location(:,:,3), [], 1)';            % Z-Point clouds sequenced by line ID No. in one row 3
        ones(1, length(reshape(ptCloudObj.Location(:,:,1), [], 1)'))]; % 1 in one row 4
    
%     Transformation for each scan frame
    roll = transENU(frameCount, 7);
    pitch = transENU(frameCount, 8);
    heading = transENU(frameCount, 9);% + 90;
    trans = transENU(frameCount, 1:3);
    rotm = [1 0 0; 0 cosd(roll) sind(roll); 0 -sind(roll) cosd(roll)]*...           % Rx
        [cosd(pitch) 0 -sind(pitch); 0 1 0; sind(pitch) 0 cosd(pitch)]*...          % Ry
        [cosd(heading) sind(heading) 0; -sind(heading) cosd(heading) 0; 0 0 1];     % Rz
    
    homoTransM = [rotm trans';0 0 0 1];
    pcENU = homoTransM * homoXYZ;   % Transformation in homogenious form
        
%     Correction dx,dx for scaning dt
%     dRPY = 
    dXYZ = reshape(repmat([0: (transENU(frameCount+1, 1)-transENU(frameCount, 1))/length(homoXYZ)*16: (transENU(frameCount+1, 1)-transENU(frameCount, 1));
        0: (transENU(frameCount+1, 2)-transENU(frameCount, 2))/length(homoXYZ)*16: (transENU(frameCount+1, 2)-transENU(frameCount, 2))], 16, 1), 2, []);
    dXYZ(:, 1:16) = [];
    pcENU(1:2, :) = pcENU(1:2, :) + dXYZ;
    
    % Find and remove NaN
    nanID = find(isnan(pcENU(4, :)));   % id of nans
    pcENU(:, nanID) = [];   % Drop nan columns
    pcENU_Intensity = reshape(ptCloudObj.Intensity, [], 1);
    pcENU_Intensity(nanID) = [];
    if Seg_DG == 1
        homoXYZ(:, nanID) = [];
    end
    
    if pcFilter
        in_all = logical(zeros(length(pcENU),1));
        for i = 1:length(filterPlane)
            % Remove points outside the polygon
            [in, ~] = inpolygon(pcENU(1, :)', pcENU(2, :)', filterPlane{i,1}(:,1), filterPlane{i, 1}(:,2));
            % Remove points lower then min z
            in_all = in_all | in;
        end
        pcENU(:, ~in) = [];
        low = (pcENU(3, :) < filterMinZ);
        pcENU(:, low) = [];

        pcENU_Intensity(~in) = [];
        pcENU_Intensity(low) = [];

        if Seg_DG == 1
            homoXYZ(:, ~in) = [];
            homoXYZ(:, low) = [];
        end
    end
    
    pcENU(4, :) = [];
    pcENU = pointCloud(pcENU');
    pcENU.Intensity = pcENU_Intensity;
    if Seg_DG == 1
        homoXYZ(4, :) = [];
        pcXYZ = pointCloud(homoXYZ');
        pcXYZ.Intensity = pcENU_Intensity;
    end
    
    player.Axes.XLim = [trans(1)-60 trans(1)+60];   
    player.Axes.YLim = [trans(2)-60 trans(2)+60];
    player.Axes.ZLim = [trans(3)-60 trans(3)+60];
    view(player, pcENU);
%     hold on
%     plot3(filterPlane{1,1}(:,1), filterPlane{1,1}(:,2), ones(4,1)*filterMinZ);
%     plot3(filterPlane{2,1}(:,1), filterPlane{2,1}(:,2), ones(4,1)*filterMinZ);
    if ~isempty(pcENU.Location) && saveFile == 1
%         pcwrite(pcENU,[pcDirName savePath num2str(veloGPST(frameCount)) '.pcd'],'Encoding','ascii');
        pcwrite(pcENU,[pcDirName savePath 'DG/' num2str(veloGPST(frameCount)*10^10) 'E-10' '.ply'],'PLYFormat','binary');
    if Seg_DG == 1
        pcwrite(pcXYZ,[pcDirName savePath 'BODY/' num2str(veloGPST(frameCount)*10^10) 'E-10' '.ply'],'PLYFormat','binary');
    end
%         pcwrite(pcENU,[pcDirName savePath 'DG\' num2str(veloGPST(frameCount)*10^10) 'E-10' '.ply'],'PLYFormat','binary');
%         pcwrite(pcXYZ,[pcDirName savePath 'BODY\' num2str(veloGPST(frameCount)*10^10) 'E-10' '.ply'],'PLYFormat','binary');
    end
    
    pause(0.0001);
end
pcwrite(pointCloud(transENU(:, 2:4)),[pcDirName 'trajectory.ply'],'PLYFormat','binary');
pose_ENU = [veloGPST, transENU];
save([pcDirName 'pose_ENU.txt'], 'pose_ENU', '-ascii', '-tabs');