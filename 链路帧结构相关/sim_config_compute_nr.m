function sim_config_compute_nr(varargin)
% sim_config_compute_nr - NR时隙配置预计算函数
%
% 功能描述：
%   本函数用于NR系统仿真中，在开始一个时隙（slot）的发射和接收处理之前，
%   预先计算该时隙的运行时配置信息。主要任务包括：
%     1) 根据输入参数（帧号、时隙号）确定当前时隙的链路方向（下行/上行/灵活）；
%     2) 根据小区配置的时隙图样（slot_link_config）和灵活时隙处理规则，
%        确定当前时隙的有效链路类型（effective_link_type）；
%     3) 初始化小区和所有用户的运行时结构体，填充该时隙的信道激活状态、
%        资源分配（PRB、符号集）、DMRS/PTRS符号位置等；
%     4) 调用图样生成函数（DL/UL slot pattern）用于调试和记录。
%
% 输入参数：
%   支持两种调用方式：
%     - sim_config_compute_nr(n_frame, n_slot) : 显式指定帧号和时隙号
%     - sim_config_compute_nr(n_slot) : 仅指定时隙号，帧号从sim_para.global_unit_index推算
%
% 输出参数：
%   无显式输出，但会更新全局结构体：
%     - cell_para{1,n_cell}.nr.runtime : 小区级运行时信息
%     - user_para{n_cell,n_user}.nr.*.runtime : 用户级信道运行时信息
%     - sim_para.sim_link_type : 当前链路类型（供上层使用）
%     - frame_cfg.current : 当前时隙/子帧信息

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量：cell_para, user_para, sys_para, sim_para, frame_cfg

% ========================== 1. 解析输入参数 ==========================
% 根据输入参数个数确定调用方式
if nargin == 2
    % 方式1：同时传入帧号和时隙号
    n_frame = varargin{1};   % 帧号（10ms帧）
    n_slot = varargin{2};    % 时隙号（在帧内的索引，0 ~ slots_per_frame-1）
elseif nargin == 1
    % 方式2：仅传入时隙号，帧号从全局单元索引推算
    n_slot = varargin{1};
    % 检查sim_para中是否存在全局单元索引，以及frame_cfg中每帧单元数
    if isfield(sim_para, 'global_unit_index') && ~isempty(sim_para.global_unit_index) ...
            && isfield(frame_cfg, 'unit_per_frame') && ~isempty(frame_cfg.unit_per_frame)
        % 全局单元索引 = 帧号 * 每帧单元数 + 单元内偏移
        n_frame = floor(sim_para.global_unit_index / frame_cfg.unit_per_frame);
    else
        n_frame = 0;   % 默认帧号为0
    end
else
    error('sim_config_compute_nr: invalid input arguments.');
end

% ========================== 2. 初步检查全局变量 ==========================
% 获取用户参数矩阵的尺寸
[cell_num, user_num] = size(user_para);
if cell_num == 0 || user_num == 0
    error('sim_config_compute_nr: user_para/cell_para is empty.');
end

% ========================== 3. 遍历所有小区 ==========================
for n_cell = 1:cell_num
    if isempty(cell_para{1, n_cell})
        continue;   % 跳过空小区
    end
    % 检查小区是否配置了NR参数
    if ~isfield(cell_para{1, n_cell}, 'nr') || isempty(cell_para{1, n_cell}.nr)
        error('sim_config_compute_nr: cell_para{%d}.nr is missing.', n_cell);
    end

    nr = cell_para{1, n_cell}.nr;   % NR配置结构体
    slots_per_frame = nr.slots_per_frame;      % 每帧的时隙数
    symbols_per_slot = nr.symbols_per_slot;    % 每时隙的OFDM符号数
    % 检查时隙号范围
    if n_slot < 0 || n_slot >= slots_per_frame
        error('sim_config_compute_nr: n_slot out of range.');
    end
    slot_idx = n_slot + 1;   % 转换为1-based索引（用于MATLAB数组）

    % ---------- 3.1 计算当前子帧号和帧号 ----------
    cur_frame = n_frame;
    cur_subframe = floor(n_slot / nr.slots_per_subframe);  % 每个子帧包含的时隙数

    % ---------- 3.2 获取时隙的链路配置（由高层配置） ----------
    % slot_link_config: 1=下行, -1=上行, 0=灵活
    slot_flag = nr.slot_link_config(slot_idx);

    % ---------- 3.3 确定当前时隙的链路类型 ----------
    if slot_flag == 1
        cur_link_type = 'DOWNLINK';
        effective_link_type = 'DOWNLINK';
    elseif slot_flag == -1
        cur_link_type = 'UPLINK';
        effective_link_type = 'UPLINK';
    elseif slot_flag == 0
        cur_link_type = 'FLEXIBLE';   % 灵活时隙，由高层决定具体方向
        % 灵活时隙的有效方向根据全局配置 frame_cfg.flexible_slot_as 确定
        effective_link_type = upper(frame_cfg.flexible_slot_as);
    else
        error('sim_config_compute_nr: invalid nr.slot_link_config value.');
    end

    % 将有效链路类型存储到仿真参数中（供发射/接收循环使用）
    sim_para.sim_link_type = effective_link_type;

    % ---------- 3.4 获取当前时隙激活的信道列表 ----------
    % slot_channel_config: 每个时隙的信道配置，例如 {'PDSCH','PDCCH','PUSCH',...}
    active_channels = nr.slot_channel_config{slot_idx};
    if isempty(active_channels)
        active_channels = {};   % 确保为cell数组
    end

    % ---------- 3.5 判断SSB是否在当前时隙激活 ----------
    ssb_active = 0;
    if isfield(nr, 'ssb') && isfield(nr.ssb, 'enable') && strcmpi(nr.ssb.enable, 'YES')
        periodicity_ms = nr.ssb.periodicity_ms;   % SSB周期（毫秒）
        if isempty(periodicity_ms) || periodicity_ms <= 0
            periodicity_ms = 20;   % 默认20ms周期
        end
        % 将周期从毫秒转换为时隙数
        periodicity_slots = round((periodicity_ms / 10) * slots_per_frame);
        if periodicity_slots <= 0
            periodicity_slots = slots_per_frame;
        end
        % 绝对时隙号（从帧0开始）
        abs_slot = cur_frame * slots_per_frame + n_slot;
        % 如果小区SSB配置中指定了激活的时隙掩码，则检查当前时隙是否在掩码中
        if isfield(nr.ssb, 'active_slots') && length(nr.ssb.active_slots) >= slot_idx
            if nr.ssb.active_slots(slot_idx) == 1 && mod(abs_slot, periodicity_slots) == 0
                ssb_active = 1;
            end
        end
    end

    % ---------- 3.6 生成每个符号的角色（用于灵活时隙的细化） ----------
    % slot_symbol_role: 长度为 symbols_per_slot 的cell数组，每个元素为 'DL', 'UL', 'FLEX', 'IDLE'
    slot_symbol_role = repmat({'IDLE'}, 1, symbols_per_slot);
    if slot_flag == 1
        % 全下行时隙：所有符号为 DL
        slot_symbol_role(:) = {'DL'};
    elseif slot_flag == -1
        % 全上行时隙：所有符号为 UL
        slot_symbol_role(:) = {'UL'};
    else
        % 灵活时隙：根据一个简单示例划分（实际应基于更详细的配置）
        % 这里假设前10个符号为DL，中间2个为FLEX，最后2个为UL
        slot_symbol_role(1:10)  = {'DL'};
        slot_symbol_role(11:12) = {'FLEX'};
        slot_symbol_role(13:14) = {'UL'};
    end

    % ---------- 3.7 初始化小区运行时结构体（公共字段） ----------
    cell_para{1, n_cell}.nr.runtime.current_frame = cur_frame;
    cell_para{1, n_cell}.nr.runtime.current_subframe = cur_subframe;
    cell_para{1, n_cell}.nr.runtime.current_slot = n_slot;
    cell_para{1, n_cell}.nr.runtime.current_link_type = cur_link_type;
    cell_para{1, n_cell}.nr.runtime.current_effective_link_type = effective_link_type;
    cell_para{1, n_cell}.nr.runtime.current_channels = active_channels;
    cell_para{1, n_cell}.nr.runtime.slot_symbol_role = slot_symbol_role;
    cell_para{1, n_cell}.nr.runtime.current_slot_pattern = [];   % 稍后填充
    cell_para{1, n_cell}.nr.runtime.txGrid = [];
    cell_para{1, n_cell}.nr.runtime.txWaveform = [];
    cell_para{1, n_cell}.nr.runtime.ofdmInfo = [];

    % 确定各信道是否激活（基于链路方向和信道列表）
    cell_para{1, n_cell}.nr.runtime.ssb_active = ssb_active;
    cell_para{1, n_cell}.nr.runtime.pdcch_active = local_pdcch_active(cell_para{1, n_cell}, active_channels, effective_link_type);
    cell_para{1, n_cell}.nr.runtime.pdsch_active = any(strcmpi(active_channels, 'PDSCH')) && ~strcmpi(effective_link_type, 'UPLINK');
    cell_para{1, n_cell}.nr.runtime.pusch_active = any(strcmpi(active_channels, 'PUSCH')) && ~strcmpi(effective_link_type, 'DOWNLINK');
    cell_para{1, n_cell}.nr.runtime.pucch_active = any(strcmpi(active_channels, 'PUCCH')) && ~strcmpi(effective_link_type, 'DOWNLINK');

    % ---------- 3.8 配置SSB运行时信息 ----------
    if ~isfield(cell_para{1, n_cell}.nr, 'ssb') || isempty(cell_para{1, n_cell}.nr.ssb)
        cell_para{1, n_cell}.nr.ssb = struct;
    end
    if ~isfield(cell_para{1, n_cell}.nr.ssb, 'runtime') || isempty(cell_para{1, n_cell}.nr.ssb.runtime)
        cell_para{1, n_cell}.nr.ssb.runtime = struct;
    end
    cell_para{1, n_cell}.nr.ssb.runtime.active = ssb_active;
    if ssb_active
        % 获取SSB占用的符号索引（0-based），默认符号0~3
        if isfield(cell_para{1, n_cell}.nr.ssb, 'symbols')
            cell_para{1, n_cell}.nr.ssb.runtime.SymbolSet = cell_para{1, n_cell}.nr.ssb.symbols;
        else
            cell_para{1, n_cell}.nr.ssb.runtime.SymbolSet = 0:3;
        end
    else
        cell_para{1, n_cell}.nr.ssb.runtime.SymbolSet = [];
    end
    cell_para{1, n_cell}.nr.ssb.runtime.SCSet = [];   % 子载波集合（稍后填充）

    % ---------- 3.9 配置PDCCH/CORESET运行时信息 ----------
    if ~isfield(cell_para{1, n_cell}.nr, 'pdcch') || isempty(cell_para{1, n_cell}.nr.pdcch)
        cell_para{1, n_cell}.nr.pdcch = struct;
    end
    if ~isfield(cell_para{1, n_cell}.nr.pdcch, 'runtime') || isempty(cell_para{1, n_cell}.nr.pdcch.runtime)
        cell_para{1, n_cell}.nr.pdcch.runtime = struct;
    end

    if cell_para{1, n_cell}.nr.runtime.pdcch_active
        % 从searchspace和coreset配置中获取PDCCH占用的符号
        first_symbol = cell_para{1, n_cell}.nr.searchspace.first_symbol;
        duration = cell_para{1, n_cell}.nr.coreset.duration;
        pdcch_symbol_set = first_symbol:(first_symbol + duration - 1);
        pdcch_symbol_set = pdcch_symbol_set(pdcch_symbol_set >= 0 & pdcch_symbol_set < symbols_per_slot);
        % 仅保留符合链路方向的符号（下行或灵活）
        pdcch_symbol_set = intersect(pdcch_symbol_set, local_dl_symbol_set(slot_symbol_role, effective_link_type));

        % 获取CORESET占用的PRB范围
        rb_start = cell_para{1, n_cell}.nr.coreset.rb_start;
        rb_size = cell_para{1, n_cell}.nr.coreset.rb_size;
        rb_set = rb_start:(rb_start + rb_size - 1);

        cell_para{1, n_cell}.nr.pdcch.runtime.active = 1;
        cell_para{1, n_cell}.nr.pdcch.runtime.SymbolSet = pdcch_symbol_set;
        cell_para{1, n_cell}.nr.pdcch.runtime.RBSet = rb_set;
        cell_para{1, n_cell}.nr.pdcch.runtime.AggregationLevel = cell_para{1, n_cell}.nr.searchspace.AL;
        cell_para{1, n_cell}.nr.pdcch.runtime.coreset_id = cell_para{1, n_cell}.nr.coreset.id;
        cell_para{1, n_cell}.nr.pdcch.runtime.searchspace_id = cell_para{1, n_cell}.nr.searchspace.id;
    else
        % PDCCH未激活，清空运行时字段
        cell_para{1, n_cell}.nr.pdcch.runtime.active = 0;
        cell_para{1, n_cell}.nr.pdcch.runtime.SymbolSet = [];
        cell_para{1, n_cell}.nr.pdcch.runtime.RBSet = [];
        cell_para{1, n_cell}.nr.pdcch.runtime.AggregationLevel = [];
        cell_para{1, n_cell}.nr.pdcch.runtime.coreset_id = [];
        cell_para{1, n_cell}.nr.pdcch.runtime.searchspace_id = [];
    end

    % ---------- 3.10 遍历所有用户，配置用户级运行时 ----------
    for n_user = 1:user_num
        if n_cell > size(user_para,1) || n_user > size(user_para,2) || isempty(user_para{n_cell, n_user})
            continue;   % 用户不存在或未配置
        end
        ue = user_para{n_cell, n_user}.nr;   % 用户NR配置

        % 公共运行时字段
        user_para{n_cell, n_user}.nr.runtime.current_frame = cur_frame;
        user_para{n_cell, n_user}.nr.runtime.current_slot = n_slot;
        user_para{n_cell, n_user}.nr.runtime.current_link_type = cur_link_type;
        user_para{n_cell, n_user}.nr.runtime.current_effective_link_type = effective_link_type;
        user_para{n_cell, n_user}.nr.runtime.txGrid = [];
        user_para{n_cell, n_user}.nr.runtime.txWaveform = [];
        user_para{n_cell, n_user}.nr.runtime.ofdmInfo = [];

        % ----- 3.10.1 PDSCH（下行数据信道）配置 -----
        if isfield(ue, 'pdsch') && isfield(ue.pdsch, 'enable') && strcmpi(ue.pdsch.enable, 'YES') ...
                && cell_para{1, n_cell}.nr.runtime.pdsch_active

            % 根据用户配置的SymbolAllocation生成符号集合（连续区间）
            pdsch_sym = ue.pdsch.SymbolAllocation(1):(ue.pdsch.SymbolAllocation(1) + ue.pdsch.SymbolAllocation(2) - 1);
            % 仅保留符合下行方向的符号（DL或FLEX）
            pdsch_sym = intersect(pdsch_sym, local_dl_symbol_set(slot_symbol_role, effective_link_type));

            % 如果PDCCH激活，则PDSCH不能占用PDCCH占用的符号（资源不重叠）
            if cell_para{1, n_cell}.nr.pdcch.runtime.active
                pdsch_sym = setdiff(pdsch_sym, cell_para{1, n_cell}.nr.pdcch.runtime.SymbolSet);
            end

            % 计算DMRS符号位置（基于PDSCH的DMRS配置）
            pdsch_dmrs = nr_pdsch_dmrs_symbols(ue.pdsch.SymbolAllocation, ue.pdsch.dmrs);
            pdsch_dmrs = intersect(pdsch_dmrs, pdsch_sym);

            % 计算PTRS符号位置（如果使能）
            if isfield(ue.pdsch, 'ptrs')
                pdsch_ptrs = nr_ptrs_symbols(ue.pdsch.SymbolAllocation, pdsch_dmrs, ue.pdsch.ptrs);
                pdsch_ptrs = intersect(pdsch_ptrs, pdsch_sym);
            else
                pdsch_ptrs = [];
            end

            % 计算每个PRB内可用于PDSCH的RE数量（排除DMRS和PTRS）
            exact_re_per_prb = local_count_pdsch_re(ue.pdsch, pdsch_sym, pdsch_dmrs, pdsch_ptrs);
            Qm = user_para{n_cell, n_user}.nr.pdsch.derived.Qm;   % 调制阶数
            % 总编码比特数 G = PRB数 * 每PRB有效RE数 * 调制阶数 * 层数
            G = length(ue.pdsch.PRBSet) * exact_re_per_prb * Qm * ue.pdsch.NumLayers;
            % 粗略传输块大小（目标码率）
            TB = floor(G * ue.pdsch.TargetCodeRate);

            % 保存PDSCH运行时信息
            user_para{n_cell, n_user}.nr.pdsch.runtime.active = ~isempty(pdsch_sym) && ~isempty(ue.pdsch.PRBSet);
            user_para{n_cell, n_user}.nr.pdsch.runtime.slot = n_slot;
            user_para{n_cell, n_user}.nr.pdsch.runtime.PRBSet = ue.pdsch.PRBSet;
            user_para{n_cell, n_user}.nr.pdsch.runtime.SymbolSet = pdsch_sym;
            user_para{n_cell, n_user}.nr.pdsch.runtime.DMRSSymbolSet = pdsch_dmrs;
            user_para{n_cell, n_user}.nr.pdsch.runtime.PTRSSymbolSet = pdsch_ptrs;
            user_para{n_cell, n_user}.nr.pdsch.runtime.transportBlock = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.transportBlockSize = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.HARQProcessID = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.RedundancyVersion = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.pdschIndicesInfo = [];
            user_para{n_cell, n_user}.nr.pdsch.runtime.G = G;
            user_para{n_cell, n_user}.nr.pdsch.runtime.TargetTBSize = TB;
            user_para{n_cell, n_user}.nr.pdsch.runtime.REPerPRB = exact_re_per_prb;
        else
            % PDSCH未激活，清空运行时
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
            user_para{n_cell, n_user}.nr.pdsch.runtime.G = 0;
            user_para{n_cell, n_user}.nr.pdsch.runtime.TargetTBSize = 0;
            user_para{n_cell, n_user}.nr.pdsch.runtime.REPerPRB = 0;
        end

        % ----- 3.10.2 PUSCH（上行数据信道）配置 -----
        if isfield(ue, 'pusch') && isfield(ue.pusch, 'enable') && strcmpi(ue.pusch.enable, 'YES') ...
                && cell_para{1, n_cell}.nr.runtime.pusch_active

            pusch_sym = ue.pusch.SymbolAllocation(1):(ue.pusch.SymbolAllocation(1) + ue.pusch.SymbolAllocation(2) - 1);
            pusch_sym = intersect(pusch_sym, local_ul_symbol_set(slot_symbol_role, effective_link_type));
            pusch_dmrs = nr_pusch_dmrs_symbols(ue.pusch.SymbolAllocation, ue.pusch.dmrs);
            pusch_dmrs = intersect(pusch_dmrs, pusch_sym);

            exact_re_per_prb = local_count_pusch_re(ue.pusch, pusch_sym, pusch_dmrs);
            Qm = user_para{n_cell, n_user}.nr.pusch.derived.Qm;
            G = length(ue.pusch.PRBSet) * exact_re_per_prb * Qm * ue.pusch.NumLayers;
            TB = floor(G * ue.pusch.TargetCodeRate);

            user_para{n_cell, n_user}.nr.pusch.runtime.active = ~isempty(pusch_sym) && ~isempty(ue.pusch.PRBSet);
            user_para{n_cell, n_user}.nr.pusch.runtime.slot = n_slot;
            user_para{n_cell, n_user}.nr.pusch.runtime.PRBSet = ue.pusch.PRBSet;
            user_para{n_cell, n_user}.nr.pusch.runtime.SymbolSet = pusch_sym;
            user_para{n_cell, n_user}.nr.pusch.runtime.DMRSSymbolSet = pusch_dmrs;
            user_para{n_cell, n_user}.nr.pusch.runtime.PayloadType = 'ULSCH';
            user_para{n_cell, n_user}.nr.pusch.runtime.transportBlock = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.transportBlockSize = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.HARQProcessID = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.RedundancyVersion = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.puschIndicesInfo = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.G = G;
            user_para{n_cell, n_user}.nr.pusch.runtime.TargetTBSize = TB;
            user_para{n_cell, n_user}.nr.pusch.runtime.REPerPRB = exact_re_per_prb;
        else
            user_para{n_cell, n_user}.nr.pusch.runtime.active = 0;
            user_para{n_cell, n_user}.nr.pusch.runtime.slot = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.PRBSet = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.SymbolSet = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.DMRSSymbolSet = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.PayloadType = 'NONE';
            user_para{n_cell, n_user}.nr.pusch.runtime.transportBlock = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.transportBlockSize = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.HARQProcessID = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.RedundancyVersion = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.puschIndicesInfo = [];
            user_para{n_cell, n_user}.nr.pusch.runtime.G = 0;
            user_para{n_cell, n_user}.nr.pusch.runtime.TargetTBSize = 0;
            user_para{n_cell, n_user}.nr.pusch.runtime.REPerPRB = 0;
        end

        % ----- 3.10.3 PUCCH（上行控制信道）配置 -----
        if isfield(ue, 'pucch') && isfield(ue.pucch, 'enable') && strcmpi(ue.pucch.enable, 'YES') ...
                && cell_para{1, n_cell}.nr.runtime.pucch_active
            pucch_sym = local_pucch_symbol_set(ue.pucch, slot_symbol_role, effective_link_type, symbols_per_slot);
            pucch_prb = local_pucch_prb_set(ue.pucch, cell_para{1, n_cell}, effective_link_type);
            pucch_dmrs = local_pucch_dmrs_symbols(ue.pucch, pucch_sym);
            [payload_type, payload_bits] = local_pucch_payload(ue.pucch);

            user_para{n_cell, n_user}.nr.pucch.runtime.active = ~isempty(pucch_sym) && ~isempty(pucch_prb);
            user_para{n_cell, n_user}.nr.pucch.runtime.slot = n_slot;
            user_para{n_cell, n_user}.nr.pucch.runtime.PRBSet = pucch_prb;
            user_para{n_cell, n_user}.nr.pucch.runtime.SymbolSet = pucch_sym;
            user_para{n_cell, n_user}.nr.pucch.runtime.DMRSSymbolSet = pucch_dmrs;
            user_para{n_cell, n_user}.nr.pucch.runtime.Format = ue.pucch.format;
            user_para{n_cell, n_user}.nr.pucch.runtime.PayloadType = payload_type;
            user_para{n_cell, n_user}.nr.pucch.runtime.PayloadBits = payload_bits;
            user_para{n_cell, n_user}.nr.pucch.runtime.resourceIndex = ue.pucch.resourceIndex;
        else
            if isfield(user_para{n_cell, n_user}.nr, 'pucch')
                user_para{n_cell, n_user}.nr.pucch.runtime.active = 0;
                user_para{n_cell, n_user}.nr.pucch.runtime.slot = [];
                user_para{n_cell, n_user}.nr.pucch.runtime.PRBSet = [];
                user_para{n_cell, n_user}.nr.pucch.runtime.SymbolSet = [];
                user_para{n_cell, n_user}.nr.pucch.runtime.DMRSSymbolSet = [];
                user_para{n_cell, n_user}.nr.pucch.runtime.Format = [];
                user_para{n_cell, n_user}.nr.pucch.runtime.PayloadType = 'NONE';
                user_para{n_cell, n_user}.nr.pucch.runtime.PayloadBits = 0;
                user_para{n_cell, n_user}.nr.pucch.runtime.resourceIndex = [];
            end
        end

        % ----- 3.10.4 SSB（用户级运行时，通常与小区一致） -----
        user_para{n_cell, n_user}.nr.ssb.runtime.active = ssb_active;
        if ssb_active
            if isfield(cell_para{1, n_cell}.nr.ssb, 'symbols')
                user_para{n_cell, n_user}.nr.ssb.runtime.SymbolSet = cell_para{1, n_cell}.nr.ssb.symbols;
            else
                user_para{n_cell, n_user}.nr.ssb.runtime.SymbolSet = 0:3;
            end
        else
            user_para{n_cell, n_user}.nr.ssb.runtime.SymbolSet = [];
        end
    end   % 结束用户循环

    % ---------- 3.11 生成图样（仅用于调试和记录） ----------
    if strcmpi(effective_link_type, 'DOWNLINK')
        % 下行时隙：生成下行slot pattern
        cell_para{1, n_cell}.nr.runtime.current_slot_pattern = DL_slot_pattern_nr(cell_para{1, n_cell}.cellID, n_slot);
        cell_para{1, n_cell}.nr.runtime.current_ul_slot_pattern = [];

        % 生成下行参考信号图样（PDSCH DMRS/PTRS等）
        [cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern, ...
         cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern, ...
         cell_para{1, n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern, ...
         cell_para{1, n_cell}.nr.runtime.CSI_RS_PRB_pattern] = DL_RS_pattern_nr(cell_para{1, n_cell}.cellID);

        cell_para{1, n_cell}.nr.runtime.PUCCH_PRB_DMRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.SRS_PRB_pattern = [];

    elseif strcmpi(effective_link_type, 'UPLINK')
        % 上行时隙：生成上行slot pattern
        cell_para{1, n_cell}.nr.runtime.current_slot_pattern = [];
        cell_para{1, n_cell}.nr.runtime.current_ul_slot_pattern = UL_slot_pattern_nr(cell_para{1, n_cell}.cellID, n_slot);

        cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.CSI_RS_PRB_pattern = [];

        % 生成上行参考信号图样（PUSCH DMRS, PUCCH DMRS, SRS）
        [cell_para{1, n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern, ...
         cell_para{1, n_cell}.nr.runtime.PUCCH_PRB_DMRS_pattern, ...
         cell_para{1, n_cell}.nr.runtime.SRS_PRB_pattern] = UL_RS_pattern_nr(cell_para{1, n_cell}.cellID);
    else
        % 其他情况（如灵活时隙但未确定方向）清空所有图样
        cell_para{1, n_cell}.nr.runtime.current_slot_pattern = [];
        cell_para{1, n_cell}.nr.runtime.current_ul_slot_pattern = [];
        cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_DMRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.PDSCH_PRB_PTRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.PUSCH_PRB_DMRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.PUCCH_PRB_DMRS_pattern = [];
        cell_para{1, n_cell}.nr.runtime.CSI_RS_PRB_pattern = [];
        cell_para{1, n_cell}.nr.runtime.SRS_PRB_pattern = [];
    end
end   % 结束小区循环

% ========================== 4. 更新帧结构全局变量 ==========================
% 记录当前时隙和子帧信息，供其他模块使用
frame_cfg.current.n_slot = n_slot;
frame_cfg.current.n_subframe = floor(n_slot / cell_para{1,1}.nr.slots_per_subframe);
frame_cfg.current.sim_link_type = sim_para.sim_link_type;

end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function active = local_pdcch_active(cellCfg, active_channels, effective_link_type)
% 判断PDCCH是否在当前时隙激活
active = false;
if ~strcmpi(effective_link_type, 'DOWNLINK')
    return;   % 非下行时隙无PDCCH
end
if ~isfield(cellCfg.nr, 'pdcch') || ~isfield(cellCfg.nr.pdcch, 'enable') || ~strcmpi(cellCfg.nr.pdcch.enable, 'YES')
    return;   % 小区未使能PDCCH
end
active = any(strcmpi(active_channels, 'PDCCH'));   % 检查信道列表中是否包含PDCCH
end

function symSet = local_dl_symbol_set(slot_symbol_role, effective_link_type)
% 获取可用于下行传输的符号索引（0-based）
if strcmpi(effective_link_type, 'DOWNLINK')
    % 下行时隙：所有非UL符号（即DL或FLEX）均可用于下行
    idx = find(~strcmpi(slot_symbol_role, 'UL')) - 1;
else
    idx = [];
end
symSet = idx(:).';
end

function symSet = local_ul_symbol_set(slot_symbol_role, effective_link_type)
% 获取可用于上行传输的符号索引（0-based）
if strcmpi(effective_link_type, 'UPLINK')
    % 上行时隙：所有非DL符号（即UL或FLEX）均可用于上行
    idx = find(~strcmpi(slot_symbol_role, 'DL')) - 1;
else
    idx = [];
end
symSet = idx(:).';
end

function symSet = local_pucch_symbol_set(pucchCfg, slot_symbol_role, effective_link_type, symbols_per_slot)
% 根据PUCCH格式确定占用的符号集合
ulSymSet = local_ul_symbol_set(slot_symbol_role, effective_link_type);
if isempty(ulSymSet)
    symSet = [];
    return;
end

switch pucchCfg.format
    case 0
        nSym = 1;   % 格式0占用1个符号
    case 1
        nSym = min(4, length(ulSymSet));   % 格式1最多4个符号
    otherwise
        nSym = min(2, length(ulSymSet));   % 其他格式通常2个符号
end

% 取上行可用符号的最后 nSym 个符号（通常PUCCH位于时隙末尾）
symSet = ulSymSet(max(length(ulSymSet)-nSym+1, 1):end);
symSet = symSet(symSet >= 0 & symSet < symbols_per_slot);
end

function prbSet = local_pucch_prb_set(pucchCfg, cellCfg, effective_link_type)
% 确定PUCCH占用的PRB索引（0-based）
if ~strcmpi(effective_link_type, 'UPLINK')
    prbSet = [];
    return;
end

N_RB_UL = cellCfg.N_RB_UL;   % 上行带宽（RB数）
resIdx = 0;
if isfield(pucchCfg, 'resourceIndex') && ~isempty(pucchCfg.resourceIndex)
    resIdx = pucchCfg.resourceIndex;
end

% 根据资源索引决定在带宽边缘的哪一侧（偶数索引在低频侧，奇数在高频侧）
edgeRb = mod(resIdx, max(N_RB_UL, 1));
if mod(resIdx, 2) == 0
    prbSet = edgeRb;          % 低频边缘
else
    prbSet = max(N_RB_UL - 1 - edgeRb, 0);   % 高频边缘
end
prbSet = unique(prbSet(prbSet >= 0 & prbSet < N_RB_UL));
end

function dmrsSymSet = local_pucch_dmrs_symbols(pucchCfg, symSet)
% 确定PUCCH DMRS占用的符号位置
if isempty(symSet)
    dmrsSymSet = [];
    return;
end

switch pucchCfg.format
    case 1
        % 格式1：DMRS位于奇数索引符号（1-based中的第1,3,...）
        dmrsSymSet = symSet(1:2:end);
    otherwise
        % 其他格式：通常DMRS在第一个符号
        dmrsSymSet = symSet(1);
end
end

function [payloadType, payloadBits] = local_pucch_payload(pucchCfg)
% 获取PUCCH承载的UCI类型和比特数
payloadType = 'NONE';
payloadBits = 0;

if isfield(pucchCfg, 'ACK_enable') && strcmpi(pucchCfg.ACK_enable, 'YES')
    payloadType = 'HARQ-ACK';
    payloadBits = payloadBits + 1;
end
if isfield(pucchCfg, 'SR_enable') && strcmpi(pucchCfg.SR_enable, 'YES')
    if strcmp(payloadType, 'NONE')
        payloadType = 'SR';
    else
        payloadType = [payloadType '+SR'];
    end
    payloadBits = payloadBits + 1;
end
if isfield(pucchCfg, 'CSI_enable') && strcmpi(pucchCfg.CSI_enable, 'YES')
    if strcmp(payloadType, 'NONE')
        payloadType = 'CSI';
    else
        payloadType = [payloadType '+CSI'];
    end
    payloadBits = payloadBits + 1;
end
end

function dmrs_sym = nr_pdsch_dmrs_symbols(symAlloc, dmrs)
% 计算PDSCH DMRS的符号位置（0-based）
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrs_sym = [];
    return;
end

l0 = dmrs.DMRSTypeAPosition;   % TypeA DMRS起始符号（2或3）
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
    % 双符号DMRS：每个位置占用连续两个符号
    dmrs_sym = unique([dmrs_sym, dmrs_sym+1]);
    dmrs_sym = dmrs_sym(ismember(dmrs_sym, dataSymSet));
end
end

function dmrs_sym = nr_pusch_dmrs_symbols(symAlloc, dmrs)
% 计算PUSCH DMRS的符号位置（逻辑与PDSCH类似）
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrs_sym = [];
    return;
end

l0 = max(dmrs.DMRSTypeAPosition, startSym);   % PUSCH的TypeA起始符号不能早于分配起始
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

function ptrs_sym = nr_ptrs_symbols(symAlloc, dmrs_sym, ptrs)
% 计算PTRS的符号位置（基于时域密度）
if ~isfield(ptrs, 'enable') || strcmpi(ptrs.enable, 'NO')
    ptrs_sym = [];
    return;
end

startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);

% PTRS符号从 startSym+1 开始，每隔 TimeDensity 个符号放置一个
cand = startSym+1 : ptrs.TimeDensity : (startSym+nSym-1);
cand = setdiff(cand, dmrs_sym);   % 不能与DMRS重叠
ptrs_sym = cand(ismember(cand, dataSymSet));
end

function re_per_prb = local_count_pdsch_re(pdsch, symSet, dmrsSymSet, ptrsSymSet)
% 计算每个PRB内可用于PDSCH数据的RE数量
nDataSym = numel(symSet);
re_per_prb_total = 12 * nDataSym;   % 每个PRB 12个子载波
re_per_prb_dmrs = nr_dmrs_re_per_prb(pdsch.dmrs) * numel(dmrsSymSet);
if isfield(pdsch, 'ptrs')
    re_per_prb_ptrs = nr_ptrs_re_per_prb(pdsch.ptrs, numel(ptrsSymSet));
else
    re_per_prb_ptrs = 0;
end
re_per_prb = re_per_prb_total - re_per_prb_dmrs - re_per_prb_ptrs;
re_per_prb = max(re_per_prb, 0);
end

function re_per_prb = local_count_pusch_re(pusch, symSet, dmrsSymSet)
% 计算每个PRB内可用于PUSCH数据的RE数量（PUSCH通常无PTRS开销）
nDataSym = numel(symSet);
re_per_prb_total = 12 * nDataSym;
re_per_prb_dmrs = nr_dmrs_re_per_prb(pusch.dmrs) * numel(dmrsSymSet);
re_per_prb = re_per_prb_total - re_per_prb_dmrs;
re_per_prb = max(re_per_prb, 0);
end

function re_dmrs = nr_dmrs_re_per_prb(dmrs)
% 计算每个PRB内每个DMRS符号占用的RE数
if dmrs.DMRSConfigurationType == 1
    % Type1: 每CDM组6个RE，共NumCDMGroupsWithoutData组
    re_dmrs = 6 * dmrs.NumCDMGroupsWithoutData;
else
    % Type2: 每CDM组4个RE
    re_dmrs = 4 * dmrs.NumCDMGroupsWithoutData;
end
end

function re_ptrs = nr_ptrs_re_per_prb(ptrs, nPtrsSym)
% 计算每个PRB内每个PTRS符号占用的RE数（通常2个RE）
if ~isfield(ptrs, 'enable') || strcmpi(ptrs.enable, 'NO') || nPtrsSym == 0
    re_ptrs = 0;
    return;
end
re_ptrs = 2 * nPtrsSym;   % PTRS在每个PRB内占用2个子载波
end
