function sim_config_change_nr
% sim_config_change_nr - 纯NR物理层配置入口函数
%
% 功能描述：
%   本函数用于NR（New Radio）模式下的系统参数初始化，设置仿真控制参数、
%   系统参数、小区参数和用户参数。与LTE模式不同，本函数不再兼容LTE链路，
%   只生成NR相关的配置字段。
%
% 主要任务：
%   1) 清空核心全局对象（sim_para, sys_para, cell_para, user_para, user_data），
%      避免残留旧LTE参数污染；
%   2) 设置RAT模式为NR，并配置灵活时隙的处理方向；
%   3) 定义基本Numerology（子载波间隔、FFT点数、采样率等）；
%   4) 配置仿真参数（SNR点、帧数、接收机算法等）；
%   5) 配置系统参数（小区ID列表、NR带宽等）；
%   6) 配置小区参数（小区ID、BWP、SSB、CORESET、PDCCH、TDD时隙图样等）；
%   7) 配置用户参数（PDSCH、PUSCH、PUCCH的详细配置）；
%   8) 配置帧结构参数；
%   9) 初始化用户数据缓存。
%
% 调用方式：
%   无输入输出参数，直接修改全局结构体。

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量：sim_para, sys_para, cell_para, user_para, user_data, frame_cfg等

%% 清空核心对象，避免残留旧LTE参数污染
sim_para  = [];    % 仿真控制参数结构体（清空后重新构建）
sys_para  = [];    % 系统级公共参数结构体
cell_para = {};    % 小区参数 cell 数组（每个小区一个结构体）
user_para = {};    % 用户参数 cell 数组（二维：小区×用户）
user_data = [];    % 用户数据缓存（三维：小区×用户×方向，用于存储收发数据）

%% =======================================================================
% 1. RAT 总开关
% =======================================================================
frame_cfg.flexible_slot_as = 'DOWNLINK'; % 当遇到灵活时隙（slot indicator = 0）时，默认当作下行处理
frame_cfg.enable_legacy_cm_timing_nr = 'YES'; % NR 模式默认复用 LTE legacy CM 时序/频偏控制初始化链

%% =======================================================================
% 2. 仿真基础参数
% =======================================================================
n_cell = 1;          % 仿真中的小区个数（本仿真配置为单小区）
n_user = 1;          % 仿真中的用户个数（每个小区一个用户）

cellID = 3;          % 物理层小区标识 (PCI)，用于加扰、序列生成等
userID = 20;         % 用户标识，用于高层区分用户

% Numerology (参数集)
mu  = 1;             % 子载波间隔配置索引，μ=1 对应 SCS = 15×2^1 = 30 kHz
scs = 30e3;          % 子载波间隔 (Hz)，决定 OFDM 符号长度和时隙长度

% 载波参数
bandwidth_mhz = 20;  % 系统带宽 (MHz)，用于确定资源块数量等
N_RB = 51;           % 下行活动带宽内的资源块 (RB) 数量。FR1 20MHz / 30kHz SCS 典型值为 51
N_FFT = 1024;        % FFT 点数，决定了基带采样率和子载波总数
Fs = scs * N_FFT;    % 基带采样率 = 30e3 * 1024 = 30.72 MHz

slots_per_subframe = 2^mu;           % 每个子帧 (1ms) 内的时隙数，μ=1 时为 2
slots_per_frame    = 10 * 2^mu;      % 每个无线帧 (10ms) 内的时隙数，μ=1 时为 20
symbols_per_slot   = 14;             % 每个时隙的 OFDM 符号数（常规 CP 固定为 14）
slot_duration      = 1e-3 / slots_per_subframe; % 单个时隙的时长 (s)，μ=1 时为 0.5 ms
samples_per_slot   = round(Fs * slot_duration); % 每个时隙的基带采样点数

%% =======================================================================
% 3. sim_para (仿真控制参数)
% =======================================================================
sim_para.rat_mode = 'NR';                    % 标识当前为 NR 模式
sim_para.link_run_mode = 'SIMULATION';       % 链路运行模式：仿真、测试向量或纯接收机
sim_para.sim_link_type = 'DOWNLINK';         % 仿真链路方向初始值，实际会被每个时隙的方向覆盖
sim_para.targetID = userID;                  % 目标用户 ID，用于接收机处理
sim_para.SNR = [24];                         % 仿真信噪比 (dB) 向量（此处只配置了一个点）
sim_para.SNR_NUM = length(sim_para.SNR);     % SNR 点数
sim_para.TotalFrameNum = 40 * ones(1, sim_para.SNR_NUM); % 每个 SNR 点仿真的无线帧数
sim_para.resultFileName = '.\results\nr_simulation_result.am'; % 结果保存文件路径

sim_para.global_subframe_index = [];         % 全局子帧计数器，用于跨函数同步
sim_para.global_unit_index = [];             % 全局基本单元（时隙）计数器
sim_para.test_vector_case = [];              % 测试向量编号（仅用于一致性测试）

% NR 专用运行控制
sim_para.nr.enable = 'YES';                  % 使能 NR 处理分支
sim_para.nr.frequency_range = 'FR1';         % 频率范围：FR1 (<6GHz) 或 FR2 (毫米波)
sim_para.nr.band = 'n78';                    % 工作频段号 (3.5 GHz 附近)
sim_para.nr.duplex_mode = 'TDD';             % 双工模式：TDD 或 FDD

% 接收机算法配置
sim_para.nr.rx.enable = 'YES';               % 使能接收机处理
sim_para.nr.rx.equalizer = 'MMSE';           % 均衡算法：'ZF' 或 'MMSE'
sim_para.nr.rx.chest_method = 'DMRS_MMSE';   % 信道估计方法：基于 DMRS 的 LS 或 MMSE
sim_para.nr.rx.time_sync_method = 'DMRS';    % 时间同步方法：基于 SSB 或 DMRS
sim_para.nr.rx.residual_cfo_method = 'DMRS'; % 残余频偏估计方法
sim_para.nr.rx.ptrs_phase_tracking = 'YES';  % 是否使能 PTRS 相位跟踪
sim_para.nr.rx.perfect_timing = 'NO';        % 是否使用理想定时（仿真时关闭）
sim_para.nr.rx.perfect_chest = 'NO';         % 是否使用理想信道估计
sim_para.nr.rx.ldpc_max_iter = 25;           % LDPC 解码最大迭代次数
sim_para.nr.rx.softbuffer_enable = 'YES';    % 是否使能 HARQ 软缓存

% 关闭 LTE 专用流程
sim_para.CS_process = 'DISABLED';            % 禁用小区搜索过程 (LTE 遗留)
sim_para.M1.enable = 'NO';                   % 禁用 M1 接口 (LTE 遗留)

% NR 模式下默认复用 LTE legacy CM 控制路径（时序/频偏/功率控制）
sim_para.CM.DL_TA_FLAG = 'Fixed_Timing_Error';
sim_para.CM.DL_FOE_FLAG = 'No_Initial_FOE_No_Control';
sim_para.CM.UL_TA_FLAG = 'No_Control';
sim_para.CM.powercontrol.enabled = 'NO';
sim_para.CM.deltaTA = 0;

%% =======================================================================
% 4. sys_para (系统参数)
% =======================================================================
sys_para.cellID_list = [cellID];             % 系统中所有小区的 ID 列表
sys_para.Ts = 1 / Fs;                        % 基带采样周期 (s)

sys_para.nr.enable = 'YES';                  % NR 系统级使能
sys_para.nr.bandwidth_mhz = bandwidth_mhz;   % 系统带宽 (MHz)
sys_para.nr.sample_rate = Fs;                % 基带采样率 (Hz)
sys_para.nr.frequency_range = 'FR1';         % 频率范围
sys_para.nr.band = 'n78';                    % 频段

%% =======================================================================
% 5. cell_para（小区参数：公共字段 + 纯 NR 字段）
% =======================================================================
cell_para{1, n_cell}.cellID = cellID;                     % 小区标识
cell_para{1, n_cell}.userID_list = [userID];              % 该小区服务的用户 ID 列表

% 以下字段为上层通用框架读取，并非 LTE 兼容遗留
cell_para{1, n_cell}.frame_type = 'NR';                   % 帧结构类型：NR
cell_para{1, n_cell}.cp_type = 'NORMAL';                  % 循环前缀类型：常规 CP
cell_para{1, n_cell}.sc_spacing = scs;                    % 子载波间隔 (Hz)
cell_para{1, n_cell}.N_FFT = N_FFT;                       % FFT 点数
cell_para{1, n_cell}.N_RB_DL = N_RB;                      % 下行资源块数量
cell_para{1, n_cell}.N_RB_UL = N_RB;                      % 上行资源块数量
cell_para{1, n_cell}.BS_phy_antenna_num = 2;              % 基站物理天线数
cell_para{1, n_cell}.BS_antenna_port_num = 2;             % 基站天线端口数（逻辑端口）
cell_para{1, n_cell}.BS_antenna_type = 'ULA';             % 基站天线阵列类型：均匀线阵
cell_para{1, n_cell}.BS_antenna_spacing = 0.5;            % 天线间距（以波长为单位）
cell_para{1, n_cell}.detected_userID_list = [];           % 小区搜索检测到的用户列表（接收端用）

% ---------------- NR carrier / grid 参数 ----------------
cell_para{1, n_cell}.nr.enable = 'YES';                   % 使能 NR 小区配置
cell_para{1, n_cell}.nr.NCellID = cellID;                 % NR 小区标识（同 PCI）
cell_para{1, n_cell}.nr.mu = mu;                          % 参数集索引 μ
cell_para{1, n_cell}.nr.scs = scs;                        % 子载波间隔 (Hz)
cell_para{1, n_cell}.nr.scs_khz = scs / 1e3;              % 子载波间隔 (kHz)
cell_para{1, n_cell}.nr.Nfft = N_FFT;                     % FFT 点数
cell_para{1, n_cell}.nr.sample_rate = Fs;                 % 采样率
cell_para{1, n_cell}.nr.symbols_per_slot = symbols_per_slot;   % 每时隙符号数 (14)
cell_para{1, n_cell}.nr.slots_per_subframe = slots_per_subframe; % 每子帧时隙数
cell_para{1, n_cell}.nr.slots_per_frame = slots_per_frame;       % 每帧时隙数
cell_para{1, n_cell}.nr.slot_duration = slot_duration;           % 时隙时长 (s)
cell_para{1, n_cell}.nr.samples_per_slot = samples_per_slot;     % 每时隙采样点数

% 载波频率配置
cell_para{1, n_cell}.nr.carrier.fc = 3.5e9;               % 中心频率 (Hz)
cell_para{1, n_cell}.nr.carrier.band = 'n78';             % 频段号
cell_para{1, n_cell}.nr.carrier.frequency_range = 'FR1';  % 频率范围
cell_para{1, n_cell}.nr.carrier.bandwidth_mhz = bandwidth_mhz;   % 带宽 (MHz)
cell_para{1, n_cell}.nr.carrier.NSizeGrid = N_RB;         % 载波总 RB 数
cell_para{1, n_cell}.nr.carrier.NStartGrid = 0;           % 载波起始 RB 索引（相对于 Point A）

% ---------------- NR BWP (带宽部分) 配置 ----------------
cell_para{1, n_cell}.nr.active_bwp_id = 1;                % 当前激活的 BWP ID
cell_para{1, n_cell}.nr.bwp{1}.id = 1;                    % BWP ID
cell_para{1, n_cell}.nr.bwp{1}.NStartBWP = 0;             % BWP 起始 RB 索引（相对于载波）
cell_para{1, n_cell}.nr.bwp{1}.NSizeBWP = N_RB;           % BWP 包含的 RB 数
cell_para{1, n_cell}.nr.bwp{1}.SubcarrierSpacing = scs;   % BWP 使用的子载波间隔 (Hz)
cell_para{1, n_cell}.nr.bwp{1}.CyclicPrefix = 'NORMAL';   % BWP 的循环前缀类型

% ---------------- SSB / PBCH 配置 ----------------
cell_para{1, n_cell}.nr.ssb.enable = 'NO';                % 使能 SSB 发送
cell_para{1, n_cell}.nr.ssb.block_pattern = 'CaseB';      % SSB 时频图样，Case B 对应 30 kHz SCS，Lmax=4/8
cell_para{1, n_cell}.nr.ssb.SubcarrierSpacing = 30e3;     % SSB 的子载波间隔 (Hz)
cell_para{1, n_cell}.nr.ssb.Lmax = 4;                     % SSB 波束最大数量（FR1 通常为 4 或 8）
cell_para{1, n_cell}.nr.ssb.periodicity_ms = 20;          % SSB 周期 (ms)
cell_para{1, n_cell}.nr.ssb.kSSB = 0;                     % 子载波偏移（0 表示 SSB 与公共资源块对齐）
cell_para{1, n_cell}.nr.ssb.offsetToPointA = 0;           % SSB 起始 RB 相对于 Point A 的偏移（单位 RB）
cell_para{1, n_cell}.nr.ssb.firstSymbol = 0;              % SSB 在时隙内的起始符号索引
cell_para{1, n_cell}.nr.ssb.symbols = 0:3;                % SSB 占用的符号索引（4 个符号）
cell_para{1, n_cell}.nr.ssb.active_slots = zeros(1, slots_per_frame); % 标记哪些时隙包含 SSB
cell_para{1, n_cell}.nr.ssb.active_slots(1) = 1;          % 第一个时隙发送 SSB

% ---------------- CORESET / SearchSpace / PDCCH 配置 ----------------
cell_para{1, n_cell}.nr.pdcch.enable = 'NO';
cell_para{1, n_cell}.nr.coreset.enable = 'YES';           % 使能 CORESET
cell_para{1, n_cell}.nr.coreset.id = 0;                   % CORESET ID (0 用于公共搜索空间)
cell_para{1, n_cell}.nr.coreset.duration = 2;             % CORESET 持续符号数 (1~3)
cell_para{1, n_cell}.nr.coreset.rb_start = 0;             % 频域起始 RB 索引
cell_para{1, n_cell}.nr.coreset.rb_size = 48;             % 频域 RB 大小（必须是 6 的倍数）
cell_para{1, n_cell}.nr.coreset.mapping = 'noninterleaved'; % CCE-REG 映射类型：非交织
cell_para{1, n_cell}.nr.coreset.reg_bundle_size = 6;      % REG 束大小 (L)
cell_para{1, n_cell}.nr.coreset.interleaver_size = 2;     % 交织器深度 (R)，仅交织时有效
cell_para{1, n_cell}.nr.coreset.shift_index = cellID;     % 移位索引（等于 PCI），用于 REG 捆绑交织

cell_para{1, n_cell}.nr.searchspace.enable = 'YES';       % 使能搜索空间
cell_para{1, n_cell}.nr.searchspace.id = 0;               % 搜索空间 ID
cell_para{1, n_cell}.nr.searchspace.type = 'common';      % 搜索空间类型：公共 (common) 或 UE 专用 (ue)
cell_para{1, n_cell}.nr.searchspace.first_symbol = 0;     % 时隙内监听起始符号
cell_para{1, n_cell}.nr.searchspace.monitoring_slot_period = 1; % 监听周期（时隙为单位）
cell_para{1, n_cell}.nr.searchspace.slot_offset = 0;      % 周期内的时隙偏移
cell_para{1, n_cell}.nr.searchspace.duration_slots = 1;   % 连续监听的时隙数
cell_para{1, n_cell}.nr.searchspace.AL = 4;               % 聚合等级 (1,2,4,8,16)

% ---------------- TDD 时隙方向配置 ----------------
cell_para{1, n_cell}.nr.duplex_mode = 'TDD';              % 双工模式
cell_para{1, n_cell}.nr.slot_indicator = ones(1, slots_per_frame); % 预留字段（部分代码可能用于快速查询）

% 时隙链路方向配置：1 表示下行，-1 表示上行，0 表示灵活
slot_link_pattern_5ms = [-1 1 1 1 1 0 1 1 1 1];       % 5ms 半帧内 10 个时隙的方向
cell_para{1, n_cell}.nr.slot_link_config = [slot_link_pattern_5ms slot_link_pattern_5ms]; % 10ms 帧内共 20 时隙

% 每个时隙的信道清单（用于指示该时隙可能发送/接收的信道类型）
cell_para{1, n_cell}.nr.slot_channel_config = cell(1, slots_per_frame);
% 注意：当前版本不再声明会发送 SSB/PDCCH，因为真正发射波形不是标准的，会导致帧设计和波形不一致。
% 因此将每个下行时隙的信道列表简化为 {'PDSCH','DMRS'}，上行时隙为 {'PUSCH','DMRS'}，灵活时隙为两者都有。
for k = 1:slots_per_frame
    if cell_para{1, n_cell}.nr.slot_link_config(k) == 1
        cell_para{1, n_cell}.nr.slot_channel_config{k} = {'PDSCH','DMRS'};
    elseif cell_para{1, n_cell}.nr.slot_link_config(k) == -1
        cell_para{1, n_cell}.nr.slot_channel_config{k} = {'PUSCH','DMRS'};
    else
        cell_para{1, n_cell}.nr.slot_channel_config{k} = {'PDSCH','PUSCH','DMRS'};
    end
end
% 强制将第一个时隙的信道配置设为 PDSCH+DMRS（当前版本波形只映射 PDSCH/DMRS）
cell_para{1, n_cell}.nr.slot_channel_config{1} = {'PDSCH','DMRS'};

% ---------------- PTRS / CSI-RS 配置 ----------------
cell_para{1, n_cell}.nr.ptrs.enable = 'YES';              % 使能相位跟踪参考信号
cell_para{1, n_cell}.nr.ptrs.time_density = 2;            % 时域密度（每几个符号一个 PTRS）
cell_para{1, n_cell}.nr.ptrs.freq_density = 2;            % 频域密度（每几个 RB 一个 PTRS）
cell_para{1, n_cell}.nr.ptrs.RE_offset = '00';            % 资源粒子偏移

cell_para{1, n_cell}.nr.csirs.enable = 'NO';              % 不使能 CSI-RS（本仿真未用）

% ---------------- NR 信道模型配置 ----------------
ue_speed_kmh = 3;                                        % 用户移动速度 (km/h)
lambda = 3e8 / cell_para{1, n_cell}.nr.carrier.fc;        % 载波波长 (m)
fd_ue = (ue_speed_kmh/3.6) / lambda;                     % 最大多普勒频移 (Hz)

cell_para{1, n_cell}.nr.channel.enable = 'YES';           % 使能信道模型
cell_para{1, n_cell}.nr.channel.model = 'TDL-C';          % 抽头延迟线模型类型 (TDL-A/B/C/D)
cell_para{1, n_cell}.nr.channel.delay_spread = 300e-9;    % 时延扩展 (s)
cell_para{1, n_cell}.nr.channel.fc = cell_para{1, n_cell}.nr.carrier.fc; % 载波频率 (Hz)
cell_para{1, n_cell}.nr.channel.ue_speed_kmh = ue_speed_kmh; % 用户速度 (km/h)
cell_para{1, n_cell}.nr.channel.ue_doppler_hz = fd_ue;    % 多普勒频移 (Hz)
cell_para{1, n_cell}.nr.channel.seed = 73;                % 随机种子，保证信道可复现

%% =======================================================================
% 6. user_para（用户参数，纯 NR 配置）
% =======================================================================
user_para{1, n_user}.cellID = cellID;                     % 用户所属小区 ID
user_para{1, n_user}.userID = userID;                     % 用户 ID
user_para{1, n_user}.UeAntennaNum = 2;                    % 用户天线数
user_para{1, n_user}.UE_antenna_spacing = 0.5;            % 用户天线间距（波长单位）
user_para{1, n_user}.UE_antenna_type = 'ULA';             % 用户天线类型
user_para{1, n_user}.mobile_speed = ue_speed_kmh;         % 移动速度
user_para{1, n_user}.enable_DL_channel = {'SSB','PDCCH','PDSCH'}; % 用户接收的下行信道列表
user_para{1, n_user}.enable_UL_channel = {'PUSCH','PUCCH'};       % 用户发送的上行信道列表

user_para{1, n_user}.nr.enable = 'YES';                   % 使能 NR 用户配置
user_para{1, n_user}.nr.RNTI = 1;                         % 无线网络临时标识 (C-RNTI)
user_para{1, n_user}.nr.NID = cellID;                     % 扰码 ID（通常等于小区 ID）
user_para{1, n_user}.nr.active_bwp_id = 1;                % 激活的 BWP ID
user_para{1, n_user}.nr.BWPStart = 0;                     % BWP 起始 RB
user_para{1, n_user}.nr.BWPSize = N_RB;                   % BWP RB 数

% ---------------- PDSCH 配置 ----------------
user_para{1, n_user}.nr.pdsch.enable = 'YES';             % 使能 PDSCH 处理
user_para{1, n_user}.nr.pdsch.RNTI = 1;                   % 用于 PDSCH 加扰的 RNTI
user_para{1, n_user}.nr.pdsch.NID = cellID;               % PDSCH 加扰 ID
user_para{1, n_user}.nr.pdsch.BWPStart = 0;               % PDSCH 所在 BWP 起始 RB
user_para{1, n_user}.nr.pdsch.BWPSize = N_RB;             % BWP 大小
user_para{1, n_user}.nr.pdsch.PRBSet = 0:(N_RB-1);        % 分配给 PDSCH 的 PRB 集合
user_para{1, n_user}.nr.pdsch.SymbolAllocation = [2 10];  % [起始符号, 持续符号数] 时隙内符号分配
user_para{1, n_user}.nr.pdsch.MappingType = 'A';          % PDSCH 映射类型：A (slot-based) 或 B (non-slot-based)
user_para{1, n_user}.nr.pdsch.Modulation = 'QPSK';        % 调制方式：'QPSK','16QAM','64QAM','256QAM'
user_para{1, n_user}.nr.pdsch.NumLayers = 2;              % 传输层数 (MIMO 层)
user_para{1, n_user}.nr.pdsch.NumCodewords = 1;           % 码字数（1 或 2）
user_para{1, n_user}.nr.pdsch.TargetCodeRate = 490/1024;  % 目标码率 (MCS 表对应)
user_para{1, n_user}.nr.pdsch.RVSequence = [0 2 3 1];     % 冗余版本序列 (HARQ)
user_para{1, n_user}.nr.pdsch.HARQEnable = 'YES';         % 是否使能 HARQ
user_para{1, n_user}.nr.pdsch.data_power_db = 0;          % PDSCH 数据功率偏移 (dB)

% PDSCH DMRS 配置
user_para{1, n_user}.nr.pdsch.dmrs.enable = 'YES';        % 使能 DMRS
user_para{1, n_user}.nr.pdsch.dmrs.DMRSConfigurationType = 1; % DMRS 配置类型 (1 或 2)
user_para{1, n_user}.nr.pdsch.dmrs.DMRSLength = 1;        % 单符号或双符号 DMRS
user_para{1, n_user}.nr.pdsch.dmrs.DMRSAdditionalPosition = 1; % 额外 DMRS 位置个数
user_para{1, n_user}.nr.pdsch.dmrs.DMRSTypeAPosition = 2; % PDSCH 映射类型 A 的 DMRS 起始符号位置
user_para{1, n_user}.nr.pdsch.dmrs.NumCDMGroupsWithoutData = 2; % 无数据的 CDM 组数（影响 DMRS 功率提升）
user_para{1, n_user}.nr.pdsch.dmrs.DMRSPortSet = [0 1];   % DMRS 端口集合
user_para{1, n_user}.nr.pdsch.dmrs.NIDNSCID = cellID;     % DMRS 序列生成的加扰 ID
user_para{1, n_user}.nr.pdsch.dmrs.NSCID = 0;             % DMRS 序列初始化时的 n_SCID

% PDSCH PTRS 配置
user_para{1, n_user}.nr.pdsch.ptrs.enable = 'YES';        % 使能 PTRS
user_para{1, n_user}.nr.pdsch.ptrs.TimeDensity = 2;       % 时域密度
user_para{1, n_user}.nr.pdsch.ptrs.FrequencyDensity = 2;  % 频域密度
user_para{1, n_user}.nr.pdsch.ptrs.REOffset = '00';       % RE 偏移

% ---------------- PUSCH 配置 ----------------
user_para{1, n_user}.nr.pusch.enable = 'YES';             % 使能 PUSCH
user_para{1, n_user}.nr.pusch.RNTI = 1;                   % RNTI
user_para{1, n_user}.nr.pusch.NID = cellID;               % 加扰 ID
user_para{1, n_user}.nr.pusch.BWPStart = 0;               % BWP 起始
user_para{1, n_user}.nr.pusch.BWPSize = N_RB;             % BWP 大小
user_para{1, n_user}.nr.pusch.PRBSet = 0:(N_RB-1);        % 分配的 PRB
user_para{1, n_user}.nr.pusch.SymbolAllocation = [0 14];  % 占满整个时隙的符号
user_para{1, n_user}.nr.pusch.MappingType = 'A';          % 映射类型 A
user_para{1, n_user}.nr.pusch.Modulation = 'QPSK';        % 调制方式
user_para{1, n_user}.nr.pusch.NumLayers = 1;              % 层数
user_para{1, n_user}.nr.pusch.TransformPrecoding = 'DISABLED'; % 是否使能 DFT-s-OFDM（变换预编码）
user_para{1, n_user}.nr.pusch.TargetCodeRate = 438/1024;  % 目标码率
user_para{1, n_user}.nr.pusch.RVSequence = [0 2 3 1];     % RV 序列
user_para{1, n_user}.nr.pusch.HARQEnable = 'YES';         % HARQ 使能
user_para{1, n_user}.nr.pusch.data_power_db = 0;          % 数据功率偏移

% PUSCH DMRS 配置
user_para{1, n_user}.nr.pusch.dmrs.enable = 'YES';
user_para{1, n_user}.nr.pusch.dmrs.DMRSConfigurationType = 1;
user_para{1, n_user}.nr.pusch.dmrs.DMRSLength = 1;
user_para{1, n_user}.nr.pusch.dmrs.DMRSAdditionalPosition = 1;
user_para{1, n_user}.nr.pusch.dmrs.DMRSTypeAPosition = 2;
user_para{1, n_user}.nr.pusch.dmrs.NumCDMGroupsWithoutData = 1; % PUSCH 通常为 1 或 2
user_para{1, n_user}.nr.pusch.dmrs.DMRSPortSet = 0;       % 端口 0
user_para{1, n_user}.nr.pusch.dmrs.NIDNSCID = cellID;
user_para{1, n_user}.nr.pusch.dmrs.NSCID = 0;

% ---------------- PUCCH 配置 ----------------
user_para{1, n_user}.nr.pucch.enable = 'YES';             % 使能 PUCCH
user_para{1, n_user}.nr.pucch.format = 1;                 % PUCCH 格式 (0~4)
user_para{1, n_user}.nr.pucch.resourceIndex = 0;          % PUCCH 资源索引
user_para{1, n_user}.nr.pucch.initialCyclicShift = 0;     % 初始循环移位
user_para{1, n_user}.nr.pucch.SR_enable = 'NO';           % 调度请求使能
user_para{1, n_user}.nr.pucch.CSI_enable = 'NO';          % CSI 上报使能
user_para{1, n_user}.nr.pucch.ACK_enable = 'NO';          % HARQ-ACK 使能

% 为 NR 模式创建 legacy LTE CM 兼容容器（部分后续处理可能依赖这些字段）
if ~isfield(user_para{1, n_user}, 'pdsch') || isempty(user_para{1, n_user}.pdsch)
    user_para{1, n_user}.pdsch = struct;
end
if ~isfield(user_para{1, n_user}.pdsch, 'CM') || isempty(user_para{1, n_user}.pdsch.CM)
    user_para{1, n_user}.pdsch.CM = struct;
end

if ~isfield(user_para{1, n_user}, 'pusch') || isempty(user_para{1, n_user}.pusch)
    user_para{1, n_user}.pusch = struct;
end
if ~isfield(user_para{1, n_user}.pusch, 'CM') || isempty(user_para{1, n_user}.pusch.CM)
    user_para{1, n_user}.pusch.CM = struct;
end

%% =======================================================================
% 7. frame_cfg (帧结构配置)
% =======================================================================
frame_cfg.unit_name = 'SLOT';                % 基本调度单元名称
frame_cfg.mu = mu;                           % 参数集索引 μ
frame_cfg.scs = scs;                         % 子载波间隔 (Hz)
frame_cfg.unit_per_subframe = slots_per_subframe; % 每子帧的基本单元数
frame_cfg.unit_per_frame = slots_per_frame;       % 每帧的基本单元数
frame_cfg.symbols_per_unit = symbols_per_slot;    % 每单元符号数
frame_cfg.sample_rate = Fs;                       % 基带采样率
frame_cfg.samples_per_unit = samples_per_slot;    % 每单元采样点数
frame_cfg.current = [];                           % 当前帧状态（运行时更新）

%% =======================================================================
% 8. 用户数据缓存
% =======================================================================
% 三维 cell：小区 × 用户 × 方向（1:DL, 2:UL），存储各用户收发数据
user_data = cell(n_cell, n_user, 2);

% 为 NR 模式初始化 legacy LTE CM 状态（复用部分定时/频偏控制）
sim_config_CM_init;

%% 运行提示
disp('==============================================================');
disp('Pure NR configuration loaded.');
fprintf('BW = %.1f MHz, SCS = %.1f kHz, mu = %d\n', bandwidth_mhz, scs/1e3, mu);
fprintf('N_RB = %d, N_FFT = %d, Fs = %.2f MHz\n', N_RB, N_FFT, Fs/1e6);
fprintf('Slots/frame = %d, Samples/slot = %d\n', slots_per_frame, samples_per_slot);
disp('==============================================================');
end