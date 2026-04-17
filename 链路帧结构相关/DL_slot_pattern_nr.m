function slot_pattern = DL_slot_pattern_nr(N_ID_CELL,n_slot)
% DL_slot_pattern_nr - 生成当前时隙的资源网格占位图（用于调试和可视化）
%
% 功能描述：
%   本函数根据小区配置和用户运行时信息，生成一个二维数值矩阵 slot_pattern，
%   其维度为 [子载波数 × OFDM符号数]，每个元素用不同的数值标记该资源单元（RE）
%   被何种信道/信号占用。主要用于调试、可视化或资源分配验证，不用于实际信号生成。
%
% 关键修正说明：
%   1) 明确定义控制区标记 99，避免 DL_CONTROL_FLAG 未定义；
%   2) 使用 runtime 中已算好的 slot/symbol 结果；
%   3) 面向 active BWP 生成图样。
%
% 输入参数：
%   N_ID_CELL : 小区标识符
%   n_slot    : 当前时隙号
% 输出参数：
%   slot_pattern : 二维数值矩阵，尺寸 [N_subcarriers, N_symbols_per_slot]

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量：cell_para, user_para, sim_para等

% 显式定义控制区域标记值（PDCCH/CORESET 占用标记为 99）
DL_CONTROL_FLAG = 99;

% ========================== 1. 获取小区索引与配置检查 ==========================
% 根据小区ID获取小区索引
n_cell = getCellIndexfromID(N_ID_CELL);
if isempty(n_cell)   % 小区不存在则报错
    error('DL_slot_pattern_nr: invalid N_ID_CELL.');
end

% 获取小区配置结构体
cellCfg = cell_para{1,n_cell};
% 检查小区是否配置了NR参数
if ~isfield(cellCfg,'nr') || isempty(cellCfg.nr)
    error('DL_slot_pattern_nr: cell_para{%d}.nr is missing.', n_cell);
end

% 提取NR配置结构体
nr = cellCfg.nr;
% 检查运行时信息是否存在，且当前时隙号匹配
if ~isfield(nr,'runtime') || isempty(nr.runtime) || ...
   ~isfield(nr.runtime,'current_slot') || isempty(nr.runtime.current_slot) || ...
   nr.runtime.current_slot ~= n_slot
    error('DL_slot_pattern_nr: please call sim_config_compute_nr(n_frame,n_slot) first.');
end

% ========================== 2. 确定子载波数和符号数 ==========================
% 优先使用 active BWP 的带宽来确定子载波总数
if isfield(nr,'active_bwp') && isfield(nr.active_bwp,'NSizeBWP') && ~isempty(nr.active_bwp.NSizeBWP)
    Nsc = 12 * nr.active_bwp.NSizeBWP;   % 子载波数 = 12 × RB数
% 否则使用小区网格中的子载波数
elseif isfield(nr,'grid') && isfield(nr.grid,'NSubcarriers')
    Nsc = nr.grid.NSubcarriers;
else
    error('DL_slot_pattern_nr: cannot determine number of subcarriers.');
end
% 每时隙OFDM符号数（从NR配置中获取，通常为14）
Nsym = nr.symbols_per_slot;
% 初始化占位图矩阵为全零
slot_pattern = zeros(Nsc,Nsym);

%% ========================== 3. SSB 图样标记 ==========================
% 检查SSB是否激活（由运行时决定）
if isfield(nr,'ssb') && isfield(nr.ssb,'runtime') && isfield(nr.ssb.runtime,'active') ...
        && nr.ssb.runtime.active == 1
    ssbSC = 240;   % SSB固定占用20个RB = 240个子载波
    % 确保带宽足够容纳SSB
    if Nsc >= ssbSC
        % 将SSB置于频带中央（1-based索引）
        k0 = floor(Nsc/2) - floor(ssbSC/2) + 1;
        scSet = k0:(k0+ssbSC-1);   % SSB占用的子载波集合
        % 确定SSB占用的符号位置：优先使用运行时指定的符号集，否则使用配置层，默认前4个符号
        if isfield(nr.ssb.runtime,'SymbolSet') && ~isempty(nr.ssb.runtime.SymbolSet)
            symSet = nr.ssb.runtime.SymbolSet + 1;   % 转为1-based索引
        elseif isfield(nr.ssb,'symbols') && ~isempty(nr.ssb.symbols)
            symSet = nr.ssb.symbols + 1;
        else
            symSet = 1:4;   % 默认时隙前4个符号
        end
        symSet = symSet(symSet>=1 & symSet<=Nsym);   % 边界裁剪
        % 将SSB区域标记为5000
        slot_pattern(scSet,symSet) = 5000;
    end
end

%% ========================== 4. PDCCH / CORESET 图样标记 ==========================
% 检查PDCCH是否激活
if isfield(nr,'pdcch') && isfield(nr.pdcch,'runtime') && isfield(nr.pdcch.runtime,'active') ...
        && nr.pdcch.runtime.active == 1
    rbSet = nr.pdcch.runtime.RBSet;       % PDCCH占用的PRB集合（0-based）
    symSet = nr.pdcch.runtime.SymbolSet;  % PDCCH占用的符号集合（0-based）
    if ~isempty(rbSet) && ~isempty(symSet)
        scSet = local_prb_to_sc(rbSet,Nsc);   % 将PRB转换为子载波索引（1-based）
        symSet = symSet + 1;                   % 转为1-based符号索引
        symSet = symSet(symSet>=1 & symSet<=Nsym);
        if ~isempty(scSet) && ~isempty(symSet)
            slot_pattern(scSet,symSet) = DL_CONTROL_FLAG;   % 标记为99
        end
    end
end

%% ========================== 5. PDSCH / DMRS / PTRS 及 PUSCH DMRS 图样标记 ==========================
% 获取该小区下所有用户ID列表
userID_list = cellCfg.userID_list;
for iu = 1:length(userID_list)   % 遍历每个用户
    userID = userID_list(iu);
    [u_cell,u_user] = getUserIndexfromID(userID);
    % 跳过无效用户
    if isempty(u_cell) || isempty(u_user) || isempty(user_para{u_cell,u_user})
        continue;
    end
    ue = user_para{u_cell,u_user};
    if ~isfield(ue,'nr') || isempty(ue.nr)
        continue;
    end

    % ---------- 5.1 PDSCH 数据区域 ----------
    if isfield(ue.nr,'pdsch') && isfield(ue.nr.pdsch,'runtime') ...
            && isfield(ue.nr.pdsch.runtime,'active') && ue.nr.pdsch.runtime.active == 1
        prbSet = ue.nr.pdsch.runtime.PRBSet;          % PDSCH分配的PRB集合
        symSet = ue.nr.pdsch.runtime.SymbolSet;       % PDSCH占用的符号集合（0-based）
        dmrsSymSet = ue.nr.pdsch.runtime.DMRSSymbolSet; % DMRS占用的符号集合
        ptrsSymSet = ue.nr.pdsch.runtime.PTRSSymbolSet; % PTRS占用的符号集合
        scData = local_prb_to_sc(prbSet,Nsc);          % PDSCH数据子载波集合

        % 标记PDSCH数据RE（用用户ID作为标记值）
        if ~isempty(scData)
            for is = 1:length(symSet)
                s = symSet(is) + 1;   % 转为1-based符号索引
                if s>=1 && s<=Nsym
                    slot_pattern(scData,s) = userID;   % 写入用户ID
                end
            end
        end

        % ---------- 5.2 PDSCH DMRS ----------
        if isfield(ue.nr.pdsch,'dmrs') && ~isempty(ue.nr.pdsch.dmrs)
            scDmrs = local_pdsch_dmrs_sc(prbSet,ue.nr.pdsch.dmrs,Nsc); % DMRS子载波
            % 确定端口标记值：100 + 第一个端口号
            if isfield(ue.nr.pdsch.dmrs,'DMRSPortSet') && ~isempty(ue.nr.pdsch.dmrs.DMRSPortSet)
                portFlag = 100 + ue.nr.pdsch.dmrs.DMRSPortSet(1);
            else
                portFlag = 100;
            end
            for is = 1:length(dmrsSymSet)
                s = dmrsSymSet(is) + 1;
                if s>=1 && s<=Nsym && ~isempty(scDmrs)
                    slot_pattern(scDmrs,s) = portFlag;   % 标记为100+端口号
                end
            end
        end

        % ---------- 5.3 PDSCH PTRS ----------
        if isfield(ue.nr.pdsch,'ptrs') && ~isempty(ue.nr.pdsch.ptrs)
            scPtrs = local_pdsch_ptrs_sc(prbSet,ue.nr.pdsch.ptrs,Nsc); % PTRS子载波
            for is = 1:length(ptrsSymSet)
                s = ptrsSymSet(is) + 1;
                if s>=1 && s<=Nsym && ~isempty(scPtrs)
                    slot_pattern(scPtrs,s) = 3000;   % PTRS固定标记3000
                end
            end
        end
    end

    % ---------- 5.4 PUSCH DMRS（用于图样中展示上行参考信号）----------
    if isfield(ue.nr,'pusch') && isfield(ue.nr.pusch,'runtime') ...
            && isfield(ue.nr.pusch.runtime,'active') && ue.nr.pusch.runtime.active == 1
        prbSet = ue.nr.pusch.runtime.PRBSet;
        dmrsSymSet = ue.nr.pusch.runtime.DMRSSymbolSet;
        if isfield(ue.nr.pusch,'dmrs') && ~isempty(ue.nr.pusch.dmrs)
            scDmrs = local_pusch_dmrs_sc(prbSet,ue.nr.pusch.dmrs,Nsc);
            % 端口标记：200 + 端口号
            if isfield(ue.nr.pusch.dmrs,'DMRSPortSet') && ~isempty(ue.nr.pusch.dmrs.DMRSPortSet)
                if numel(ue.nr.pusch.dmrs.DMRSPortSet)==1
                    portFlag = 200 + ue.nr.pusch.dmrs.DMRSPortSet;
                else
                    portFlag = 200 + ue.nr.pusch.dmrs.DMRSPortSet(1);
                end
            else
                portFlag = 200;
            end
            for is = 1:length(dmrsSymSet)
                s = dmrsSymSet(is) + 1;
                if s>=1 && s<=Nsym && ~isempty(scDmrs)
                    slot_pattern(scDmrs,s) = portFlag;
                end
            end
        end
    end
end

%% ========================== 6. CSI-RS 图样标记（占位） ==========================
if isfield(nr,'csirs') && isfield(nr.csirs,'runtime') && isfield(nr.csirs.runtime,'active') ...
        && nr.csirs.runtime.active == 1
    prbSet = nr.csirs.runtime.PRBSet;
    symSet = nr.csirs.runtime.SymbolSet;
    if ~isempty(prbSet) && ~isempty(symSet)
        scSet = local_prb_to_sc(prbSet,Nsc);      % 所有子载波（实际CSI-RS可能稀疏）
        symSet = symSet + 1;                       % 转为1-based
        symSet = symSet(symSet>=1 & symSet<=Nsym);
        if ~isempty(scSet) && ~isempty(symSet)
            % 简化处理：仅在每个PRB的第一个子载波（索引1,13,...）上标记
            for is = 1:length(symSet)
                s = symSet(is);
                idx = scSet(1:12:end);   % 每12个取第一个（每个RB的第一个子载波）
                slot_pattern(idx,s) = 4000;   % CSI-RS固定标记4000
            end
        end
    end
end

% 将生成的图样存入小区运行时，便于外部访问
cell_para{1,n_cell}.nr.runtime.current_slot_pattern = slot_pattern;

end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function scSet = local_prb_to_sc(prbSet,Nsc)
% 将PRB索引集合转换为子载波索引集合（1-based）
% 输入：prbSet - PRB索引列向量或行向量（0-based）
%      Nsc    - 总子载波数
% 输出：scSet  - 所有对应的子载波索引（排序后，去除非法的）
if isempty(prbSet)
    scSet = [];
    return;
end
% 预分配最大可能长度
scSet = zeros(length(prbSet)*12,1);
ptr = 1;
for ip = 1:length(prbSet)
    base = prbSet(ip)*12;          % PRB起始子载波（0-based）
    cur = base + (1:12);           % 该PRB内的12个子载波（1-based）
    cur = cur(cur>=1 & cur<=Nsc);  % 边界裁剪
    ncur = length(cur);
    if ncur > 0
        scSet(ptr:ptr+ncur-1) = cur(:);
        ptr = ptr + ncur;
    end
end
scSet = scSet(1:ptr-1);            % 截断未使用的部分
end

function scDmrs = local_pdsch_dmrs_sc(prbSet,dmrsCfg,Nsc)
% 计算PDSCH DMRS占用的子载波索引（1-based）
% 根据DMRS配置类型（Type1或Type2）确定频域梳状位置
if isempty(prbSet)
    scDmrs = [];
    return;
end
% Type1: 每RB 6个DMRS子载波（索引1,3,5,7,9,11）
% Type2: 每RB 4个DMRS子载波（索引1,4,7,10）
if dmrsCfg.DMRSConfigurationType == 1
    comb = [1 3 5 7 9 11];
else
    comb = [1 4 7 10];
end
scDmrs = zeros(length(prbSet)*length(comb),1);
ptr = 1;
for ip = 1:length(prbSet)
    base = prbSet(ip)*12;
    cur = base + comb;
    cur = cur(cur>=1 & cur<=Nsc);
    ncur = length(cur);
    if ncur > 0
        scDmrs(ptr:ptr+ncur-1) = cur(:);
        ptr = ptr + ncur;
    end
end
scDmrs = scDmrs(1:ptr-1);
end

function scDmrs = local_pusch_dmrs_sc(prbSet,dmrsCfg,Nsc)
% 计算PUSCH DMRS占用的子载波索引（1-based）
% 逻辑与PDSCH DMRS相同，但分开以便区分
if isempty(prbSet)
    scDmrs = [];
    return;
end
if dmrsCfg.DMRSConfigurationType == 1
    comb = [1 3 5 7 9 11];
else
    comb = [1 4 7 10];
end
scDmrs = zeros(length(prbSet)*length(comb),1);
ptr = 1;
for ip = 1:length(prbSet)
    base = prbSet(ip)*12;
    cur = base + comb;
    cur = cur(cur>=1 & cur<=Nsc);
    ncur = length(cur);
    if ncur > 0
        scDmrs(ptr:ptr+ncur-1) = cur(:);
        ptr = ptr + ncur;
    end
end
scDmrs = scDmrs(1:ptr-1);
end

function scPtrs = local_pdsch_ptrs_sc(prbSet,ptrsCfg,Nsc)
% 计算PDSCH PTRS占用的子载波索引（1-based）
% PTRS仅在部分PRB上出现，频域密度 FrequencyDensity 决定间隔多少个PRB放置一个PTRS
if isempty(prbSet) || ~isfield(ptrsCfg,'enable') || strcmpi(ptrsCfg.enable,'NO')
    scPtrs = [];
    return;
end
% 频域密度：默认2，表示每2个PRB放置一个PTRS
if ~isfield(ptrsCfg,'FrequencyDensity') || isempty(ptrsCfg.FrequencyDensity)
    fden = 2;
else
    fden = max(1, ptrsCfg.FrequencyDensity);
end
% 选择放置PTRS的PRB：从第一个开始，每隔fden个PRB选一个
selPRB = prbSet(1:fden:end);
% 获取PTRS在PRB内的子载波偏移（取决于REOffset配置）
re0 = local_ptrs_re_index(ptrsCfg);
scPtrs = zeros(length(selPRB),1);
ptr = 1;
for k = 1:length(selPRB)
    cur = selPRB(k)*12 + re0;   % 绝对子载波索引（1-based）
    if cur>=1 && cur<=Nsc
        scPtrs(ptr) = cur;
        ptr = ptr + 1;
    end
end
scPtrs = scPtrs(1:ptr-1);
end

function re0 = local_ptrs_re_index(ptrsCfg)
% 根据PTRS的REOffset配置返回子载波偏移（0-based，相对于PRB起始）
% 对应38.214中PTRS频域偏移参数，影响PTRS在PRB内的位置
if ~isfield(ptrsCfg,'REOffset') || isempty(ptrsCfg.REOffset)
    reOff = '00';
else
    reOff = ptrsCfg.REOffset;
end
switch reOff
    case '00'
        re0 = 2;   % 子载波索引2（0-based），实际位置为第3个子载波
    case '01'
        re0 = 4;
    case '10'
        re0 = 6;
    case '11'
        re0 = 8;
    otherwise
        re0 = 2;
end
end