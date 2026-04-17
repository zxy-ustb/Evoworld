%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 文件名: UL_slot_process_nr.m
% 主要功能:
%   NR 上行时隙处理的主入口函数（非 5G 工具箱路径）。
%   本函数在时隙级进行整体编排，包括：
%     1. 检查当前时隙是否为上行时隙，若不是则返回零信号；
%     2. 生成时隙格式 pattern 和上行参考信号 pattern 并缓存；
%     3. 构建载波参数和空资源网格；
%     4. 判断当前 UE 是否有 PUSCH 和/或 PUCCH 激活；
%     5. 若 PUSCH 激活，调用 pusch_process_nr 处理 PUSCH（支持 PRB 冲突解决）；
%     6. 若 PUCCH 激活，调用占位符函数映射 PUCCH 信号（简单 BPSK/QPSK 序列）；
%     7. 对填充后的资源网格进行 OFDM 调制，生成时域发送信号；
%     8. 将运行时信息写回全局变量 user_para 和 cell_para。
%   该函数将每个 UE 的 PUSCH 具体处理委托给 pusch_process_nr.m，
%   将 PUCCH 以简化的占位符方式实现。
%
% 输入参数:
%   userID      : 用户全局 ID（用于在 user_para 中查找 UE）
%   n_frame     : 帧号
%   n_slot      : 时隙号
%
% 输出参数:
%   transmit_slot_signal : 发送的时域时隙信号，维度 [Nt, K]
%                          Nt 为 UE 天线数，K 为每个时隙的样本点数
%
% 依赖的全局变量:
%   cell_para   : 小区参数元胞数组，包含 NR 配置、参考信号 pattern 等
%   user_para   : 用户参数元胞数组，包含 PUSCH/PUCCH 配置等
%
% 调用的子函数:
%   getUserIndexfromID, UL_slot_pattern_nr, UL_RS_pattern_nr,
%   pusch_process_nr, NR_ofdm_modulation, local_map_pucch_placeholder
%
% 注意事项:
%   1. 调用本函数前必须先调用 sim_config_compute_nr(n_frame, n_slot)
%      以初始化 nr.runtime 中的 current_slot 和 current_frame。
%   2. 本函数假设用户参数中已正确设置 PUSCH 和/或 PUCCH 的运行时激活标志。
%   3. PUCCH 目前仅为占位符实现，使用随机的 BPSK/QPSK 序列，未完全遵循 NR 规范。
%   4. 若 PUSCH 和 PUCCH 同时激活，PUSCH 的 PRB 集合会自动排除 PUCCH 占用的 PRB。
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function transmit_slot_signal = UL_slot_process_nr(userID, n_frame, n_slot)
% 函数开始：输入用户 ID、帧号、时隙号，输出时域上行时隙信号

% 声明全局变量（通常包含 cell_para, user_para 等）
globals_declare;

% -------------------- 0) 用户/小区基本检查 --------------------
% 根据用户 ID 获取该用户在 user_para 中的索引（小区索引和用户索引）
[n_cell, n_user] = getUserIndexfromID(userID);
% 若索引无效，报错退出
if isempty(n_cell) || isempty(n_user)
    error('UL_slot_process_nr: invalid userID.');
end
% 检查用户参数中是否配置了 nr 结构体
if ~isfield(user_para{n_cell, n_user}, 'nr') || isempty(user_para{n_cell, n_user}.nr)
    error('UL_slot_process_nr: user_para{%d,%d}.nr not configured.', n_cell, n_user);
end
% 检查对应小区参数中是否配置了 nr 结构体
if ~isfield(cell_para{1, n_cell}, 'nr') || isempty(cell_para{1, n_cell}.nr)
    error('UL_slot_process_nr: cell_para{1,%d}.nr not configured.', n_cell);
end

% 获取小区配置和 NR 配置
cellCfg = cell_para{1, n_cell};
nrCfg = cellCfg.nr;
% 获取用户配置和用户的 NR 配置
ueCfg = user_para{n_cell, n_user};
ueNr = ueCfg.nr;
% 用户天线数（默认 1，若用户配置中有 UeAntennaNum 则使用）
Nt = local_get_field(ueCfg, 'UeAntennaNum', 1);
% 小区物理 ID（优先使用小区配置中的 cellID，否则使用 nrCfg.NCellID）
cellID = local_get_field(cellCfg, 'cellID', nrCfg.NCellID);

% 检查运行时状态：必须已通过 sim_config_compute_nr 正确初始化当前时隙/帧
if ~isfield(nrCfg, 'runtime') || isempty(nrCfg.runtime) || ...
   ~isfield(nrCfg.runtime, 'current_slot') || isempty(nrCfg.runtime.current_slot) || ...
   ~isfield(nrCfg.runtime, 'current_frame') || isempty(nrCfg.runtime.current_frame) || ...
   nrCfg.runtime.current_slot ~= n_slot || ...
   nrCfg.runtime.current_frame ~= n_frame
    error('UL_slot_process_nr: please call sim_config_compute_nr(n_frame,n_slot) first.');
end

% -------------------- 1) 上行时隙防护（若非上行则直接返回零信号）--------------------
linkType = '';  % 存储链路类型（UPLINK 或 DOWNLINK）
% 优先使用 effective_link_type（可能由更高层动态决定）
if isfield(nrCfg.runtime, 'current_effective_link_type') && ~isempty(nrCfg.runtime.current_effective_link_type)
    linkType = nrCfg.runtime.current_effective_link_type;
% 否则使用 current_link_type（静态配置）
elseif isfield(nrCfg.runtime, 'current_link_type') && ~isempty(nrCfg.runtime.current_link_type)
    linkType = nrCfg.runtime.current_link_type;
end
% 如果不是上行时隙，直接返回全零的时隙信号
if ~strcmpi(linkType, 'UPLINK')
    K = nrCfg.samples_per_slot;   % 每个时隙的样本点数
    transmit_slot_signal = complex(zeros(Nt, K));
    return;  % 提前退出
end

% -------------------- 2) 上行时隙 pattern 和参考信号 pattern 缓存 --------------------
% 获取当前时隙的符号级 pattern（每个符号是上行、下行还是灵活）
slot_pattern = UL_slot_pattern_nr(cellID, n_slot);
% 获取上行参考信号的 PRB 级 pattern（PUSCH DMRS, PUCCH DMRS, SRS）
[PUSCH_PRB_DMRS_pattern, PUCCH_PRB_DMRS_pattern, SRS_PRB_pattern] = UL_RS_pattern_nr(cellID);

% 将上述 pattern 存储到小区运行时缓存中，供其他模块使用
cell_para{1, n_cell}.nr.runtime.current_ul_slot_pattern = slot_pattern;
cell_para{1, n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = PUSCH_PRB_DMRS_pattern;
cell_para{1, n_cell}.nr.runtime.PUCCH_PRB_DMRS_pattern = PUCCH_PRB_DMRS_pattern;
cell_para{1, n_cell}.nr.runtime.SRS_PRB_pattern = SRS_PRB_pattern;

% -------------------- 3) 构建载波结构体和空资源网格 --------------------
% 创建 carrier 结构体，用于传递给下层处理函数（如 pusch_process_nr）
carrier = struct;
carrier.NCellID = nrCfg.NCellID;                 % 小区 ID
carrier.SubcarrierSpacing = nrCfg.scs / 1e3;    % 子载波间隔（kHz）
carrier.CyclicPrefix = 'normal';                % 循环前缀类型
carrier.NSizeGrid = nrCfg.carrier.NSizeGrid;    % 载波的 PRB 数量
carrier.NStartGrid = nrCfg.carrier.NStartGrid;  % 载波起始 PRB 索引
carrier.NSlot = n_slot;                         % 当前时隙号
carrier.NFrame = n_frame;                       % 当前帧号
carrier.SymbolsPerSlot = nrCfg.symbols_per_slot;% 每个时隙的 OFDM 符号数
carrier.NTxAnts = Nt;                           % 发送天线数（UE 侧）

% 创建空的时频资源网格（上行：UE 侧发送，维度为 [子载波数, 符号数, UE天线数]）
txGrid = complex(zeros(12 * carrier.NSizeGrid, carrier.SymbolsPerSlot, Nt));

% -------------------- 4) 检查 PUSCH 和 PUCCH 激活标志 --------------------
% 检查 PUSCH 是否激活：需要在 ueNr.pusch.runtime.active 为 true
hasPusch = isfield(ueNr, 'pusch') && isfield(ueNr.pusch, 'runtime') && ...
    isfield(ueNr.pusch.runtime, 'active') && ueNr.pusch.runtime.active;
% 检查 PUCCH 是否激活：需要在 ueNr.pucch.runtime.active 为 true
hasPucch = isfield(ueNr, 'pucch') && isfield(ueNr.pucch, 'runtime') && ...
    isfield(ueNr.pucch.runtime, 'active') && ueNr.pucch.runtime.active;

% 若两者都未激活，则直接返回零信号（但需更新用户运行时信息）
if ~hasPusch && ~hasPucch
    transmit_slot_signal = complex(zeros(Nt, nrCfg.samples_per_slot));
    user_para{n_cell, n_user}.nr.runtime.txGrid = txGrid;
    user_para{n_cell, n_user}.nr.runtime.txWaveform = transmit_slot_signal;
    return;
end

% -------------------- 5) 通过委托函数处理 PUSCH --------------------
if hasPusch
    % 获取 PUSCH 运行时配置的 PRB 集合
    effPrbSet = ueNr.pusch.runtime.PRBSet;
    % 若 PUCCH 也激活，且 PUCCH 配置了 PRBSet，则需要从 PUSCH 的 PRB 集合中排除 PUCCH 占用的 PRB
    % 避免资源冲突
    if hasPucch && isfield(ueNr.pucch.runtime, 'PRBSet') && ~isempty(ueNr.pucch.runtime.PRBSet)
        effPrbSet = setdiff(effPrbSet, ueNr.pucch.runtime.PRBSet);
    end

    % 调用 pusch_process_nr 处理该用户的 PUSCH
    % 输入：小区索引、用户索引、帧号、时隙号、载波结构体、当前网格、有效 PRB 集合
    % 输出：更新后的网格、PUSCH 处理信息结构体
    [txGrid, puschInfo] = pusch_process_nr(n_cell, n_user, n_frame, n_slot, carrier, txGrid, effPrbSet);
    % 将本次处理的信息存入用户运行时
    user_para{n_cell, n_user}.nr.pusch.runtime.lastProcessInfo = puschInfo;
    user_para{n_cell, n_user}.nr.runtime.txGrid = txGrid;
end

% -------------------- 6) PUCCH 占位符处理（简化实现）--------------------
if hasPucch
    % 调用局部函数映射 PUCCH 占位符信号（使用 BPSK/QPSK 随机序列）
    txGrid = local_map_pucch_placeholder(txGrid, ueCfg, Nt);
end

% -------------------- 7) OFDM 调制：从频域网格生成时域信号 --------------------
N_ID_CELL = cellID;   % 使用小区 ID 作为 OFDM 调制的小区标识
transmit_slot_signal = NR_ofdm_modulation(txGrid, N_ID_CELL, n_frame, n_slot);

% -------------------- 8) 写回运行时信息到 user_para 和 cell_para --------------------
% 更新用户运行时信息
user_para{n_cell, n_user}.nr.runtime.current_frame = n_frame;
user_para{n_cell, n_user}.nr.runtime.current_slot = n_slot;
user_para{n_cell, n_user}.nr.runtime.current_link_type = 'UPLINK';
user_para{n_cell, n_user}.nr.runtime.current_effective_link_type = 'UPLINK';
user_para{n_cell, n_user}.nr.runtime.txGrid = txGrid;
user_para{n_cell, n_user}.nr.runtime.txWaveform = transmit_slot_signal;
% 复制小区中的 OFDM 信息（如采样率、FFT 大小等）到用户运行时
user_para{n_cell, n_user}.nr.runtime.ofdmInfo = cell_para{1, n_cell}.nr.runtime.ofdmInfo;
user_para{n_cell, n_user}.nr.runtime.current_ul_slot_pattern = slot_pattern;

% 同时更新小区运行时中的发送网格和波形（用于可能的宏分集或记录）
cell_para{1, n_cell}.nr.runtime.txGrid = txGrid;
cell_para{1, n_cell}.nr.runtime.txWaveform = transmit_slot_signal;
cell_para{1, n_cell}.nr.runtime.last_ul_userID = userID;  % 记录最后处理的上行用户 ID
end

%% ======================= 局部辅助函数 =======================
% 功能：PUCCH 占位符映射（简化实现，非完整 NR 规范）
% 输入：当前资源网格 txGrid，用户配置 ueCfg，天线数 Nt
% 输出：添加了 PUCCH 占位符信号的网格
function txGrid = local_map_pucch_placeholder(txGrid, ueCfg, Nt)
% 获取 PUCCH 运行时配置
rt = ueCfg.nr.pucch.runtime;
% 若未配置 PRB 集合或符号集合，则直接返回
if isempty(rt.PRBSet) || isempty(rt.SymbolSet)
    return;
end

% 获取 PRB 索引集（去重、行向量）
prbSet = unique(rt.PRBSet(:).');
% 获取符号索引集（去重）
symSet = unique(rt.SymbolSet(:).');
% 获取 DMRS 符号集（若有配置）
dmrsSet = [];
if isfield(rt, 'DMRSSymbolSet') && ~isempty(rt.DMRSSymbolSet)
    dmrsSet = unique(rt.DMRSSymbolSet(:).');
end

% 获取 PUCCH 载荷比特数（默认 1 比特）
payloadBits = 1;
if isfield(rt, 'PayloadBits') && ~isempty(rt.PayloadBits) && rt.PayloadBits > 0
    payloadBits = rt.PayloadBits;
end

% 遍历每个 PRB 和每个符号，生成对应的序列并映射
for iPrb = 1:length(prbSet)
    % 该 PRB 对应的子载波起始索引（0-based，MATLAB 索引需 +1）
    scBase = prbSet(iPrb) * 12;
    for iSym = 1:length(symSet)
        sym = symSet(iSym);   % 符号索引（0-based）
        % 子载波索引范围（1-based）
        scIdx = (scBase + 1):(scBase + 12);
        % 判断当前符号是否为 DMRS 符号
        if ismember(sym, dmrsSet)
            % DMRS 符号：生成 QPSK 序列（12 个 RE），种子基于小区 ID、PRB、符号
            seq = local_qpsk_sequence(12, 7000 + ueCfg.userID + 31 * prbSet(iPrb) + sym);
        else
            % 非 DMRS 符号（数据符号）：生成 BPSK 序列，种子加入载荷比特
            seq = local_bpsk_sequence(12, 8000 + ueCfg.userID + payloadBits + 17 * prbSet(iPrb) + sym);
        end
        % 对所有天线端口，将序列叠加到网格对应位置
        for ia = 1:Nt
            txGrid(scIdx, sym + 1, ia) = txGrid(scIdx, sym + 1, ia) + seq;
        end
    end
end
end

% 功能：生成指定长度的 QPSK 调制序列（复数，能量归一化）
% 输入：N 为序列长度（RE 数），seed 为随机种子
% 输出：复数 QPSK 符号列向量，每个符号幅度为 1/sqrt(2)
function seq = local_qpsk_sequence(N, seed)
if N <= 0
    seq = complex(zeros(0, 1));
    return;
end
% 使用梅森旋转算法随机数生成器
s = RandStream('mt19937ar', 'Seed', seed);
% 生成 2N 个随机比特
b = randi(s, [0 1], 2 * N, 1);
% 映射为 QPSK：b0 为偶数位，b1 为奇数位
b0 = 1 - 2 * b(1:2:end);   % 映射 0->1, 1->-1
b1 = 1 - 2 * b(2:2:end);
% 复数符号，除以 sqrt(2) 保持能量归一化
seq = (b0 + 1i * b1) / sqrt(2);
end

% 功能：生成指定长度的 BPSK 调制序列（实数，能量归一化）
% 输入：N 为序列长度（RE 数），seed 为随机种子
% 输出：BPSK 符号列向量（+1/-1）
function seq = local_bpsk_sequence(N, seed)
if N <= 0
    seq = complex(zeros(0, 1));
    return;
end
s = RandStream('mt19937ar', 'Seed', seed);
b = randi(s, [0 1], N, 1);
% 映射：0 -> +1, 1 -> -1
seq = 1 - 2 * b;
end

% 功能：从结构体中安全获取字段值，若不存在或为空则返回默认值
function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end