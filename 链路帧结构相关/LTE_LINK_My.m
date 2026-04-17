%%
%第一步:仿真前清空工作空间中的所有变量,图形及命令
clear all;          % 清除MATLAB工作空间中的所有变量，确保仿真环境干净
close all;          % 关闭所有打开的图形窗口
% clc;              % 清空命令行窗口（被注释，保留命令行历史）
tic                 % 启动计时器，记录整个仿真运行时间

%%
%添加必要的路径(path)
% 根据当前MATLAB平台的可执行文件扩展名（mexext）动态添加对应的二进制库路径
switch upper(mexext)   % 获取MEX文件扩展名并转为大写，用于判断操作系统/平台
    case 'DLL'         % Windows动态链接库平台
        addpath '.\dll\'   % 添加dll文件夹到MATLAB搜索路径
    case 'MEXW32'      % 32位Windows MEX平台
        addpath '.\mexw32\' % 添加mexw32文件夹
    case 'MEXW64'      % 64位Windows MEX平台
        addpath '.\mexw64\' % 添加mexw64文件夹
    otherwise          % 其他平台不添加任何路径
end

%%
%第二步:设定随机数种子,确保每次仿真结果相同(应当在所有初始化之前设定)
rand('state',2^13-1);   % 设置均匀随机数生成器的状态种子为8191，保证可重复性
randn('state',2^17-1);  % 设置正态随机数生成器的状态种子为131071，保证可重复性

%%
%第三步:全局参数初始化
globals_init;           % 调用用户自定义的全局变量初始化函数（通常创建cell_para、user_para等全局结构体）

%%
%第四步:系统参数,小区参数,用户参数，用户信道参数，仿真参数配置
% sim_config_change;    % 被注释的旧配置调用
% sim_config_change;    % 再次注释
% 检查全局结构体frame_cfg是否存在且包含rat_mode字段，若不存在则设置默认RAT模式为LTE
if ~exist('frame_cfg','var') || isempty(frame_cfg) || ~isfield(frame_cfg,'rat_mode') || isempty(frame_cfg.rat_mode)
    frame_cfg.rat_mode = 'LTE';   % 默认无线接入技术为LTE
end

% 根据选择的RAT模式调用不同的配置函数
if strcmpi(frame_cfg.rat_mode,'NR')   % 如果模式为NR（不区分大小写）
    sim_config_change_nr;             % 调用NR模式配置函数
else
    frame_cfg.rat_mode = 'LTE';       % 强制设为LTE模式
    sim_config_change_dl;             % 调用LTE下行配置函数
end

sim_config_init;                      % 仿真参数初始化（如SNR点数、总帧数等）
frame_structure_init;                 % 帧结构初始化（新增于4.14版本）
sim_para.CM.deltaTA = 0;              % 设置信道模型中的时间提前量增量为0

%%
%第五步:无线信道初始化
%根据仿真链路类型及目标小区/用户进行无线信道初始化
%为了支持闭环传输,在此处同时添加上下行信道初始化参数
targetUserID = user_para{1,1}.userID;     % 获取第一个用户的ID（作为目标用户）
downlink_wireless_channel_init(targetUserID); % 初始化目标用户的下行无线信道
targetCellID = cell_para{1,1}.cellID;     % 获取第一个小区的小区ID
uplink_wireless_channel_init(targetCellID);   % 初始化目标小区的上行无线信道
if strcmpi(frame_cfg.rat_mode,'LTE')
   uplink_PRACH_init(targetCellID); % 初始化目标小区的物理随机接入信道（PRACH）
elseif  strcmpi(frame_cfg.rat_mode,'NR')
        %NR暂不走
else 
   error('unknown frame_cfg.rat_mode.');
end
   

%建立测试向量存储文件夹
RESULT_DIR='.\testvector\';               % 定义测试向量根目录
if exist(RESULT_DIR)~=7                  % 如果目录不存在（7表示文件夹）
    mkdir(RESULT_DIR);                   % 创建该文件夹
end
RESULT_DIR='.\testvector\pdsch\';        % PDSCH信道测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pusch\';        % PUSCH信道测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pusch\hardbit\';% PUSCH硬比特测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pusch\softbit\';% PUSCH软比特测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pucch\';        % PUCCH信道测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pucch\hardbit\';% PUCCH硬比特子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pucch\softbit\';% PUCCH软比特子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pdcch\';        % PDCCH测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pcfich\';       % PCFICH测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pbch\';         % PBCH测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\pmch\';         % PMCH测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\phich\';        % PHICH测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\ssch\';         % SSCH（辅同步信道）测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\psch\';         % PSCH（主同步信道）测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\prach\';        % PRACH测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\srs\';          % SRS（探测参考信号）测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\testvector\M1\';           % M1测试向量子目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end
RESULT_DIR='.\results\';                 % 仿真结果存储目录
if exist(RESULT_DIR)~=7
    mkdir(RESULT_DIR);
end

%%
%第六步:按照SNR-Frame-Unit三重结构进行仿真循环
% LTE: unit = subframe (子帧)
% NR : unit = slot (时隙)
%发射端始终按照子帧进行发送,接收端可能需要存储多个连续子帧/帧
%如何处理完全可以根据全局帧编号和子帧编号来决定
%另外,对于HARQ,可能发送端和接收端都需要存储数据,并记录编号
%此时，可能需要开辟全局的缓冲区

SNR_NUM = sim_para.SNR_NUM;               % 从仿真参数中获取信噪比点数
TotalFrameNum = sim_para.TotalFrameNum;   % 获取每个SNR点需要仿真的总帧数（可能为向量）

for n_snr = 1:SNR_NUM                     % 外层循环：遍历每个SNR点

    CS.cs_process_num = 0;                % 小区搜索过程计数器清零
    CS.cs_correct_num = 0;                % 小区搜索正确次数清零
    CS.n_rxframe = 0;                     % 接收帧计数器清零

    % 目标小区统计变量的初始化
    if strcmpi(frame_cfg.rat_mode,'LTE')
        sim_para.sim_link_type = 'DOWNLINK';  % 临时设为下行链路（用于初始化TBS控制）
        TBS_control_init(targetUserID);       % 初始化目标用户的传输块大小控制结构
        sim_para.sim_link_type = 'UPLINK';    % 临时设为上行链路
        TBS_control_init(targetCellID);       % 初始化目标小区的TBS控制结构
    elseif strcmpi(frame_cfg.rat_mode,'NR')
        sim_para.sim_link_type = 'DOWNLINK';
        NR_transport_control_init(targetUserID);
        sim_para.sim_link_type = 'UPLINK';
        NR_transport_control_init(targetCellID);
    else
        error('Unknown frame_cfg.rat_mode.');
    end

    sim_para.cur_SNR = sim_para.SNR(n_snr); % 当前SNR点值（线性或dB，取决于定义）
    SNR = sim_para.cur_SNR                 % 在命令行显示当前SNR值（无分号）

    CM_control_init;                      % LTE 与 NR 当前都复用 legacy CM 控制参数初始化，每个SNR点重置

    for n_frame = 0:TotalFrameNum(n_snr)-1  % 中层循环：遍历每个帧

        if mod(n_frame,10) == 0           % 每10帧在命令行输出一次换行
            fprintf(1,'\n\t\t');
        end
        fprintf(1,'%5d ',n_frame);        % 输出当前帧号（格式化宽度5）

        rx_signal_all  = [];              % 存储所有接收信号（用于PRACH累积）
        rx_signal0_all = [];              % 存储所有接收信号副本（可能用于AGC）

        for n_unit = 0:frame_cfg.unit_per_frame-1  % 内层循环：遍历每个单元（子帧或时隙）

            cell_para{1,1}.detected_userID_list = []; % 重置检测到的用户列表
            % 计算全局单元索引（帧索引×每帧单元数 + 单元内偏移）
            sim_para.global_unit_index = n_frame * frame_cfg.unit_per_frame + n_unit;

            %% 根据RAT模式判断当前处理单元对应的"传统子帧索引”
            if strcmpi(frame_cfg.rat_mode,'LTE')   % LTE模式
                n_subframe = n_unit;               % 单元即为子帧号
                sim_para.global_subframe_index = n_frame * 10 + n_subframe; % 全局子帧索引

                subframe_indicator = cell_para{1}.subframe_indicator; % 子帧激活指示器（10元素向量）
                unit_active = (subframe_indicator(n_subframe+1) == 1); % 当前子帧是否激活（1激活，0不激活）

                if unit_active
                    sim_config_compute(n_subframe);  % 计算当前子帧的配置（如TDD上下行配比）

                    UL_DL_config = cell_para{1,1}.UL_DL_config;        % TDD上下行配置索引（0-6）
                    UL_DL_subframe_config = UL_DL_config_table(UL_DL_config+1,:); % 查表得到每个子帧方向（1下行，-1上行，0特殊）
                    
                    if UL_DL_subframe_config(n_subframe+1) == 1
                        sim_para.sim_link_type = 'DOWNLINK';           % 下行子帧
                    elseif UL_DL_subframe_config(n_subframe+1) == -1
                        sim_para.sim_link_type = 'UPLINK';             % 上行子帧
                    elseif UL_DL_subframe_config(n_subframe+1) == 0
                        SP_subframe_type = sim_para.SP_subframe_type;  % 特殊子帧类型（DwPTS/UpPTS）
                        if strcmpi(SP_subframe_type,'DwPTs')
                            sim_para.sim_link_type = 'DOWNLINK';       % 特殊子帧的下行导频时隙
                        elseif strcmpi(SP_subframe_type,'UpPTs')
                            sim_para.sim_link_type = 'UPLINK';         % 特殊子帧的上行导频时隙
                        else
                            error('Special subframe type is wrong.');
                        end
                    else
                        error('UL_DL_config_table problem.');
                    end
                end

            else   % NR模式
                n_slot = n_unit;           % 单元即为时隙号
                n_subframe = floor(n_slot / frame_cfg.unit_per_subframe); % 计算所属子帧号（每子帧可能多个时隙）
                sim_para.global_subframe_index = n_frame * 10 + n_subframe;

                % 检查小区NR配置中是否存在slot_indicator（时隙激活指示）
                if ~isfield(cell_para{1,1},'nr') || ~isfield(cell_para{1,1}.nr,'slot_indicator')
                    error('NR mode requires cell_para{1,1}.nr.slot_indicator.');
                end
                if length(cell_para{1,1}.nr.slot_indicator) < frame_cfg.unit_per_frame
                    error('cell_para{1,1}.nr.slot_indicator length is smaller than slots per frame.');
                end

                unit_active = (cell_para{1,1}.nr.slot_indicator(n_slot+1) == 1); % 当前时隙是否激活

                if unit_active
                    % 如果存在NR配置计算函数，则调用它（预计算当前时隙的运行时参数）
                    if exist('sim_config_compute_nr','file') == 2
                        sim_config_compute_nr(n_slot);
                    end
                end 
            end

            %% 仅当当前子帧/时隙激活时才进行发射和接收处理，并且区分LTE和NR

            if unit_active   

                % 子帧/时隙发送：调用发射处理函数，返回接收信号（可能含噪声）和理想接收信号（无噪声）
                [rx_signal, rx_signal0] = subframe_transmit(n_snr, n_frame, n_unit);

                if strcmpi(sim_para.sim_link_type,'DOWNLINK')   % 下行链路处理

                    % 如果启用了小区搜索过程（CS_process）且为LTE模式
                    if strcmpi(sim_para.CS_process,'ENABLED') && strcmpi(frame_cfg.rat_mode,'LTE')

                        CS.process_flag = 0;   % 小区搜索处理标志（将在LTE_CS_system中设置）
                        % 调用LTE小区搜索系统函数，返回检测到的主同步信号位置、粗频偏、细频偏和检测到的小区ID
                        [pos0, foe1, foe2, CELL_ID] = LTE_CS_system(rx_signal, rx_signal0, n_snr, targetUserID);

                        if CS.process_flag   % 如果搜索成功
                            pos(CS.cs_process_num)        = pos0;          % 记录位置
                            foe_coarse(CS.cs_process_num) = foe1;          % 记录粗频偏
                            foe_fine(CS.cs_process_num)   = foe2;          % 记录细频偏
                            CELL_ID_detect(CS.cs_process_num) = CELL_ID;   % 记录检测到的小区ID
                        end

                    else   % 正常下行接收（非小区搜索模式）

                        userID_list = cell_para{1}.userID_list;  % 获取小区下所有用户ID
                        user_num = length(userID_list);

                        for k = 1:user_num   % 遍历每个用户
                            userID = userID_list(k);
                            [n_cell, n_user] = getUserIndexfromID(userID); % 获取用户索引（忽略输出）

                            if strcmpi(frame_cfg.rat_mode,'LTE')   % LTE模式下行接收

                                % 调用LTE下行解调解码系统函数，返回多种中间结果
                                [time_agc_factor, fre_agc_factor, pilot_chan_est, ue_pilot_chan_est, ...
                                    channel_est_subframe, demapper_soft_bits, subframe_fre_symb, ...
                                    receiver_blocks_symbols] = LTE_DL_DE_system(rx_signal, rx_signal0, userID);

                                % 如果使能了M1（某种测量或测试模式），调用LTE下行M1处理函数
                                if strcmpi(sim_para.M1.enable,'YES')
                                    LTE_DL_M1_system(time_agc_factor, fre_agc_factor, pilot_chan_est, ...
                                        ue_pilot_chan_est, channel_est_subframe, demapper_soft_bits, ...
                                        subframe_fre_symb, receiver_blocks_symbols, userID, n_snr, n_frame);
                                    CM_information_collect_DL(n_cell, n_user);  % 收集下行信道模型信息
                                end

                                % 计算接收机参数（用于信道模型）
                                CM_receiver_para_compute('DOWNLINK', n_snr, n_frame, n_subframe);

                            else   % NR模式下行接收
                                if exist('NR_DL_DE_system','file') ~= 2
                                    error('NR mode requires NR_DL_DE_system.m');
                                end
                                % 调用NR下行解调解码系统函数
                                nr_rx_result = NR_DL_DE_system(rx_signal, rx_signal0, userID, n_unit);
                                
                                % 如果存在接收机参数计算函数，则调用
                                if exist('CM_receiver_para_compute','file') == 2
                                    CM_receiver_para_compute('DOWNLINK', n_snr, n_frame, n_subframe);
                                end
                            end
                        end
                    end

                elseif strcmpi(sim_para.sim_link_type,'UPLINK')   % 上行链路处理

                    if strcmpi(frame_cfg.rat_mode,'LTE')   % LTE模式上行

                        n_cell = getCellIndexfromID(targetCellID); % 获取小区索引
                        N_FFT = cell_para{1, n_cell}.N_FFT;        % FFT点数
                        cp_type = cell_para{1, n_cell}.cp_type;    % 循环前缀类型（常规或扩展）

                        % 获取第一个OFDM符号的循环前缀长度（用于AGC定时）
                        if strcmpi(cp_type,'NORMAL')
                            N_CP1 = cell_para{1, n_cell}.normal_cp_length(1);
                        else
                            N_CP1 = cell_para{1, n_cell}.ex_cp_length(1);
                        end

                        % 时域AGC（自动增益控制）：计算增益因子并应用到接收信号
                        agc_factor = AGC_unit(rx_signal(:, N_CP1+1:N_CP1+N_FFT));
                        agc_signal = agc_factor * rx_signal;   % 增益调整后的信号
                        agc_signal0 = agc_factor * rx_signal0; % 调整理想信号

                        % 检测PRACH（物理随机接入信道）
                        if strcmpi(user_para{n_cell,1}.enable_UL_channel{1},'PRACH')
                            preamble_format = cell_para{1, n_cell}.prach.format;   % 前导格式
                            subframe_indicator = cell_para{n_cell}.subframe_indicator;
                            % 累积接收信号用于PRACH检测（可能需要多个子帧）
                            rx_signal_all = [rx_signal_all rx_signal];
                            rx_signal0_all = [rx_signal0_all rx_signal0];
                            LTE_UL_PRACH(preamble_format, subframe_indicator, n_subframe, n_snr, targetCellID, rx_signal_all, rx_signal0_all);
                        end

                        % 上行OFDM解调（时域转频域）
                        [rx_subframe_symb, rx_subframe_symb0] = UL_ofdm_demodulation(agc_signal, agc_signal0, targetCellID);
                        n_case = sim_para.test_vector_case;   % 测试向量用例编号

                        % 如果运行模式为测试向量生成，则写入二进制探测文件
                        if strcmpi(sim_para.link_run_mode,'TESTVECTOR')
                            filename = strcat('.\testvector\pusch\de_ant_time_data_case_',num2str(n_case),'.am');
                            bc_probe(filename,16,1,'de_ant_error',reshape(rx_signal.',1,[]));

                            filename = strcat('.\testvector\pusch\de_agc_time_data_case_',num2str(n_case),'.am');
                            bc_probe(filename,16,1,'de_agc_error',reshape(agc_signal.',1,[]));

                            filename = strcat('.\testvector\pusch\de_FFT_data_case_',num2str(n_case),'.am');
                            bc_probe(filename,16,1,'de_FFT_error',reshape(permute(rx_subframe_symb,[2 1 3]),1,[]));
                        end

                        n_cell = getCellIndexfromID(targetCellID);
                        userID_list = cell_para{n_cell}.userID_list;
                        user_num = length(userID_list);

                        M1.recip_temp = [];   % M1临时接收缓冲区初始化

                        for k = 1:user_num   % 遍历每个上行用户
                            userID = userID_list(k);

                            % 如果该用户尚未被检测到（避免重复处理）
                            if isempty(find(cell_para{n_cell}.detected_userID_list == userID,1))
                                % 调用LTE上行解调解码系统函数
                                [time_agc_factor, fre_agc_pucch, fre_agc_pusch, pucch_bits, pucch_symbol, ...
                                    pucch_data_channel, pucch_pilot_fre_ch, pucch_pilot_fre_ch2, ...
                                    pusch_data_channel, pusch_pilot_fre_ch, pusch_pilot_fre_ch2, ...
                                    pusch_detected_soft_bits, receiver_blocks_symbols, srs_ch1, srs_ch2] ...
                                    = LTE_UL_DE_system(userID, rx_signal, rx_signal0);

                                % 如果使能M1，调用LTE上行M1处理函数
                                if strcmpi(sim_para.M1.enable,'YES')
                                    LTE_UL_M1_system(time_agc_factor, fre_agc_pucch, fre_agc_pusch, ...
                                        pucch_bits, pucch_symbol, pucch_pilot_fre_ch, pucch_pilot_fre_ch2, ...
                                        pusch_pilot_fre_ch, pusch_pilot_fre_ch2, pusch_detected_soft_bits, ...
                                        receiver_blocks_symbols, srs_ch1, srs_ch2, userID, n_snr, n_frame);
                                end

                                % 计算上行接收机参数
                                CM_receiver_para_compute('UPLINK', n_snr, n_frame, n_subframe);
                            end
                        end

                    else   % NR模式上行
                        if exist('NR_UL_DE_system','file') ~= 2
                            error('NR mode requires NR_UL_DE_system.m');
                        end
                        % 调用NR上行解调解码系统函数
                        nr_rx_result = NR_UL_DE_system(targetCellID, rx_signal, rx_signal0, n_unit);
                        
                        if exist('CM_receiver_para_compute','file') == 2
                            CM_receiver_para_compute('UPLINK', n_snr, n_frame, n_subframe);
                        end
                    end

                end   % 结束上行链路处理
            end   % 结束unit_active判断
        end   % 结束n_unit循环
    end   % 结束n_frame循环
end   % 结束n_snr循环

%% 存储和结果输出
if strcmpi(frame_cfg.rat_mode,'LTE')   % LTE模式的结果汇总和输出

    save result_recip_pucch user_para   % 保存用户参数到mat文件（PUCCH相关）

    % 仿真结果及统计输出
    if strcmpi(sim_para.CS_process,'ENABLED')   % 如果使能了小区搜索过程
        CS.sim_CER(n_snr) = CS.cs_correct_num / CS.cs_process_num;   % 计算小区搜索错误率

        [n_cell, n_user] = getUserIndexfromID(targetUserID); 
        N_ID_CELL = cell_para{1,1}.cellID;        % 真实小区ID
        correct_index = find(CELL_ID_detect == N_ID_CELL);   % 检测正确的索引
        correct_num = length(correct_index);
        N = CS.cs_process_num;

        if correct_num ~= 0
            search_time = zeros(1, correct_num);
            search_time(2:end) = correct_index(2:end) - correct_index(1:end-1); % 搜索间隔
            search_time(1) = correct_index(1);
            M = max(search_time);

            CDF = [];
            detect_num = [];

            for inum = 1:M
                detect_num(inum) = length(find(search_time == inum)); 
                if inum == 1
                    CDF(inum) = detect_num / N; 
                else
                    CDF(inum) = CDF(inum-1) + detect_num(inum) / ceil((N/inum)); 
                end
            end

            CDF = cumsum(detect_num) / max(cumsum(detect_num));
            CS.sim_CDF{n_snr} = CDF;          % 累积分布函数
        else
            CS.sim_CDF{n_snr} = Inf;           % 无正确检测时设为无穷
        end

        CS.sim_foe_coarse(n_snr,:) = foe_coarse; % 存储粗频偏估计结果
        CS.sim_foe_fine(n_snr,:) = foe_fine;     % 存储细频偏估计结果
        CS.sim_pos(n_snr,:) = pos;               % 存储同步位置
        CS.sim_CELL_ID(n_snr,:) = CELL_ID_detect;% 存储检测到的小区ID
        save CS_result CS sim_para sys_para;     % 保存小区搜索结果
    end

    fid = fopen(sim_para.resultFileName, 'w+');  % 打开结果文件用于写入
    userID_list = cell_para{1}.userID_list;
    user_num = length(userID_list);

    subframe_index = find(cell_para{1,1}.subframe_indicator, 1, 'first'); % 找到第一个激活的子帧索引
    if isempty(subframe_index)
        subframe_index = 1;
    end
    subframe_channel_config = cell_para{1,1}.subframe_channel_config{subframe_index}; % 该子帧的信道配置

    for n_user = 1:user_num   % 遍历每个用户，统计误块率和误比特率

        if strcmpi(sim_para.sim_link_type,'DOWNLINK')
            psch = user_para{1,n_user}.pdsch;   % 下行取PDSCH结构
        else
            psch = user_para{1,n_user}.pusch;   % 上行取PUSCH结构
        end

        % 统计每个HARQ进程（SAW）和码字的错误块数
        for n_tread = 1:psch.CM.NUM_SAW
            cw = psch.codeword_num;
            for n_block = 1:cw
                if psch.CM.T_trans(n_tread, n_block) ~= 0   % 如果传输次数不为0（表示有错误？具体逻辑需结合定义）
                    psch.TBS_control.error_blocks_num(n_block) = psch.TBS_control.error_blocks_num(n_block) + 1;
                    psch.TBS_control.error_source_bits_num(n_block) = psch.TBS_control.error_source_bits_num(n_block) + 1;
                end
            end
        end

        % 汇总结果到RESULT字段
        psch.RESULT.totalBlockNum(:, n_snr) = psch.TBS_control.total_blocks_num;
        psch.RESULT.totalSrcbitNum(:, n_snr) = psch.TBS_control.total_source_bits_num;
        psch.RESULT.totalRawbitNum(:, n_snr) = psch.TBS_control.total_raw_bits;
        psch.RESULT.errorBlockNum(:, n_snr) = psch.TBS_control.error_blocks_num;
        psch.RESULT.errorSrcbitNum(:, n_snr) = psch.TBS_control.error_source_bits_num;
        psch.RESULT.errorRawbitNum(:, n_snr) = psch.TBS_control.error_raw_bits;
        psch.RESULT.through_put(:, n_snr) = psch.TBS_control.through_bits / TotalFrameNum(n_snr);
        psch.RESULT.through_put_Hz(:, n_snr) = psch.TBS_control.through_bits ./ psch.TBS_control.total_VRB_num;

        % 计算BLER（误块率）、BER（误比特率）和原始BER
        psch.RESULT.BLER(:, n_snr) = psch.RESULT.errorBlockNum(:, n_snr) ./ psch.RESULT.totalBlockNum(:, n_snr);
        psch.RESULT.BER(:, n_snr) = psch.RESULT.errorSrcbitNum(:, n_snr) ./ psch.RESULT.totalSrcbitNum(:, n_snr);
        psch.RESULT.rawBER(:, n_snr) = psch.RESULT.errorRawbitNum(:, n_snr) ./ psch.RESULT.totalRawbitNum(:, n_snr);

        if strcmpi(sim_para.sim_link_type,'UPLINK')   % 上行额外统计CQI/ACK/RI错误率
            psch.RESULT.CQI_BLER(:, n_snr) = psch.TBS_control.CQI_err_num ./ TotalFrameNum(n_snr);
            psch.RESULT.ACK_BLER(:, n_snr) = psch.TBS_control.ACK_err_num ./ TotalFrameNum(n_snr);
            psch.RESULT.RI_BLER(:, n_snr) = psch.TBS_control.RI_err_num ./ TotalFrameNum(n_snr);

            save PRACH_results user_para cell_para sim_para;   % 保存PRACH相关结果

            % 如果子帧配置中包含PUCCH，则处理PUCCH统计
            if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PUCCH'))
                n_cell = 1;
                pucch_format = user_para{n_cell, n_user}.pucch.format;

                if ~isempty(strfind(upper(pucch_format), '2'))   % PUCCH格式2（CQI）
                    user_para{n_cell, n_user}.pcch.RESULT.CQI_BLER(n_snr) = ...
                        user_para{n_cell, n_user}.RESULT.errorCQIblockNum(n_snr) ./ ...
                        user_para{n_cell, n_user}.RESULT.totalCQIblockNum(n_snr);
                end

                % 格式1/1a/1b（ACK/NACK或SR）
                if ~isempty(strfind(upper(pucch_format), '1')) || ...
                   ~isempty(strfind(upper(pucch_format), 'A')) || ...
                   ~isempty(strfind(upper(pucch_format), 'B'))

                    user_para{n_cell, n_user}.pcch.RESULT.ACK_BLER(n_snr) = ...
                        user_para{n_cell, n_user}.RESULT.errorACKblockNum(n_snr) ./ ...
                        user_para{n_cell, n_user}.RESULT.totalACKblockNum(n_snr);

                    % 如果使能了调度请求（SR），统计虚警和漏检率
                    if ~isempty(strfind(upper(user_para{n_cell, n_user}.pucch.SR_instance), 'YES'))
                        user_para{n_cell, n_user}.pcch.RESULT.pucch.SRfalsealarm_result(n_snr) = ...
                            user_para{1, n_user}.pucch.SR_falsealarm(n_snr) / TotalFrameNum(n_snr);
                        user_para{n_cell, n_user}.pcch.RESULT.pucch.SRmiss_result(n_snr) = ...
                            user_para{1, n_user}.pucch.SR_miss(n_snr) / TotalFrameNum(n_snr);
                    end
                end
            end
        end

        % 将更新后的PDSCH或PUSCH结构存回用户参数
        if strcmpi(sim_para.sim_link_type,'DOWNLINK')
            user_para{1, n_user}.pdsch = psch;
        else
            user_para{1, n_user}.pusch = psch;
        end

        % 以下为各物理信道的BLER/BER统计（若子帧配置中包含该信道）
        if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PBCH'))
            n_cell = 1;
            user_para{n_cell, n_user}.pbch.BLER(n_snr) = user_para{n_cell, n_user}.pbch.errorBlockNum(n_snr) / user_para{n_cell, n_user}.pbch.totalBlockNum(n_snr);
            user_para{n_cell, n_user}.pbch.BER(n_snr) = user_para{n_cell, n_user}.pbch.errorSrcbitNum(n_snr) / user_para{n_cell, n_user}.pbch.totalSrcbitNum(n_snr);
            user_para{n_cell, n_user}.pbch.rawBER(n_snr) = user_para{n_cell, n_user}.pbch.errorRawbitNum(n_snr) / user_para{n_cell, n_user}.pbch.totalRawbitNum(n_snr);
        end

        if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PDCCH'))
            n_cell = 1;
            user_para{n_cell, n_user}.pdcch.BLER(n_snr) = user_para{n_cell, n_user}.pdcch.errorBlockNum(n_snr) / user_para{n_cell, n_user}.pdcch.totalBlockNum(n_snr);
            user_para{n_cell, n_user}.pdcch.BER(n_snr) = user_para{n_cell, n_user}.pdcch.errorSrcbitNum(n_snr) / user_para{n_cell, n_user}.pdcch.totalSrcbitNum(n_snr);
            user_para{n_cell, n_user}.pdcch.rawBER(n_snr) = user_para{n_cell, n_user}.pdcch.errorRawbitNum(n_snr) / user_para{n_cell, n_user}.pdcch.totalRawbitNum(n_snr);
        end

        if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PHICH'))
            n_cell = 1;
            user_para{n_cell, n_user}.phich.BLER(n_snr, :) = ...
                user_para{n_cell, n_user}.phich.errorBlockNum(n_snr, :) ./ user_para{n_cell, n_user}.phich.totalBlockNum(n_snr, :);
        end

        if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PCFICH'))
            n_cell = 1;
            user_para{n_cell, n_user}.pcfich.BLER(n_snr) = user_para{n_cell, n_user}.pcfich.errorBlockNum(n_snr) / user_para{n_cell, n_user}.pcfich.totalBlockNum(n_snr);
        end
    end

    % 结果输出到文本文件
    fid = fopen(sim_para.resultFileName, 'w+');
    userID_list = cell_para{1}.userID_list;
    user_num = length(userID_list);

    fprintf(fid, 'SNR = %s\n', num2str(sim_para.SNR));

    if strcmpi(sim_para.sim_link_type,'DOWNLINK')   % 下行输出

        for n_user = 1:user_num
            cw = user_para{1, n_user}.pdsch.codeword_num;
            PDSCH_BLER = user_para{1, n_user}.pdsch.RESULT.BLER(1:cw, :) %#ok<NOPRT>
            PDSCH_BER  = user_para{1, n_user}.pdsch.RESULT.BER(1:cw, :)  %#ok<NOPRT>

            fprintf(fid, '*********************************************\r\n');
            fprintf(fid, '******下行仿真结果输出***********************\r\n');

            if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PBCH'))
                fprintf(fid, '********PBCH*****************\r\n');
                fprintf(fid, 'PBCH BLER = %s\n PBCH BER= %s\n PBCH rawBER = %s\n', ...
                    num2str(user_para{1, n_user}.pbch.BLER), ...
                    num2str(user_para{1, n_user}.pbch.BER), ...
                    num2str(user_para{1, n_user}.pbch.rawBER));
            end

            if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PDCCH'))
                fprintf(fid, '********PDCCH*****************\n');
                fprintf(fid, 'PDCCH BLER = %s\n PDCCH BER= %s\n PDCCH rawBER = %s\n', ...
                    num2str(user_para{1, n_user}.pdcch.BLER), ...
                    num2str(user_para{1, n_user}.pdcch.BER), ...
                    num2str(user_para{1, n_user}.pdcch.rawBER));
            end

            if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PHICH'))
                fprintf(fid, '********PHICH*****************\n');
                fprintf(fid, 'PHICH error indicator = %s\n', num2str(user_para{1, n_user}.phich.BLER));
            end

            if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PCFICH'))
                fprintf(fid, '********PCFICH*****************\n');
                fprintf(fid, 'PCFICH error indicator = %s \t', num2str(user_para{1, n_user}.pcfich.BLER));
            end
        end
        fclose(fid);

        if exist('CM_pdsch_para_results_output', 'file') == 2
            CM_pdsch_para_results_output;   % 输出PDSCH信道模型参数结果
        end

    else   % 上行输出

        if exist('CM_pusch_para_results_output', 'file') == 2
            CM_pusch_para_results_output;   % 输出PUSCH信道模型参数结果
        end

        fid = fopen(sim_para.resultFileName, 'a+');   % 追加模式打开

        for n_user = 1:user_num
            cw = user_para{1, n_user}.pusch.codeword_num;
            PUSCH_BLER = user_para{1, n_user}.pusch.RESULT.BLER(1:cw, :) %#ok<NOPRT>
            PUSCH_BER  = user_para{1, n_user}.pusch.RESULT.BER(1:cw, :)  %#ok<NOPRT>

            if ~isempty(strfind(cat(2, subframe_channel_config{:}), 'PUCCH'))
                pucch_format = user_para{1, n_user}.pucch.format;

                if ~isempty(strfind(upper(pucch_format), '2'))
                    fprintf(fid, 'PUCCH CQI_BLER = %s\t\t\n', num2str(user_para{1, n_user}.pcch.RESULT.CQI_BLER));
                end

                if ~isempty(strfind(upper(pucch_format), '1')) || ...
                   ~isempty(strfind(upper(pucch_format), 'A')) || ...
                   ~isempty(strfind(upper(pucch_format), 'B'))

                    if ~isempty(strfind(upper(user_para{1, n_user}.pucch.SR_instance), 'YES'))
                        fprintf(fid, 'PUCCH SR_false_alarm = %s\t\t\n', num2str(user_para{1, n_user}.pcch.RESULT.pucch.SRfalsealarm_result));
                        fprintf(fid, 'PUCCH SR_miss = %s\t\t\n', num2str(user_para{1, n_user}.pcch.RESULT.pucch.SRmiss_result));
                    end

                    fprintf(fid, 'PUCCH ACK_BLER = %s\t\t\n', num2str(user_para{1, n_user}.pcch.RESULT.ACK_BLER));
                end
            end
        end
        fclose(fid);
    end

else   % NR模式的结果输出（占位）
    fid = fopen(sim_para.resultFileName, 'w+');
    fprintf(fid, 'RAT_MODE = NR\n');
    fprintf(fid, 'SNR = %s\n', num2str(sim_para.SNR));
    fprintf(fid, 'Note: NR skeleton is enabled in LTE_LINK_MY.m.\n');
    fprintf(fid, 'Please add NR result aggregation/output in the next step.\n');
    fclose(fid);

    save NR_result_stub sim_para sys_para cell_para user_para frame_cfg;   % 保存NR仿真中间结果
end

toc   % 打印仿真总运行时间

%%
% 删除添加的路径（与开头添加的路径对应，保持环境清洁）
switch upper(mexext)
    case 'DLL'
        rmpath '.\dll\'
    case 'MEXW32'
        rmpath '.\mexw32\'
    case 'MEXW64'
        rmpath '.\mexw64\'
    otherwise
end
