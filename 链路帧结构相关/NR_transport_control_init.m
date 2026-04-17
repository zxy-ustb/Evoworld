function NR_transport_control_init(target_ID)
% NR_transport_control_init - 初始化NR传输控制容器及HARQ记账簿
%
% 功能描述：
%   本函数用于NR系统仿真开始时，为每个用户创建并重置传输控制相关的数据结构，
%   包括统计计数器、HARQ进程状态、软缓存等。它不生成实际的传输块，也不执行
%   HARQ处理，仅建立后续链路处理函数（如DL_slot_process_nr、UL_slot_process_nr）
%   所需使用的容器和初始状态。
%
%   主要初始化三个层次的结构：
%     1) transport_control（根容器）：记录链路方向、各处理阶段的归属（由哪个函数负责）、
%        累计统计量（总块数、错误块数、总比特数、错误比特数、吞吐量等）。上行链路
%        还会额外包含CQI/ACK/RI错误计数。
%     2) 信道专用控制容器（pdsch.transport_control 或 pusch.transport_control）：
%        记录码字数、最大HARQ进程数、容量提示、最近传输信息以及按码字的统计计数器。
%     3) HARQ状态容器（harq）：记录HARQ进程总数、冗余版本序列、每个进程的详细状态
%        （激活标志、当前RV索引、当前RV值、是否新传、传输次数、ACK状态、TB大小、
%        所属帧/时隙、软缓存占位），以及软缓存池。
%
% 输入参数：
%   target_ID : 下行链路时为目标用户ID；上行链路时为目标小区ID。
%
% 输出参数：
%   无（直接修改全局变量 user_para{n_cell,n_user}.nr 中的相关字段）
%
% 调用示例：
%   NR_transport_control_init(targetUserID);   % 下行链路调用
%   NR_transport_control_init(targetCellID);   % 上行链路调用
%
% 设计说明：
%   NR传输控制在LTE基础上拆分为多个函数：
%     参数源          -> sim_config_change_nr
%     静态推导        -> sim_config_init_nr
%     每时隙运行时    -> sim_config_compute_nr
%     TB/RV/HARQ执行 -> DL_slot_process_nr / UL_slot_process_nr
%   本函数只负责创建容器和重置统计，不重新生成参数。

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量（sim_para, frame_cfg, cell_para, user_para等）
global sim_para frame_cfg cell_para user_para;  % 显式声明，确保可见性

% ========================== 1. 全局模式检查 ==========================
% 确保当前仿真模式为NR
if ~isfield(frame_cfg, 'rat_mode') || ~strcmpi(frame_cfg.rat_mode, 'NR')
    error('NR_transport_control_init: frame_cfg.rat_mode must be NR.');
end

% 确保仿真链路类型已设置（由上层循环中的 sim_para.sim_link_type 指定）
if isempty(sim_para) || ~isfield(sim_para, 'sim_link_type') || isempty(sim_para.sim_link_type)
    error('NR_transport_control_init: sim_para.sim_link_type is missing.');
end

% ========================== 2. 根据链路类型获取小区索引 ==========================
if strcmpi(sim_para.sim_link_type, 'DOWNLINK')
    % 下行：target_ID 为用户ID，通过用户ID获取其所在的小区索引（忽略用户索引）
    [n_cell, ~] = getUserIndexfromID(target_ID);
elseif strcmpi(sim_para.sim_link_type, 'UPLINK')
    % 上行：target_ID 为小区ID，通过小区ID获取小区索引
    n_cell = getCellIndexfromID(target_ID);
else
    error('NR_transport_control_init: unsupported sim_link_type %s.', sim_para.sim_link_type);
end

if isempty(n_cell)
    error('NR_transport_control_init: failed to resolve target_ID %d.', target_ID);
end

% ========================== 3. 获取该小区下的所有用户ID列表 ==========================
cell_userID_list = cell_para{1, n_cell}.userID_list;  % 从小区参数中读取用户ID列表
cell_user_num = length(cell_userID_list);             % 小区内的用户总数

% ========================== 4. 遍历该小区的所有用户进行初始化 ==========================
for n_user = 1:cell_user_num
    % 跳过未配置或没有NR字段的用户
    if isempty(user_para{n_cell, n_user}) || ~isfield(user_para{n_cell, n_user}, 'nr')
        continue;
    end

    % 初始化传输控制根容器（存储链路方向、阶段归属、统计计数器等）
    local_init_transport_root(n_cell, n_user);
    % 初始化HARQ状态容器（进程数、RV序列、每个进程的状态、软缓存等）
    local_init_nr_harq_state(n_cell, n_user);

    % 根据链路类型初始化PDSCH或PUSCH的专用传输控制容器
    if strcmpi(sim_para.sim_link_type, 'DOWNLINK')
        local_init_pdsch_control(n_cell, n_user);
    else
        local_init_pusch_control(n_cell, n_user);
    end
end
end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function local_init_transport_root(n_cell, n_user)
% 局部函数：初始化用户NR传输控制根容器（transport_control）
% 输入：小区索引、用户索引
% 输出：修改 user_para{n_cell,n_user}.nr.transport_control
global sim_para frame_cfg cell_para user_para;

ue = user_para{n_cell, n_user}.nr;   % 用户NR配置根结构

% 创建根容器结构体
root = struct;
root.userID = user_para{n_cell, n_user}.userID;          % 用户ID
root.cellID = user_para{n_cell, n_user}.cellID;          % 所属小区ID
root.link = upper(sim_para.sim_link_type);               % 链路类型（DOWNLINK/UPLINK）
root.status = 'initialized';                             % 状态：已初始化
root.last_frame = [];                                    % 最后处理的帧号
root.last_slot = [];                                     % 最后处理的时隙号
root.last_tb_size = [];                                  % 最后一次传输块大小
root.last_rv = [];                                       % 最后一次冗余版本
root.last_harq_process = [];                             % 最后一次使用的HARQ进程号

% 阶段归属映射：描述各处理阶段由哪个函数负责（核心目的，用于代码可追溯性）
root.stage_owner.parameter_source = 'sim_config_change_nr';   % 参数源函数
root.stage_owner.static_derived = 'sim_config_init_nr';       % 静态推导函数
root.stage_owner.runtime_compute = 'sim_config_compute_nr';   % 运行时计算函数
if strcmpi(sim_para.sim_link_type, 'DOWNLINK')
    root.stage_owner.tb_rv_harq_execution = 'DL_slot_process_nr'; % 下行TB/RV/HARQ执行函数
else
    root.stage_owner.tb_rv_harq_execution = 'UL_slot_process_nr'; % 上行TB/RV/HARQ执行函数
end

% 统计计数器（累积值，用于最终性能评估）
root.counters.total_blocks_num = 0;        % 总码块数
root.counters.error_blocks_num = 0;        % 错误码块数
root.counters.total_source_bits_num = 0;   % 总源比特数（传输块原始比特）
root.counters.error_source_bits_num = 0;   % 错误源比特数
root.counters.total_raw_bits = 0;          % 总编码后比特数
root.counters.error_raw_bits = 0;          % 错误编码后比特数
root.counters.through_bits = 0;            % 吞吐量比特数（正确接收的源比特）
root.counters.total_VRB_num = 0;           % 总虚拟资源块数（用于平均频谱效率计算）

% 上行链路额外需要统计UCI（上行控制信息）错误
if strcmpi(sim_para.sim_link_type, 'UPLINK')
    root.counters.CQI_err_num = 0;          % CQI错误计数
    root.counters.ACK_err_num = 0;          % ACK/NACK错误计数
    root.counters.RI_err_num = 0;           % RI错误计数
end

% 如果用户NR配置中尚未存在transport_control，则直接赋值；否则合并字段
if ~isfield(ue, 'transport_control') || isempty(ue.transport_control)
    user_para{n_cell, n_user}.nr.transport_control = root;
else
    % 合并：保留旧结构中的其他字段，用新值覆盖同名字段（避免重复初始化时丢失已有数据）
    user_para{n_cell, n_user}.nr.transport_control = local_merge_struct(...
        user_para{n_cell, n_user}.nr.transport_control, root);
end
end

function local_init_pdsch_control(n_cell, n_user)
% 局部函数：初始化PDSCH专用传输控制容器（pdsch.transport_control）
% 输入：小区索引、用户索引
% 输出：修改 user_para{n_cell,n_user}.nr.pdsch.transport_control
global sim_para frame_cfg cell_para user_para;

ue = user_para{n_cell, n_user}.nr;
% 如果用户未使能PDSCH，则直接返回
if ~isfield(ue, 'pdsch') || ~isfield(ue.pdsch, 'enable') || ~strcmpi(ue.pdsch.enable, 'YES')
    return;
end

ctrl = struct;
ctrl.link = 'DOWNLINK';                      % 链路方向
ctrl.channel = 'PDSCH';                      % 信道类型
ctrl.status = 'initialized';                 % 状态
ctrl.codeword_num = local_pdsch_codeword_count(ue);   % 码字数（1或2）
ctrl.max_harq_process = local_nr_harq_process_count(ue); % 最大HARQ进程数
ctrl.capacity_hint_tb_size = local_pdsch_capacity_hint(ue); % 传输块大小提示（用于预分配）
ctrl.parameter_source = 'sim_config_change_nr';     % 参数源
ctrl.static_derived = 'sim_config_init_nr';         % 静态推导
ctrl.runtime_compute = 'sim_config_compute_nr';     % 运行时计算
ctrl.tb_rv_harq_execution = 'DL_slot_process_nr';   % 执行函数

% 最近一次传输信息（用于调试/跟踪）
ctrl.last_frame = [];
ctrl.last_slot = [];
ctrl.last_tb_size = zeros(1, ctrl.codeword_num);    % 每个码字的最后TB大小
ctrl.last_rv = zeros(1, ctrl.codeword_num);         % 每个码字的最后RV
ctrl.last_harq_process = [];                         % 最后HARQ进程

% 统计计数器（按码字维度）
ctrl.total_blocks_num = zeros(1, ctrl.codeword_num);
ctrl.error_blocks_num = zeros(1, ctrl.codeword_num);
ctrl.total_source_bits_num = zeros(1, ctrl.codeword_num);
ctrl.error_source_bits_num = zeros(1, ctrl.codeword_num);
ctrl.total_raw_bits = zeros(1, ctrl.codeword_num);
ctrl.error_raw_bits = zeros(1, ctrl.codeword_num);
ctrl.through_bits = zeros(1, ctrl.codeword_num);
ctrl.total_VRB_num = zeros(1, ctrl.codeword_num);

% 存入用户结构
user_para{n_cell, n_user}.nr.pdsch.transport_control = ctrl;
end

function local_init_pusch_control(n_cell, n_user)
% 局部函数：初始化PUSCH专用传输控制容器（pusch.transport_control）
% 输入：小区索引、用户索引
% 输出：修改 user_para{n_cell,n_user}.nr.pusch.transport_control
global sim_para frame_cfg cell_para user_para;

ue = user_para{n_cell, n_user}.nr;
if ~isfield(ue, 'pusch') || ~isfield(ue.pusch, 'enable') || ~strcmpi(ue.pusch.enable, 'YES')
    return;
end

ctrl = struct;
ctrl.link = 'UPLINK';
ctrl.channel = 'PUSCH';
ctrl.status = 'initialized';
ctrl.codeword_num = 1;                                % 上行通常为单码字
ctrl.max_harq_process = local_nr_harq_process_count(ue);
ctrl.capacity_hint_tb_size = local_pusch_capacity_hint(ue);
ctrl.parameter_source = 'sim_config_change_nr';
ctrl.static_derived = 'sim_config_init_nr';
ctrl.runtime_compute = 'sim_config_compute_nr';
ctrl.tb_rv_harq_execution = 'UL_slot_process_nr';

ctrl.last_frame = [];
ctrl.last_slot = [];
ctrl.last_tb_size = 0;
ctrl.last_rv = 0;
ctrl.last_harq_process = [];

% 统计计数器（上行单码字）
ctrl.total_blocks_num = 0;
ctrl.error_blocks_num = 0;
ctrl.total_source_bits_num = 0;
ctrl.error_source_bits_num = 0;
ctrl.total_raw_bits = 0;
ctrl.error_raw_bits = 0;
ctrl.through_bits = 0;
ctrl.total_VRB_num = 0;
% 上行控制信息错误统计
ctrl.CQI_err_num = 0;
ctrl.ACK_err_num = 0;
ctrl.RI_err_num = 0;

user_para{n_cell, n_user}.nr.pusch.transport_control = ctrl;
end

function local_init_nr_harq_state(n_cell, n_user)
% 局部函数：初始化HARQ状态容器（harq）
% 输入：小区索引、用户索引
% 输出：修改 user_para{n_cell,n_user}.nr.harq
global sim_para frame_cfg cell_para user_para;

ue = user_para{n_cell, n_user}.nr;
num_harq = local_nr_harq_process_count(ue);   % HARQ进程总数

% 确保用户NR配置中存在harq字段
if ~isfield(user_para{n_cell, n_user}.nr, 'harq') || isempty(user_para{n_cell, n_user}.nr.harq)
    user_para{n_cell, n_user}.nr.harq = struct;
end

harq = user_para{n_cell, n_user}.nr.harq;
harq.num_process = num_harq;                  % 进程数

% 设置冗余版本序列（如果未定义则使用默认[0 2 3 1]，符合3GPP规范）
if ~isfield(harq, 'rv_sequence') || isempty(harq.rv_sequence)
    harq.rv_sequence = [0 2 3 1];
end

% 阶段归属（记录各处理阶段的函数名）
harq.stage_owner.parameter_source = 'sim_config_change_nr';
harq.stage_owner.static_derived = 'sim_config_init_nr';
harq.stage_owner.runtime_compute = 'sim_config_compute_nr';
if strcmpi(sim_para.sim_link_type, 'DOWNLINK')
    harq.stage_owner.tb_rv_harq_execution = 'DL_slot_process_nr';
else
    harq.stage_owner.tb_rv_harq_execution = 'UL_slot_process_nr';
end

% 初始化每个HARQ进程的状态
harq.process = cell(1, num_harq);
for ih = 1:num_harq
    proc = struct;
    proc.id = ih - 1;                     % 进程ID（0-based，方便与RV序列索引对应）
    proc.active = 0;                      % 是否激活（0=未使用，1=使用中）
    proc.rv_index = 1;                    % RV序列索引（指向rv_sequence的第几个元素，1-based）
    proc.rv = harq.rv_sequence(1);        % 当前冗余版本（初传为0）
    proc.new_data = 1;                    % 是否为新数据（1=新传，0=重传）
    proc.tx_count = 0;                    % 该进程已传输次数
    proc.ack = [];                        % ACK状态（1=成功，0=失败，[]=尚未收到）
    proc.tb_size = 0;                     % 传输块大小（比特）
    proc.slot = [];                       % 最后一次传输的时隙号
    proc.frame = [];                      % 最后一次传输的帧号
    proc.softbuffer = [];                 % 软比特缓存（用于重传合并，此处仅占位）
    harq.process{ih} = proc;
end

% 软缓存容器（每个HARQ进程一个，用于存储接收软比特，实际数据在解码时填充）
harq.softbuffer = cell(1, num_harq);
for ih = 1:num_harq
    harq.softbuffer{ih} = [];
end

% 写回用户结构
user_para{n_cell, n_user}.nr.harq = harq;
end

function count = local_pdsch_codeword_count(ue)
% 获取PDSCH的码字数
count = 1;   % 默认单码字
if isfield(ue, 'pdsch') && isfield(ue.pdsch, 'NumCodewords') && ~isempty(ue.pdsch.NumCodewords)
    count = ue.pdsch.NumCodewords;
end
end

function num_harq = local_nr_harq_process_count(ue)
% 获取HARQ进程数（NR中通常为16，但也可配置）
num_harq = 16;   % 默认值
if isfield(ue, 'harq') && isfield(ue.harq, 'num_process') && ~isempty(ue.harq.num_process)
    num_harq = ue.harq.num_process;
end
end

function tbs = local_pdsch_capacity_hint(ue)
% 获取PDSCH传输块大小的容量提示（用于预分配，避免动态增长）
tbs = 1;
% 优先使用 derived 中已计算的 TargetTBSize
if isfield(ue, 'pdsch') && isfield(ue.pdsch, 'derived') && isfield(ue.pdsch.derived, 'TargetTBSize') ...
        && ~isempty(ue.pdsch.derived.TargetTBSize)
    tbs = max(1, ceil(double(ue.pdsch.derived.TargetTBSize)));
% 否则粗略估算：每个RB每符号12子载波，每时隙14符号，每个RE 8比特（近似），再乘以RB数
elseif isfield(ue, 'pdsch') && isfield(ue.pdsch, 'BWPSize') && ~isempty(ue.pdsch.BWPSize)
    tbs = max(1, 12 * 14 * double(ue.pdsch.BWPSize) * 8);
end
end

function tbs = local_pusch_capacity_hint(ue)
% 获取PUSCH传输块大小的容量提示
tbs = 1;
if isfield(ue, 'pusch') && isfield(ue.pusch, 'derived') && isfield(ue.pusch.derived, 'TargetTBSize') ...
        && ~isempty(ue.pusch.derived.TargetTBSize)
    tbs = max(1, ceil(double(ue.pusch.derived.TargetTBSize)));
elseif isfield(ue, 'pusch') && isfield(ue.pusch, 'BWPSize') && ~isempty(ue.pusch.BWPSize)
    tbs = max(1, 12 * 14 * double(ue.pusch.BWPSize) * 8);
end
end

function out = local_merge_struct(oldv, newv)
% 局部函数：合并两个结构体，用新值覆盖旧值中同名字段
% 输入：oldv - 原始结构体，newv - 新结构体
% 输出：合并后的结构体
out = oldv;
fields = fieldnames(newv);
for i = 1:length(fields)
    out.(fields{i}) = newv.(fields{i});
end
end