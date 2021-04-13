function EG_ENU = plh2enu(CG_PLH,EG_PLH)
    num1 = size(EG_PLH);    
    LO_lat = CG_PLH(1);    LO_lon = CG_PLH(2);              % 設定區域坐標系統旋轉矩陣
    LO_Cen = [-sind(LO_lon)                cosd(LO_lon)                  0;
              -sind(LO_lat)*cosd(LO_lon)   -sind(LO_lat)*sind(LO_lon)    cosd(LO_lat);
              cosd(LO_lat)*cosd(LO_lon)     cosd(LO_lat)*sind(LO_lon)    sind(LO_lat)];
    EG_ENU=zeros(num1(1),3);
    for i=1:num1(1)                                         % 參考解PLH轉XYZ再轉ENU
        PLH(1:2) = deg2rad(EG_PLH(i,1:2));%*pi/180;
        PLH(3) = EG_PLH(i,3);
        XYZ = plh2xyz(PLH);
        if i==1,XYZ0=XYZ;end
        EG_ENU(i,1:3) = (LO_Cen* (XYZ'-XYZ0'))';
        EG_ENU(i,3) = PLH(3);
    end 
end