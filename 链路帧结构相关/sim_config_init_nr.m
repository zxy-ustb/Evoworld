%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 文件名: sim_config_init_nr.m
% 功能描述:
%   纯 NR 初始化函数（不依赖 LTE 遗留配置）。
%   主要作用：
%     1) 根据 sim_config_change_nr 中预设的 NR 配置，生成运行时所需的派生参数；
%     2) 初始化小区和用户级别的运行时结构体（runtime）；
%     3) 为 PDSCH/PUSCH/PUCCH/SSB/PDCCH 等计算派生参数（如 Qm、G、TB 大小等）；
%     4) 建立与 legacy 信道模块的兼容字段（legacy_cm）；
%     5) 同步全局 frame_cfg 结构体。
%
% 调用前提:
%   必须先调用 sim_config_change_nr 完成 cell_para 和 user_para 的基础配置。
%
% 输入:
%   无（直接读取全局变量 cell_para, user_para, sim_para, sys_para）
%
% 输出:
%   无（修改全局变量 cell_para, user_para, frame_cfg, sim_para, sys_para）
%
% 依赖的全局变量:
%   cell_para, user_para, sim_para, sys_para, frame_cfg
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function sim_config_init_nr
% 声明全局变量（通常包含 cell_para, user_para, sim_para, sys_para, frame_cfg）
globals_declare;

% 获取小区和用户的数量（cell_para 第一维为小区，第二维通常为1；user_para 第一维为小区，第二维为用户）
cell_num = size(cell_para, 2);
user_num = size(user_para, 2);

% 若没有任何小区或用户配置，报错退出
if cell_num == 0 || user_num == 0
    error('sim_config_init_nr: user_para/cell_para is empty. Please call sim_config_change_nr first.');
end

% 遍历所有小区
for n_cell = 1:cell_num

    % 如果该小区配置为空，跳过
    if isempty(cell_para{1, n_cell})
        continue;
    end

    % 检查小区是否配置了 nr 结构体
    if ~isfield(cell_para{1, n_cell}, 'nr') || isempty(cell_para{1, n_cell}.nr)
        error('sim_config_init_nr: cell_para{%d}.nr does not exist.', n_cell);
    end

    nr = cell_para{1, n_cell}.nr;

    % ------------------------------------------------------------------
    % 0. 基础字段检查（确保必要的数值字段存在）
    % ------------------------------------------------------------------
    requiredCellFields = {'mu', 'scs', 'sample_rate', 'symbols_per_slot', 'slots_per_subframe', ...
                          'slots_per_frame', 'slot_duration', 'samples_per_slot', 'carrier', 'bwp'};
    for k = 1:length(requiredCellFields)
        if ~isfield(nr, requiredCellFields{k}) || isempty(nr.(requiredCellFields{k}))
            error('sim_config_init_nr: cell_para{%d}.nr.%s is missing.', n_cell, requiredCellFields{k});
        end
    end

    % 提取常用数值到局部变量（便于后续使用）
    mu                 = nr.mu;                    % 子载波间隔配置 μ (0~4)
    scs                = nr.scs;                  % 子载波间隔，单位 Hz（例如 30e3）
    Nfft               = cell_para{1, n_cell}.N_FFT;  % FFT 点数（从小区参数获取）
    Fs                 = nr.sample_rate;          % 采样率（Hz）
    symbols_per_slot   = nr.symbols_per_slot;     % 每个时隙的 OFDM 符号数（通常 14）
    slots_per_subframe = nr.slots_per_subframe;   % 每个子帧的时隙数（取决于 μ）
    slots_per_frame    = nr.slots_per_frame;      % 每个帧的时隙数（10 * slots_per_subframe）
    slot_duration      = nr.slot_duration;        % 每个时隙的时长（秒）
    samples_per_slot   = nr.samples_per_slot;     % 每个时隙的采样点数

    % ------------------------------------------------------------------
    % 1. 通用时域派生量
    % ------------------------------------------------------------------
    % 采样间隔（秒）
    cell_para{1, n_cell}.sampling_interval = 1 / Fs;

    % 有用符号时间（不含 CP）= 1 / 子载波间隔
    cell_para{1, n_cell}.useful_symbol_time = 1 / scs;
    % 遗留信道兼容参数将在下面的 local_init_legacy_channel_compat 中导出

    % 近似 NR 正常 CP 长度（与现有工程的采样体系兼容）
    % 第一个符号的 CP 稍长，其余符号 CP 固定
    cp_first  = round(Nfft * 11 / 128);   % 第一个符号的 CP 长度（采样点数）
    cp_others = round(Nfft * 9 / 128);    % 其余符号的 CP 长度
    cp_lengths = [cp_first, cp_others * ones(1, symbols_per_slot-1)];

    % 计算当前 CP 总长度 + 数据部分总长度
    total_now = sum(cp_lengths) + symbols_per_slot * Nfft;
    % 与预设的 samples_per_slot 之间的差值
    delta = samples_per_slot - total_now;

    % 将残差补偿到第一个符号的 CP 上（而不是最后一个符号）
    cp_lengths(1) = cp_lengths(1) + delta;

    % 每个 OFDM 符号的总长度（数据 + CP）
    symbol_lengths = Nfft + cp_lengths;

    % 计算每个符号在时隙内的起始采样点索引（从 0 开始）
    symbol_start = zeros(1, symbols_per_slot);
    acc = 0;
    for isym = 1:symbols_per_slot
        symbol_start(isym) = acc;
        acc = acc + symbol_lengths(isym);
    end

    % 校验累加和是否等于 samples_per_slot
    if acc ~= samples_per_slot
        error('sim_config_init_nr: symbol sample accounting mismatch.');
    end

    % 将 CP 相关参数存入小区 nr.runtime
    cell_para{1, n_cell}.nr.cp_lengths = cp_lengths;                  % 每个符号的 CP 长度
    cell_para{1, n_cell}.nr.symbol_lengths = symbol_lengths;          % 每个符号的总长度
    cell_para{1, n_cell}.nr.symbol_start = symbol_start;              % 每个符号的起始采样索引
    cell_para{1, n_cell}.nr.samples_per_symbol_no_cp = Nfft;          % 每个符号的数据部分采样点数
    cell_para{1, n_cell}.nr.samples_per_subframe = samples_per_slot * slots_per_subframe;
    cell_para{1, n_cell}.nr.samples_per_frame = samples_per_slot * slots_per_frame;

    % 调用局部函数，初始化与 legacy 信道链兼容的字段
    local_init_legacy_channel_compat(n_cell, Fs, scs, symbols_per_slot, cp_lengths);

    % ------------------------------------------------------------------
    % 2. 资源网格尺寸 / BWP
    % ------------------------------------------------------------------
    % 从载波配置中读取 PRB 总数和起始 PRB 索引
    NSizeGrid = cell_para{1, n_cell}.nr.carrier.NSizeGrid;
    NStartGrid = cell_para{1, n_cell}.nr.carrier.NStartGrid;

    % 将网格信息存入 nr.grid 结构体
    cell_para{1, n_cell}.nr.grid.NSizeGrid = NSizeGrid;               % PRB 总数
    cell_para{1, n_cell}.nr.grid.NStartGrid = NStartGrid;             % 起始 PRB 索引
    cell_para{1, n_cell}.nr.grid.NSubcarriers = 12 * NSizeGrid;       % 总子载波数
    cell_para{1, n_cell}.nr.grid.SymbolsPerSlot = symbols_per_slot;   % 每时隙符号数
    cell_para{1, n_cell}.nr.grid.SlotsPerFrame = slots_per_frame;     % 每帧时隙数
    cell_para{1, n_cell}.nr.grid.SampleRate = Fs;                     % 采样率

    % 检查 active_bwp_id 是否存在
    if ~isfield(cell_para{1, n_cell}.nr, 'active_bwp_id') || isempty(cell_para{1, n_cell}.nr.active_bwp_id)
        error('sim_config_init_nr: cell_para{%d}.nr.active_bwp_id is missing.', n_cell);
    end

    active_bwp_id = cell_para{1, n_cell}.nr.active_bwp_id;            % 当前激活的 BWP ID
    bwp = cell_para{1, n_cell}.nr.bwp{active_bwp_id};                 % 获取对应的 BWP 配置
    cell_para{1, n_cell}.nr.active_bwp = bwp;                         % 存入 active_bwp
    cell_para{1, n_cell}.nr.active_bwp.NSubcarriers = 12 * bwp.NSizeBWP;  % BWP 的子载波数

    % ------------------------------------------------------------------
    % 3. TDD 时隙配置检查
    % ------------------------------------------------------------------
    % slot_indicator: 每个时隙的标识（如 'D', 'U', 'F'）
    if ~isfield(cell_para{1, n_cell}.nr, 'slot_indicator') || length(cell_para{1, n_cell}.nr.slot_indicator) ~= slots_per_frame
        error('sim_config_init_nr: nr.slot_indicator length must equal slots_per_frame.');
    end
    % slot_link_config: 每个时隙的链路类型（'DOWNLINK', 'UPLINK', 'FLEXIBLE'）
    if ~isfield(cell_para{1, n_cell}.nr, 'slot_link_config') || length(cell_para{1, n_cell}.nr.slot_link_config) ~= slots_per_frame
        error('sim_config_init_nr: nr.slot_link_config length must equal slots_per_frame.');
    end
    % slot_channel_config: 每个时隙的信道配置（如 'PDSCH', 'PUSCH', 'SSB' 等）
    if ~isfield(cell_para{1, n_cell}.nr, 'slot_channel_config') || length(cell_para{1, n_cell}.nr.slot_channel_config) ~= slots_per_frame
        error('sim_config_init_nr: nr.slot_channel_config length must equal slots_per_frame.');
    end

    % ------------------------------------------------------------------
    % 4. 小区级运行时容器初始化
    % ------------------------------------------------------------------
    cell_para{1, n_cell}.nr.runtime.current_frame = 0;                % 当前帧号
    cell_para{1, n_cell}.nr.runtime.current_slot = 0;                 % 当前时隙号
    cell_para{1, n_cell}.nr.runtime.current_subframe = 0;             % 当前子帧号
    cell_para{1, n_cell}.nr.runtime.current_link_type = 'DOWNLINK';   % 当前链路类型（静态）
    cell_para{1, n_cell}.nr.current_effective_link_type = 'DOWNLINK'; % 有效链路类型（动态）
    cell_para{1, n_cell}.nr.runtime.current_channels = {};            % 当前时隙激活的信道列表
    cell_para{1, n_cell}.nr.runtime.current_slot_pattern = [];        % 下行时隙 pattern（符号级）
    cell_para{1, n_cell}.nr.runtime.current_ul_slot_pattern = [];     % 上行时隙 pattern
    cell_para{1, n_cell}.nr.runtime.txGrid = [];                      % 发送频域网格
    cell_para{1, n_cell}.nr.runtime.txWaveform = [];                  % 发送时域波形
    cell_para{1, n_cell}.nr.runtime.ofdmInfo = [];                    % OFDM 相关信息（如 FFT 大小等）
    cell_para{1, n_cell}.nr.runtime.slot_symbol_role = {};            % 每个符号的角色（'PDSCH', 'PUSCH', 'SSB' 等）
    cell_para{1, n_cell}.nr.runtime.ssb_active = 0;                   % SSB 是否激活
    cell_para{1, n_cell}.nr.runtime.pdcch_active = 0;                 % PDCCH 是否激活
    cell_para{1, n_cell}.nr.runtime.pdsch_active = 0;                 % PDSCH 是否激活
    cell_para{1, n_cell}.nr.runtime.pusch_active = 0;                 % PUSCH 是否激活
    cell_para{1, n_cell}.nr.runtime.pucch_active = 0;                 % PUCCH 是否激活

    % 保存单 PRB RS 图样缓存（供 DL_RS_pattern_nr / UL_RS_pattern_nr 使用）
    cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern = [];
    cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern = [];
    cell_para{1, n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = [];
    cell_para{1, n_cell}.nr.runtime.PUCCH_PRB_DMRS_pattern = [];
    cell_para{1, n_cell}.nr.runtime.CSI_RS_PRB_pattern = [];
    cell_para{1, n_cell}.nr.runtime.SRS_PRB_pattern = [];

    % ---------- SSB 运行时 ----------
    if ~isfield(cell_para{1, n_cell}.nr, 'ssb') || isempty(cell_para{1, n_cell}.nr.ssb)
        cell_para{1, n_cell}.nr.ssb = struct;
    end
    cell_para{1, n_cell}.nr.ssb.runtime.active = 0;      % SSB 是否激活
    cell_para{1, n_cell}.nr.ssb.runtime.SymbolSet = [];  % SSB 占用的符号集合
    cell_para{1, n_cell}.nr.ssb.runtime.SCSet = [];      % SSB 占用的子载波集合

    % ---------- PDCCH 运行时 ----------
    if ~isfield(cell_para{1, n_cell}.nr, 'pdcch') || isempty(cell_para{1, n_cell}.nr.pdcch)
        cell_para{1, n_cell}.nr.pdcch = struct;
    end
    cell_para{1, n_cell}.nr.pdcch.runtime.active = 0;            % PDCCH 是否激活
    cell_para{1, n_cell}.nr.pdcch.runtime.SymbolSet = [];        % 占用的符号
    cell_para{1, n_cell}.nr.pdcch.runtime.RBSet = [];            % 占用的 RB
    cell_para{1, n_cell}.nr.pdcch.runtime.AggregationLevel = []; % 聚合级别
    cell_para{1, n_cell}.nr.pdcch.runtime.coreset_id = [];       % CORESET ID
    cell_para{1, n_cell}.nr.pdcch.runtime.searchspace_id = [];   % SearchSpace ID

    % ---------- CSI-RS 运行时 ----------
    if ~isfield(cell_para{1, n_cell}.nr, 'csirs') || isempty(cell_para{1, n_cell}.nr.csirs)
        cell_para{1, n_cell}.nr.csirs = struct;
    end
    cell_para{1, n_cell}.nr.csirs.runtime.active = 0;       % CSI-RS 是否激活
    cell_para{1, n_cell}.nr.csirs.runtime.SymbolSet = [];   % 占用的符号
    cell_para{1, n_cell}.nr.csirs.runtime.PRBSet = [];      % 占用的 PRB

    % ------------------------------------------------------------------
    % 5. 用户级初始化
    % ------------------------------------------------------------------
    for n_user = 1:user_num

        % 检查用户配置是否存在
        if n_cell > size(user_para, 1) || n_user > size(user_para, 2) || isempty(user_para{n_cell, n_user})
            continue;
        end

        % 检查用户 nr 结构体是否存在
        if ~isfield(user_para{n_cell, n_user}, 'nr') || isempty(user_para{n_cell, n_user}.nr)
            error('sim_config_init_nr: user_para{%d,%d}.nr does not exist.', n_cell, n_user);
        end

        ue = user_para{n_cell, n_user}.nr;   % 用户 NR 配置

        % ---------------- PDSCH 派生参数 ----------------
        if isfield(ue, 'pdsch') && isfield(ue.pdsch, 'enable') && strcmpi(ue.pdsch.enable, 'YES')

            pdsch = ue.pdsch;

            Qm_pdsch = nr_mod_order(pdsch.Modulation);              % 调制阶数（每符号比特数）
            pdsch_nsym = pdsch.SymbolAllocation(2);                 % PDSCH 占用的符号数
            pdsch_dmrs_symbols = nr_pdsch_dmrs_symbols(pdsch.SymbolAllocation, pdsch.dmrs); % DMRS 符号位置

            % 若配置了 PTRS，计算 PTRS 符号和每 PRB 占用的 RE 数
            if isfield(pdsch, 'ptrs')
                pdsch_ptrs_symbols = nr_ptrs_symbols(pdsch.SymbolAllocation, pdsch_dmrs_symbols, pdsch.ptrs);
                re_per_prb_ptrs = nr_ptrs_re_per_prb(pdsch.ptrs, length(pdsch_ptrs_symbols));
            else
                pdsch_ptrs_symbols = [];
                re_per_prb_ptrs = 0;
            end

            % 计算每 PRB 的总 RE 数、DMRS RE 数、数据 RE 数
            re_per_prb_total = 12 * pdsch_nsym;                     % 每个 PRB 总 RE 数
            re_per_prb_dmrs = nr_dmrs_re_per_prb(pdsch.dmrs);       % 每个 DMRS 符号占用的 RE 数（每 PRB）
            re_per_prb_data = re_per_prb_total - re_per_prb_dmrs * length(pdsch_dmrs_symbols) - re_per_prb_ptrs;
            re_per_prb_data = max(re_per_prb_data, 0);

            % 总编码比特数 G = (#PRB) * (每 PRB 数据 RE 数) * 调制阶数 * 层数
            G_pdsch = length(pdsch.PRBSet) * re_per_prb_data * Qm_pdsch * pdsch.NumLayers;
            % 近似传输块大小（比特）= G * 目标码率
            TB_pdsch = floor(G_pdsch * pdsch.TargetCodeRate);

            % 存储派生参数到 user_para{n_cell,n_user}.nr.pdsch.derived
            user_para{n_cell, n_user}.nr.pdsch.derived.Qm = Qm_pdsch;
            user_para{n_cell, n_user}.nr.pdsch.derived.DMRSSymbolSet = pdsch_dmrs_symbols;
            user_para{n_cell, n_user}.nr.pdsch.derived.PTRSSymbolSet = pdsch_ptrs_symbols;
            user_para{n_cell, n_user}.nr.pdsch.derived.REPerPRB = re_per_prb_data;
            user_para{n_cell, n_user}.nr.pdsch.derived.G = G_pdsch;
            user_para{n_cell, n_user}.nr.pdsch.derived.TargetTBSize = TB_pdsch;

            % 初始化 PDSCH 运行时字段（初始为未激活）
            user_para{n_cell, n_user}.nr.pdsch.runtime.active = 0;
            user_para{n_cell, n_user}.nr.pdsch.runtime.slot = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.PRBSet = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.SymbolSet = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.DMRSSymbolSet = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.PTRSSymbolSet = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.transportBlock = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.transportBlockSize = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.HARQProcessID = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.RedundancyVersion = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.pdschIndicesInfo = [];
        end

        % ---------------- PUSCH 派生参数 ----------------
        if isfield(ue, 'pusch') && isfield(ue.pusch, 'enable') && strcmpi(ue.pusch.enable, 'YES')

            pusch = ue.pusch;

            Qm_pusch = nr_mod_order(pusch.Modulation);              % 调制阶数
            pusch_nsym = pusch.SymbolAllocation(2);                 % PUSCH 占用的符号数
            pusch_dmrs_symbols = nr_pusch_dmrs_symbols(pusch.SymbolAllocation, pusch.dmrs); % DMRS 符号位置

            % 计算每 PRB 的数据 RE 数（上行通常无 PTRS，仅扣除 DMRS）
            re_per_prb_total = 12 * pusch_nsym;
            re_per_prb_dmrs = nr_dmrs_re_per_prb(pusch.dmrs);
            re_per_prb_data = re_per_prb_total - re_per_prb_dmrs * length(pusch_dmrs_symbols);
            re_per_prb_data = max(re_per_prb_data, 0);

            % 总编码比特数 G
            G_pusch = length(pusch.PRBSet) * re_per_prb_data * Qm_pusch * pusch.NumLayers;
            % 近似传输块大小
            TB_pusch = floor(G_pusch * pusch.TargetCodeRate);

            % 存储派生参数
            user_para{n_cell, n_user}.nr.pusch.derived.Qm = Qm_pusch;
            user_para{n_cell, n_user}.nr.pusch.derived.DMRSSymbolSet = pusch_dmrs_symbols;
            user_para{n_cell, n_user}.nr.pusch.derived.REPerPRB = re_per_prb_data;
            user_para{n_cell, n_user}.nr.pusch.derived.G = G_pusch;
            user_para{n_cell, n_user}.nr.pusch.derived.TargetTBSize = TB_pusch;

            % 初始化 PUSCH 运行时
            user_para{n_cell, n_user}.nr.pusch.runtime.active = 0;
            user_para{n_cell, n_user}.nr.pusch.runtime.slot = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.PRBSet = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.SymbolSet = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.DMRSSymbolSet = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.PayloadType = 'ULSCH';
            user_para{n_cell, n_user}.nr.pusch.runtime.transportBlock = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.transportBlockSize = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.HARQProcessID = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.RedundancyVersion = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.puschIndicesInfo = [];
        end

        % ---------------- PUCCH 运行时初始化 ----------------
        if isfield(ue, 'pucch') && isfield(ue.pucch, 'enable') && strcmpi(ue.pucch.enable, 'YES')
            user_para{n_cell, n_user}.nr.pucch.runtime.active = 0;
            user_para{n_cell, n_user}.nr.pucch.runtime.slot = [];
            user_para{n_cell, n_user}.nr.pucch.runtime.PRBSet = [];
            user_para{n_cell, n_user}.nr.pucch.runtime.SymbolSet = [];
            user_para{n_cell, n_user}.nr.pucch.runtime.DMRSSymbolSet = [];
            user_para{n_cell, n_user}.nr.pucch.runtime.Format = ue.pucch.format;
            user_para{n_cell, n_user}.nr.pucch.runtime.PayloadType = 'NONE';
            user_para{n_cell, n_user}.nr.pucch.runtime.PayloadBits = 0;
            user_para{n_cell, n_user}.nr.pucch.runtime.resourceIndex = ue.pucch.resourceIndex;
        end

        % ---------------- SSB 用户级运行时 ----------------
        user_para{n_cell, n_user}.nr.ssb.runtime.active = 0;
        user_para{n_cell, n_user}.nr.ssb.runtime.SymbolSet = [];

        % ---------------- HARQ 软缓冲区初始化 ----------------
        user_para{n_cell, n_user}.nr.harq.num_process = 16;           % HARQ 进程数
        user_para{n_cell, n_user}.nr.harq.rv_sequence = [0 2 3 1];    % 冗余版本序列
        user_para{n_cell, n_user}.nr.harq.softbuffer = cell(1, 16);   % 每个进程的软比特缓冲区
        for ih = 1:16
            user_para{n_cell, n_user}.nr.harq.softbuffer{ih} = [];
        end

        % ---------------- 用户通用运行时 ----------------
        user_para{n_cell, n_user}.nr.runtime.current_slot = 0;
        user_para{n_cell, n_user}.nr.runtime.current_frame = 0;
        user_para{n_cell, n_user}.nr.runtime.current_link_type = 'DOWNLINK';
        user_para{n_cell, n_user}.nr.runtime.txGrid = [];
        user_para{n_cell, n_user}.nr.runtime.txWaveform = [];
        user_para{n_cell, n_user}.nr.runtime.ofdmInfo = [];
    end
end

% ----------------------------------------------------------------------
% 6. 同步全局 frame_cfg（用于帧结构管理）
% ----------------------------------------------------------------------
% 注意：这里假设至少有一个小区，且使用第一个小区的参数作为全局 frame_cfg
frame_cfg.unit_name = 'SLOT';                                    % 基本单元为时隙
frame_cfg.mu = cell_para{1, 1}.nr.mu;                           % 子载波间隔配置
frame_cfg.scs = cell_para{1, 1}.nr.scs;                         % 子载波间隔（Hz）
frame_cfg.unit_per_subframe = cell_para{1, 1}.nr.slots_per_subframe; % 每子帧时隙数
frame_cfg.unit_per_frame = cell_para{1, 1}.nr.slots_per_frame;  % 每帧时隙数
frame_cfg.symbols_per_unit = cell_para{1, 1}.nr.symbols_per_slot;    % 每时隙符号数
frame_cfg.sample_rate = cell_para{1, 1}.nr.sample_rate;         % 采样率
frame_cfg.samples_per_unit = cell_para{1, 1}.nr.samples_per_slot;    % 每时隙采样点数
end

%% =======================================================================
% 局部辅助函数
% =======================================================================

% 功能：根据调制方式名称返回调制阶数（每符号比特数）
function Qm = nr_mod_order(modulation)
switch upper(modulation)
    case 'BPSK'
        Qm = 1;
    case 'QPSK'
        Qm = 2;
    case '16QAM'
        Qm = 4;
    case '64QAM'
        Qm = 6;
    case '256QAM'
        Qm = 8;
    otherwise
        error('Unsupported modulation: %s', modulation);
end
end

% 功能：计算 NR PDSCH 的 DMRS 符号位置（绝对符号索引）
function dmrs_sym = nr_pdsch_dmrs_symbols(symAlloc, dmrs)
startSym = symAlloc(1);        % PDSCH 起始符号
nSym = symAlloc(2);            % PDSCH 占用的符号数
dataSymSet = startSym:(startSym + nSym - 1);  % PDSCH 占用的所有符号

% 若 DMRS 未使能，返回空
if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrs_sym = [];
    return;
end

% DMRSLength: 1 或 2，表示单符号还是双符号 DMRS
if dmrs.DMRSLength == 2
    Ldmrs = 2;
else
    Ldmrs = 1;
end

% DMRSTypeAPosition: DMRS 在时隙内的第一个可能位置（通常为 2 或 3）
l0 = dmrs.DMRSTypeAPosition;

% 根据 DMRSAdditionalPosition 确定候选符号
switch dmrs.DMRSAdditionalPosition
    case 0
        cand = [l0];
    case 1
        cand = [l0, l0+4];
    case 2
        cand = [l0, l0+4, l0+7];
    otherwise
        cand = [l0, l0+3, l0+6, l0+9];
end

% 保留落在 PDSCH 符号范围内的候选
dmrs_sym = cand(ismember(cand, dataSymSet));

% 若为双符号 DMRS，则每个候选位置再增加一个相邻符号
if Ldmrs == 2
    dmrs_sym = unique([dmrs_sym, dmrs_sym+1]);
    dmrs_sym = dmrs_sym(ismember(dmrs_sym, dataSymSet));
end
end

% 功能：计算 NR PUSCH 的 DMRS 符号位置（与 PDSCH 类似，但起始符号需与分配对齐）
function dmrs_sym = nr_pusch_dmrs_symbols(symAlloc, dmrs)
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym + nSym - 1);

if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrs_sym = [];
    return;
end

% PUSCH 的 DMRSTypeAPosition 不能小于 startSym
l0 = max(dmrs.DMRSTypeAPosition, startSym);

switch dmrs.DMRSAdditionalPosition
    case 0
        cand = [l0];
    case 1
        cand = [l0, l0+4];
    case 2
        cand = [l0, l0+4, l0+7];
    otherwise
        cand = [l0, l0+3, l0+6, l0+9];
end

dmrs_sym = cand(ismember(cand, dataSymSet));

if dmrs.DMRSLength == 2
    dmrs_sym = unique([dmrs_sym, dmrs_sym+1]);
    dmrs_sym = dmrs_sym(ismember(dmrs_sym, dataSymSet));
end
end

% 功能：计算 PTRS 符号位置（简化版，仅基于时域密度）
function ptrs_sym = nr_ptrs_symbols(symAlloc, dmrs_sym, ptrs)
if ~isfield(ptrs, 'enable') || strcmpi(ptrs.enable, 'NO')
    ptrs_sym = [];
    return;
end

startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym + nSym - 1);

% 从 startSym+1 开始，每 TimeDensity 个符号插入一个 PTRS
cand = startSym+1 : ptrs.TimeDensity : (startSym + nSym - 1);
cand = setdiff(cand, dmrs_sym);   % 排除 DMRS 符号
ptrs_sym = cand(ismember(cand, dataSymSet));
end

% 功能：计算每 PRB 每个 DMRS 符号占用的 RE 数（与 DMRS 配置类型相关）
function re_dmrs = nr_dmrs_re_per_prb(dmrs)
% DMRSConfigurationType: 1 为梳状结构，每端口每 PRB 6 个 RE；2 为频分结构，每端口 4 个 RE
if dmrs.DMRSConfigurationType == 1
    re_dmrs = 6 * dmrs.NumCDMGroupsWithoutData;  % NumCDMGroupsWithoutData 通常为 1,2,3
else
    re_dmrs = 4 * dmrs.NumCDMGroupsWithoutData;
end
end

% 功能：计算每 PRB 因 PTRS 占用的 RE 数（简化，每符号 2 个 RE）
function re_ptrs = nr_ptrs_re_per_prb(ptrs, nPtrsSym)
if ~isfield(ptrs, 'enable') || strcmpi(ptrs.enable, 'NO') || nPtrsSym == 0
    re_ptrs = 0;
    return;
end
% 每个 PTRS 符号占用 2 个 RE（一个子载波对？简化假设）
re_ptrs = 2 * nPtrsSym;
end

% 功能：初始化与 legacy 信道模型兼容的字段（便于复用 LTE 信道模块）
function local_init_legacy_channel_compat(n_cell, Fs, scs, symbols_per_slot, cp_lengths)
globals_declare;

% 创建 legacy_cm 结构体（若不存在）
if ~isfield(cell_para{1, n_cell}, 'legacy_cm') || isempty(cell_para{1, n_cell}.legacy_cm)
    cell_para{1, n_cell}.legacy_cm = struct;
end
% 填写兼容字段
cell_para{1, n_cell}.legacy_cm.Nsc_RB = 12;  % 每 RB 子载波数
cell_para{1, n_cell}.legacy_cm.normal_cp_length = [cp_lengths(1), cp_lengths(min(2, length(cp_lengths)))];
cell_para{1, n_cell}.legacy_cm.ex_cp_length = [cp_lengths(1)];
cell_para{1, n_cell}.legacy_cm.sampling_interval = 1 / Fs;
cell_para{1, n_cell}.legacy_cm.useful_symbol_time = 1 / scs;
cell_para{1, n_cell}.legacy_cm.N_symbol = symbols_per_slot;

% 将上述字段镜像到 cell_para 顶层（某些遗留代码直接读取这些字段）
cell_para{1, n_cell}.Nsc_RB = cell_para{1, n_cell}.legacy_cm.Nsc_RB;
cell_para{1, n_cell}.normal_cp_length = cell_para{1, n_cell}.legacy_cm.normal_cp_length;
cell_para{1, n_cell}.ex_cp_length = cell_para{1, n_cell}.legacy_cm.ex_cp_length;
cell_para{1, n_cell}.sampling_interval = cell_para{1, n_cell}.legacy_cm.sampling_interval;
cell_para{1, n_cell}.useful_symbol_time = cell_para{1, n_cell}.legacy_cm.useful_symbol_time;

% 初始化 sim_para.legacy_cm（若不存在）
if ~isfield(sim_para, 'legacy_cm') || isempty(sim_para.legacy_cm)
    sim_para.legacy_cm = struct;
end
if ~isfield(sim_para.legacy_cm, 'frequency_offset') || isempty(sim_para.legacy_cm.frequency_offset)
    sim_para.legacy_cm.frequency_offset = 0;
end
if ~isfield(sim_para.legacy_cm, 'chest_method') || isempty(sim_para.legacy_cm.chest_method)
    sim_para.legacy_cm.chest_method.downlink = 'PERFECT';
    sim_para.legacy_cm.chest_method.uplink = 'PERFECT';
end
if ~isfield(sim_para.legacy_cm, 'chest_R_F_option') || isempty(sim_para.legacy_cm.chest_R_F_option)
    sim_para.legacy_cm.chest_R_F_option = 'MAXCP';
end
if ~isfield(sim_para.legacy_cm, 'chest_R_T_option') || isempty(sim_para.legacy_cm.chest_R_T_option)
    sim_para.legacy_cm.chest_R_T_option = 'BESSEL';
end
% 同步到 sim_para 顶层
sim_para.frequency_offset = sim_para.legacy_cm.frequency_offset;
sim_para.chest_method = sim_para.legacy_cm.chest_method;
sim_para.chest_R_F_option = sim_para.legacy_cm.chest_R_F_option;
sim_para.chest_R_T_option = sim_para.legacy_cm.chest_R_T_option;

% 初始化 sys_para.legacy_ch（信道模型相关）
if ~isfield(sys_para, 'legacy_ch') || isempty(sys_para.legacy_ch)
    sys_para.legacy_ch = struct;
end
if ~isfield(sys_para.legacy_ch, 'channel_model') || isempty(sys_para.legacy_ch.channel_model)
    sys_para.legacy_ch.channel_model = 'SCM';
end
if ~isfield(sys_para.legacy_ch, 'LLS_PDP') || isempty(sys_para.legacy_ch.LLS_PDP)
    sys_para.legacy_ch.LLS_PDP = 'GSM_TU';
end
if ~isfield(sys_para.legacy_ch, 'carrier_frequency') || isempty(sys_para.legacy_ch.carrier_frequency)
    % 尝试从 NR 载波配置中读取中心频率，否则使用默认 3.5GHz
    if isfield(cell_para{1, n_cell}, 'nr') && isfield(cell_para{1, n_cell}.nr, 'carrier') && isfield(cell_para{1, n_cell}.nr.carrier, 'fc')
        sys_para.legacy_ch.carrier_frequency = cell_para{1, n_cell}.nr.carrier.fc;
    else
        sys_para.legacy_ch.carrier_frequency = 3.5e9;
    end
end
if ~isfield(sys_para.legacy_ch, 'scm_method') || isempty(sys_para.legacy_ch.scm_method)
    sys_para.legacy_ch.scm_method = 0;
end
if ~isfield(sys_para.legacy_ch, 'corr_grade') || isempty(sys_para.legacy_ch.corr_grade)
    sys_para.legacy_ch.corr_grade = 'LOW';
end
% 同步到 sys_para.CH（某些代码直接读取 sys_para.CH）
sys_para.CH = sys_para.legacy_ch;
end