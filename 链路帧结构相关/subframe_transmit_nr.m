function [rx_signal, rx_signal0] = subframe_transmit_nr(n_snr, n_frame, n_slot)
% subframe_transmit_nr - NR模式下子帧（时隙）发射与信道处理函数
%
% 功能描述：
%   本函数用于NR系统的物理层仿真中，完成一个时隙（slot）的完整发射链路处理：
%     1) 根据当前时隙的有效链路方向（下行/上行）确定发射端和接收端的天线数；
%     2) 遍历所有小区，对每个激活的小区生成该时隙的发射信号（下行时调用DL_slot_process_nr，
%        上行时遍历小区内所有激活的用户，调用UL_slot_process_nr生成每个用户的发射信号）；
%     3) 将发射信号通过无线信道（或固定信道）得到接收信号；
%     4) 添加加性高斯白噪声（AWGN），返回加噪后的接收信号和理想无噪信号。
%
% 输入参数：
%   n_snr   : 当前信噪比点索引（用于从sim_para.SNR中获取实际SNR值）
%   n_frame : 帧号（10ms帧）
%   n_slot  : 当前时隙号（在帧内的索引）
%
% 输出参数：
%   rx_signal  : 经过信道和噪声叠加后的接收信号矩阵，尺寸为 [Nr, slot_sample_num]
%                Nr为接收天线数（下行时为UE天线数，上行时为基站天线数）
%   rx_signal0 : 理想无噪接收信号（仅经过信道，未加噪声），尺寸同rx_signal

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局结构体：cell_para, user_para, sys_para, sim_para, frame_cfg,
                   % downlink_channel_para, uplink_channel_para等

% 关键注释：
% 1) 先按 NR runtime 计算当前 slot 有效方向；
% 2) UL 分支显式定义 N_ID_CELL。

% ========================== 1. 获取当前时隙的链路方向 ==========================
% 调用NR配置计算函数，预先计算当前时隙的运行时信息（包括effective_link_type等）
sim_config_compute_nr(n_frame, n_slot);

% 从小区1的nr运行时结构中获取当前时隙的有效链路类型（'DOWNLINK' 或 'UPLINK'）
link_type = cell_para{1,1}.nr.runtime.current_effective_link_type;

% 根据链路方向确定接收天线数Nr
if strcmpi(link_type, 'DOWNLINK')
    % 下行链路：接收端是UE，因此接收天线数为下行信道参数中定义的UE天线数
    Nr = downlink_channel_para{1,1}.Nr;
else
    % 上行链路：接收端是gNB，因此接收天线数为上行信道参数中定义的基站天线数
    Nr = uplink_channel_para{1,1}.Nr;
end

% ========================== 2. 初始化接收信号矩阵 ==========================
slot_sample_num = frame_cfg.samples_per_unit;   % 每个时隙的时域采样点数（由帧结构定义）
rx_signal  = zeros(Nr, slot_sample_num);        % 初始化加噪接收信号矩阵为全零
rx_signal0 = zeros(Nr, slot_sample_num);        % 初始化无噪接收信号矩阵为全零

% ========================== 3. 获取系统中所有小区列表 ==========================
cellID_list = sys_para.cellID_list;    % 系统参数中定义的小区ID列表（例如[1]）
CELL_NUM = length(cellID_list);        % 小区总数

% 计算当前处理时刻（绝对时间），用于信道冲激响应的时间变化
% global_unit_index 是全局单元索引（每帧包含unit_per_frame个单元，LTE为10子帧，NR为多个时隙）
% 单元持续时间 = 1ms / unit_per_subframe（每个子帧包含的单元数），再乘以全局索引得到秒为单位的时间
cur_time = sim_para.global_unit_index * (1e-3 / frame_cfg.unit_per_subframe);

% ========================== 4. 遍历所有小区 ==========================
for n_cell = 1:CELL_NUM

    % 判断当前小区在当前时隙是否激活（根据slot_indicator配置）
    if ~frame_is_unit_active(n_cell, n_slot)
        continue;   % 未激活则跳过该小区
    end

    N_ID_CELL = cellID_list(n_cell);   % 当前小区的小区ID

    % -------------------- 4.1 下行链路处理 --------------------
    if strcmpi(link_type, 'DOWNLINK')
        % 调用下行时隙处理函数，生成该小区的发射时域波形
        % tx_slot_signal 尺寸为 [Nt, slot_sample_num]，Nt为基站发射天线数
        tx_slot_signal = DL_slot_process_nr(N_ID_CELL, n_frame, n_slot);

        % 将发射信号通过无线信道（或固定信道）
        if strcmpi(sim_para.link_run_mode, 'RECEIVER')
            % 接收机测试模式：使用固定信道矩阵（不随时间变化）
            FixedChannel = sim_para.receiver.FixedChannel;   % 固定信道矩阵
            signal_out = FixedChannel * tx_slot_signal;      % 线性相乘模拟信道
        else
            % 正常模式：调用无线信道模型函数，根据当前时间、链路方向等生成时变信道响应
            % 返回经过信道后的信号（无噪声）以及信道结构体（此处忽略第二个输出）
            [signal_out, ~] = wireless_channel(tx_slot_signal, cur_time, 'DOWNLINK', N_ID_CELL, n_snr, n_frame);
        end

        % 获取当前SNR值（线性值或dB，取决于sim_para.SNR的定义，通常为dB）
        SNR = sim_para.SNR(n_snr);
        % 根据信号功率和SNR生成噪声，并叠加到signal_out上
        % noise_signal: 加噪后的完整信号（含噪声），noiseless_signal: 无噪信号（即signal_out本身）
        [noise_signal, noiseless_signal] = noise_adding(signal_out, SNR);

        % 将当前小区的接收信号累加到总接收信号中（多小区场景）
        rx_signal  = rx_signal  + noise_signal;
        rx_signal0 = rx_signal0 + noiseless_signal;

    % -------------------- 4.2 上行链路处理 --------------------
    else
        if exist('UL_slot_process_nr', 'file') ~= 2
            error(['subframe_transmit_nr: UL link selected but UL_slot_process_nr.m is missing. ', ...
                   'Please implement the NR UL waveform generator first.']);
        end
        if exist('NR_UL_Timing_process', 'file') ~= 2
            error(['subframe_transmit_nr: UL link selected but NR_UL_Timing_process.m is missing. ', ...
                   'Please implement the NR UL timing/channel wrapper first.']);
        end

        % 获取当前小区下的所有用户ID列表
        cell_userID_list = cell_para{1, n_cell}.userID_list;
        cell_userNum = length(cell_userID_list);

        % 遍历该小区内的每个用户
        for n_user = 1:cell_userNum
            userID = user_para{n_cell, n_user}.userID;                     % 用户ID
            ulEnable = user_para{n_cell, n_user}.enable_UL_channel;        % 上行信道使能标志

            % 判断上行是否禁用（enable_UL_channel可能为'NULL'或空数组）
            if ischar(ulEnable)
                isNull = strcmpi(ulEnable, 'NULL');
            else
                isNull = isempty(ulEnable);
            end

            if isNull
                continue;   % 若禁用上行，则跳过该用户
            end

            % 生成该用户的上行发射时隙波形
            tx_slot_signal = UL_slot_process_nr(userID, n_frame, n_slot);

            % 调用上行定时处理函数，模拟用户发射信号到达基站的时间偏移（TA调整）
            % 该函数内部会调用无线信道模型，并考虑定时提前量，返回经过信道后的信号
            [signal_out, ~] = NR_UL_Timing_process( ...
                n_snr, userID, tx_slot_signal, n_frame, n_slot, cur_time);

            % 将当前用户的接收信号累加到小区总接收信号中（多用户叠加）
            rx_signal = rx_signal + signal_out;
            % 注意：上行分支中没有分别累加无噪信号，而是在循环结束后统一添加噪声
        end

        % 上行链路在所有用户叠加完成后，统一添加噪声
        SNR = sim_para.SNR(n_snr);
        % 注意：这里将累加后的rx_signal作为输入，同时输出加噪后的rx_signal和对应的无噪信号rx_signal0
        [rx_signal, rx_signal0] = noise_adding(rx_signal, SNR);
    end
end

end  % 函数结束
