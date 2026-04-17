%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 文件名: DL_slot_process_nr.m
% 主要功能:
%   NR 下行时隙处理的主入口函数（非 5G 工具箱路径）。
%   本函数在时隙级进行整体编排，包括：
%     1. 检查当前时隙是否为下行时隙，若不是则返回零信号；
%     2. 生成时隙格式 pattern 和参考信号 pattern 并缓存；
%     3. 构建载波参数和空资源网格；
%     4. 遍历小区内的所有 UE，调用 pdsch_process_nr 处理每个 UE 的 PDSCH；
%     5. 对填充后的资源网格进行 OFDM 调制，生成时域发送信号；
%     6. 将运行时信息写回全局变量 cell_para。
%   该函数将每个 UE 的 PDSCH 具体处理委托给 pdsch_process_nr.m，
%   以实现最小侵入性的代码复用。
%
% 输入参数:
%   N_ID_CELL   : 小区物理层 ID（范围 0~1007）
%   n_frame     : 帧号（用于确定时隙在无线帧中的位置）
%   n_slot      : 时隙号（一个帧内的时隙索引，取决于子载波间隔）
%
% 输出参数:
%   transmit_slot_signal : 发送的时域时隙信号，维度 [Nt, K]
%                          Nt 为基站天线数，K 为每个时隙的样本点数
%
% 依赖的全局变量:
%   cell_para   : 小区参数元胞数组，包含 NR 配置、用户列表等
%   user_para   : 用户参数元胞数组，包含每个 UE 的 PDSCH 配置等
%   user_data   : （可选）用户数据调试缓存
%
% 调用的子函数:
%   getCellIndexfromID, getUserIndexfromID, DL_slot_pattern_nr,
%   DL_RS_pattern_nr, pdsch_process_nr, NR_ofdm_modulation
%
% 注意事项:
%   1. 调用本函数前必须先调用 sim_config_compute_nr(n_frame, n_slot) 
%      以初始化 nr.runtime 中的 current_slot 和 current_frame。
%   2. 本函数假设小区内所有 UE 的 PDSCH 配置已在 user_para 中正确设置。
%   3. 非下行时隙直接返回零信号，不做任何处理。
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function transmit_slot_signal = DL_slot_process_nr(N_ID_CELL, n_frame, n_slot)
% 函数开始：输入小区 ID、帧号、时隙号，输出时域时隙信号

% 声明全局变量（通常包含 cell_para, user_para, user_data 等）
globals_declare;

% -------------------- 0) 基本检查 --------------------
% 根据小区物理 ID 获取小区在 cell_para 中的索引（第一维为小区，第二维通常为 1）
n_cell = getCellIndexfromID(N_ID_CELL);
% 若未找到对应小区，报错退出
if isempty(n_cell)
    error('DL_slot_process_nr: invalid N_ID_CELL.');
end
% 检查小区参数中是否配置了 nr 结构体，且非空
if ~isfield(cell_para{1, n_cell}, 'nr') || isempty(cell_para{1, n_cell}.nr)
    error('DL_slot_process_nr: cell_para{1,%d}.nr not configured.', n_cell);
end

% 获取当前小区的完整配置（方便后续使用）
cellCfg = cell_para{1, n_cell};
% 提取 NR 相关配置
nrCfg = cellCfg.nr;
% 基站物理天线数（用于确定发送信号的维度）
Nt = cellCfg.BS_phy_antenna_num;

% 检查运行时状态：必须已通过 sim_config_compute_nr 正确初始化当前时隙/帧
% 要求 nrCfg.runtime 中存在 current_slot 和 current_frame，且与输入参数一致
if ~isfield(nrCfg, 'runtime') || isempty(nrCfg.runtime) || ...
   ~isfield(nrCfg.runtime, 'current_slot') || isempty(nrCfg.runtime.current_slot) || ...
   ~isfield(nrCfg.runtime, 'current_frame') || isempty(nrCfg.runtime.current_frame) || ...
   nrCfg.runtime.current_slot ~= n_slot || ...
   nrCfg.runtime.current_frame ~= n_frame
    error('DL_slot_process_nr: please call sim_config_compute_nr(n_frame,n_slot) first.');
end

% -------------------- 1) 下行时隙防护（若非下行则直接返回零信号）--------------------
% 初始化标志为 false
isDL = false;
% 优先使用 effective_link_type（可能由更高层动态决定）
if isfield(cellCfg.nr.runtime, 'current_effective_link_type') && ...
        ~isempty(cellCfg.nr.runtime.current_effective_link_type)
    % 不区分大小写比较字符串是否为 'DOWNLINK'
    isDL = strcmpi(cellCfg.nr.runtime.current_effective_link_type, 'DOWNLINK');
% 否则使用 current_link_type（静态配置）
elseif isfield(cellCfg.nr.runtime, 'current_link_type') && ...
        ~isempty(cellCfg.nr.runtime.current_link_type)
    isDL = strcmpi(cellCfg.nr.runtime.current_link_type, 'DOWNLINK');
end

% 如果不是下行时隙，直接返回全零的时隙信号（长度为 samples_per_slot）
if ~isDL
    % 每个时隙的样本点数（由子载波间隔和 OFDM 符号长度决定）
    K = cellCfg.nr.samples_per_slot;
    % 生成零信号，维度为 [天线数, 样本点数]
    transmit_slot_signal = complex(zeros(Nt, K));
    return;  % 提前退出，不进行后续处理
end

% -------------------- 2) 时隙 pattern 和参考信号 pattern 缓存 --------------------
% 获取当前时隙的符号级 pattern（每个符号是上行、下行还是灵活）
slot_pattern = DL_slot_pattern_nr(N_ID_CELL, n_slot);
% 获取各类参考信号的 PRB 级 pattern（PDSCH DMRS, PDSCH PTRS, PUSCH DMRS, CSI-RS）
[PDSCH_PRB_DMRS_pattern, PDSCH_PRB_PTRS_pattern, ...
 PUSCH_PRB_DMRS_pattern, CSI_RS_PRB_pattern] = DL_RS_pattern_nr(N_ID_CELL);

% 将上述 pattern 存储到小区运行时缓存中，供其他模块（如链路自适应）使用
cell_para{1, n_cell}.nr.runtime.current_slot_pattern = slot_pattern;
cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern = PDSCH_PRB_DMRS_pattern;
cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern = PDSCH_PRB_PTRS_pattern;
cell_para{1, n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = PUSCH_PRB_DMRS_pattern;
cell_para{1, n_cell}.nr.runtime.CSI_RS_PRB_pattern = CSI_RS_PRB_pattern;

% -------------------- 3) 构建载波结构体和空资源网格 --------------------
% 创建 carrier 结构体，用于传递给下层处理函数（如 pdsch_process_nr）
carrier = struct;
carrier.NCellID = nrCfg.NCellID;                 % 小区 ID
carrier.SubcarrierSpacing = nrCfg.scs / 1e3;    % 子载波间隔，单位 kHz（例如 30 -> 30kHz）
carrier.CyclicPrefix = 'normal';                % 循环前缀类型，目前仅支持 normal
carrier.NSizeGrid = nrCfg.carrier.NSizeGrid;    % 载波的 PRB 数量（带宽）
carrier.NStartGrid = nrCfg.carrier.NStartGrid;  % 载波起始 PRB 索引（通常为 0）
carrier.NSlot = n_slot;                         % 当前时隙号
carrier.NFrame = n_frame;                       % 当前帧号
carrier.SymbolsPerSlot = nrCfg.symbols_per_slot;% 每个时隙的 OFDM 符号数（通常为 14）
carrier.NTxAnts = Nt;                           % 发送天线数

% 创建空的时频资源网格
% 维度：[子载波数（12*PRB数）, 符号数, 天线端口数]
% 初始化为全零复数
txGrid = complex(zeros(12 * carrier.NSizeGrid, carrier.SymbolsPerSlot, Nt));

% -------------------- 4) 逐 UE 处理 PDSCH --------------------
% 获取当前小区下的所有用户 ID 列表
userID_list = cellCfg.userID_list;
% 遍历每个用户
for iu = 1:length(userID_list)
    userID = userID_list(iu);   % 当前用户的全局 ID
    % 根据用户 ID 获取该用户在 user_para 中的索引（小区索引和用户索引）
    [u_cell, u_user] = getUserIndexfromID(userID);
    % 若索引无效或该用户配置为空，则跳过
    if isempty(u_cell) || isempty(u_user) || isempty(user_para{u_cell, u_user})
        continue;
    end
    % 确保该用户属于当前处理的小区（理论上 userID 已保证，但双重检查）
    if u_cell ~= n_cell
        continue;
    end

    % 调用 pdsch_process_nr 处理该用户的 PDSCH：
    % 输入：小区索引、用户索引、帧号、时隙号、载波结构体、当前网格
    % 输出：更新后的网格、UE 处理信息结构体
    [txGrid, ueInfo] = pdsch_process_nr(u_cell, u_user, n_frame, n_slot, carrier, txGrid);
    % 将本次处理的信息存入用户运行时，便于调试或后续 HARQ
    user_para{u_cell, u_user}.nr.pdsch.runtime.lastProcessInfo = ueInfo;
    % 同时保存该用户的发送网格快照（可选）
    user_para{u_cell, u_user}.nr.runtime.txGrid = txGrid;
end

% -------------------- 5) OFDM 调制：从频域网格生成时域信号 --------------------
% 调用 NR OFDM 调制函数，将多天线资源网格转换为时域基带信号
transmit_slot_signal = NR_ofdm_modulation(txGrid, N_ID_CELL, n_frame, n_slot);

% -------------------- 6) 写回运行时信息到 cell_para --------------------
% 记录当前处理的帧号和时隙号（冗余记录，与输入一致）
cell_para{1, n_cell}.nr.runtime.current_frame = n_frame;
cell_para{1, n_cell}.nr.runtime.current_slot = n_slot;
% 保存时隙 pattern 和最终的发送网格、波形
cell_para{1, n_cell}.nr.runtime.current_slot_pattern = slot_pattern;
cell_para{1, n_cell}.nr.runtime.txGrid = txGrid;
cell_para{1, n_cell}.nr.runtime.txWaveform = transmit_slot_signal;

% 确保 ofdmInfo 字段存在（用于存储 OFDM 调制的相关信息，如采样率、FFT 大小等）
% 若不存在则初始化为空数组
if ~isfield(cell_para{1, n_cell}.nr.runtime, 'ofdmInfo')
    cell_para{1, n_cell}.nr.runtime.ofdmInfo = [];
end

% 函数结束，返回时域信号
end