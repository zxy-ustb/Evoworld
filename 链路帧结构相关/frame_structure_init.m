%根据系统的工作模式（LTE 或 NR），初始化帧结构相关的全局配置参数，为后续的物理层信号生成与接收提供时间网格基础。

function frame_structure_init
% frame_structure_init - 初始化帧结构全局参数
%
% 功能描述：
%   根据当前仿真模式（LTE 或 NR），设置 frame_cfg 结构体中的帧结构相关参数，
%   包括基本调度单元名称、参数集索引 μ、每子帧单元数、每帧单元数、每单元符号数、
%   每单元采样点数等。这些参数为后续的物理层信号生成、资源映射和定时同步提供基础。
%
% 输入参数：无（依赖全局变量 cell_para 和 frame_cfg.rat_mode）
% 输出参数：无（修改全局结构体 frame_cfg）

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量：cell_para, frame_cfg 等

% ========================== 1. 获取小区索引和基本采样参数 ==========================
n_cell = 1;   % 当前使用第一个小区（单小区仿真）
% 子载波间隔（Hz），从小区参数中读取
frame_cfg.scs = cell_para{1, n_cell}.sc_spacing;
% 基带采样率 = 子载波间隔 × FFT 点数（Hz）
frame_cfg.sample_rate = cell_para{1, n_cell}.sc_spacing * cell_para{1, n_cell}.N_FFT;

% ========================== 2. 根据 RAT 模式设置帧结构参数 ==========================
if strcmpi(frame_cfg.rat_mode, 'LTE')
    % ------------------- LTE 模式 -------------------
    frame_cfg.unit_name = 'SUBFRAME';          % 基本调度单元为子帧
    frame_cfg.mu = 0;                          % LTE 固定使用 μ=0（15 kHz 子载波间隔）
    frame_cfg.unit_per_subframe = 1;           % 每子帧包含 1 个单元（即 1 个子帧）
    frame_cfg.unit_per_frame = 10;             % 每帧（10ms）包含 10 个子帧
    if strcmpi(cell_para{1, n_cell}.cp_type, 'NORMAL')
        frame_cfg.symbols_per_unit = 14;       % 常规 CP：每子帧 14 个 OFDM 符号
    else
        frame_cfg.symbols_per_unit = 12;       % 扩展 CP：每子帧 12 个 OFDM 符号
    end
    % 每子帧采样点数 = 采样率 × 1ms（子帧时长）
    frame_cfg.samples_per_unit = round(frame_cfg.sample_rate * 1e-3);

elseif strcmpi(frame_cfg.rat_mode, 'NR')
    % ------------------- NR 模式 -------------------
    % 计算参数集索引 μ = log2(SCS / 15kHz)，其中 SCS 为子载波间隔
    mu = round(log2(cell_para{1, n_cell}.sc_spacing / 15e3));
    frame_cfg.mu = mu;                         % 参数集索引
    frame_cfg.unit_name = 'SLOT';              % 基本调度单元为时隙
    % 每子帧（1ms）包含的时隙数 = 2^μ
    frame_cfg.unit_per_subframe = 2^mu;
    % 每帧（10ms）包含的时隙数 = 10 × 每子帧时隙数
    frame_cfg.unit_per_frame = 10 * frame_cfg.unit_per_subframe;
    frame_cfg.symbols_per_unit = 14;           % NR 常规 CP 下每时隙固定 14 个 OFDM 符号
    % 每时隙采样点数 = 采样率 × 时隙时长
    % 时隙时长 = 1ms / 每子帧时隙数 = 1e-3 / unit_per_subframe
    frame_cfg.samples_per_unit = round(frame_cfg.sample_rate * (1e-3 / frame_cfg.unit_per_subframe));

else
    error('Unknown frame_cfg.rat_mode.');      % 未知的 RAT 模式，报错
end

end   % 函数结束