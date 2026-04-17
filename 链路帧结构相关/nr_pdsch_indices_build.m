function [pdschIndices, info] = nr_pdsch_indices_build(carrier, pdsch)
%NR_PDSCH_INDICES_BUILD Build NR PDSCH RE indices without 5G Toolbox.
%   该函数手动构建 NR PDSCH 的资源单元（RE）线性索引，不依赖 MATLAB 5G Toolbox。
%   它复用了与本地 NR 图样辅助函数中相同的 PRB/DMRS/PTRS 放置逻辑。
%
%   输入：
%       carrier - 载波配置结构体，需包含 NSizeGrid（RB 数）、SymbolsPerSlot（可选）、NTxAnts（可选）等。
%       pdsch   - PDSCH 配置结构体，需包含 SymbolAllocation、NumLayers（可选）、PRBSet（可选）、
%                 Modulation（可选）、DMRS（可选）、PTRS（可选）等字段。
%   输出：
%       pdschIndices - 所有 PDSCH 数据 RE 的线性索引（列向量），适用于维度为 [K, L, Nt] 的资源网格。
%       info         - 结构体，包含 NREPerPRB（每 PRB 平均数据 RE 数）、G（总编码比特数）、
%                      SymbolSet（PDSCH 符号集）、DMRSSymbolSet（DMRS 符号集）、PTRSSymbolSet（PTRS 符号集）。

% ========================== 主函数体 ==========================
% 计算总子载波数 K = 12 * RB 总数
K = 12 * carrier.NSizeGrid;
% 获取每个时隙的 OFDM 符号数 L（默认为 14）
L = local_symbols_per_slot(carrier);
% 获取传输层数（默认为 1）
numLayers = max(1, local_get_field(pdsch, 'NumLayers', 1));
% 确定资源网格的天线平面数：取层数与发射天线数中的较大值（保证索引不越界）
numPlanes = max(numLayers, local_get_field(carrier, 'NTxAnts', numLayers));
% 获取 PDSCH 分配的 PRB 集合（0‑based，唯一且按行排列）
prbSet = local_prb_set(pdsch, carrier);
% 获取 PDSCH 占用的 OFDM 符号集（0‑based）
symSet = local_symbol_set(pdsch);
% 获取 DMRS 占用的符号集（基于 PDSCH 符号分配和 DMRS 配置）
dmrsSymSet = local_pdsch_dmrs_symbols(pdsch.SymbolAllocation, local_get_field(pdsch, 'DMRS', struct));
% 获取 PTRS 配置（若不存在则为空结构体）
ptrsCfg = local_get_field(pdsch, 'PTRS', struct);
% 判断 PTRS 是否使能
ptrsEnabled = local_ptrs_enabled(pdsch, ptrsCfg);
% 获取 PTRS 占用的符号集（基于时域密度，且避开 DMRS）
ptrsSymSet = local_ptrs_symbols(pdsch.SymbolAllocation, dmrsSymSet, ptrsCfg);

% 累计每个 PRB 中实际用于 PDSCH 数据的 RE 数量（用于计算平均值）
dataReCountPerPrb = 0;
% 预分配索引数组（最大可能数量：PRB 数 × 符号数 × 每 PRB 子载波数 12 × 层数）
allIdx = zeros(max(1, numel(prbSet) * numel(symSet) * 12 * numLayers), 1);
ptr = 1;   % 当前填充位置的指针

% 三层循环：PRB → OFDM 符号 → 层
for ip = 1:numel(prbSet)
    prb = prbSet(ip);
    baseSc = prb * 12;   % 该 PRB 的起始子载波绝对索引（0‑based）
    for is = 1:numel(symSet)
        sym0 = symSet(is);         % 当前符号索引（0‑based）
        scLocal = 1:12;            % 初始认为该 PRB 内所有子载波都可用（1‑based 本地索引）

        % 如果当前符号是 DMRS 符号，则从子载波集合中移除 DMRS 占用的子载波
        if any(dmrsSymSet == sym0)
            dmrsCfg = local_get_field(pdsch, 'DMRS', struct);
            dmrsComb = local_dmrs_comb(dmrsCfg);   % DMRS 频域梳齿（1‑based，PRB 内）
            scLocal = setdiff(scLocal, dmrsComb);
        end

        % 如果 PTRS 使能且当前符号是 PTRS 符号，则移除 PTRS 占用的子载波
        if ptrsEnabled && any(ptrsSymSet == sym0)
            ptrsRe = local_ptrs_re_index(ptrsCfg);   % PTRS 占用的子载波索引（1‑based）
            scLocal = setdiff(scLocal, ptrsRe);
        end

        % 更新累计数据 RE 计数（每个 PRB 中该符号上的数据子载波数）
        dataReCountPerPrb = dataReCountPerPrb + numel(scLocal);

        % 将本地子载波索引转换为绝对子载波索引（1‑based，用于 sub2ind）
        scAbs = baseSc + scLocal;
        sym1 = sym0 + 1;   % 转换为 1‑based 符号索引

        % 对每一层生成索引
        for il = 1:numLayers
            plane = min(il, numPlanes);   % 天线平面索引（1‑based）
            n = numel(scAbs);
            if n == 0
                continue;
            end
            % 使用 sub2ind 将 (子载波, 符号, 天线平面) 转换为线性索引
            allIdx(ptr:ptr+n-1) = sub2ind([K, L, numPlanes], scAbs(:), sym1 * ones(n,1), plane * ones(n,1));
            ptr = ptr + n;
        end
    end
end

% 截取实际使用的部分（去除预分配中未填充的尾部）
pdschIndices = allIdx(1:ptr-1);

% 构建信息输出结构体
info = struct;
if isempty(prbSet)
    info.NREPerPRB = 0;   % 若无 PRB 分配，则每 PRB 数据 RE 数为 0
else
    info.NREPerPRB = dataReCountPerPrb / numel(prbSet);   % 平均每个 PRB 的数据 RE 数
end
% 总编码比特数 G = 数据 RE 总数 × 调制阶数
info.G = numel(pdschIndices) * local_mod_order(local_get_field(pdsch, 'Modulation', 'QPSK'));
info.SymbolSet = symSet;                % PDSCH 占用的符号集（0‑based）
info.DMRSSymbolSet = dmrsSymSet;        % DMRS 占用的符号集
info.PTRSSymbolSet = ptrsSymSet;        % PTRS 占用的符号集

end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function value = local_get_field(s, name, defaultValue)
% 安全地从结构体中获取字段值，若字段不存在或为空则返回默认值
% 输入：s - 结构体，name - 字段名，defaultValue - 默认值
% 输出：字段值或默认值
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function L = local_symbols_per_slot(carrier)
% 获取每个时隙的 OFDM 符号数
% 优先使用 carrier.SymbolsPerSlot，其次 carrier.NSymbols，否则默认 14
if isfield(carrier, 'SymbolsPerSlot') && ~isempty(carrier.SymbolsPerSlot)
    L = carrier.SymbolsPerSlot;
elseif isfield(carrier, 'NSymbols') && ~isempty(carrier.NSymbols)
    L = carrier.NSymbols;
else
    L = 14;   % NR 常规 CP 下每时隙固定 14 个符号
end
end

function prbSet = local_prb_set(cfg, carrier)
% 获取 PDSCH 分配的 PRB 集合（0‑based，行向量，唯一）
% 若配置中未指定 PRBSet，则默认使用整个载波带宽的所有 PRB
prbSet = local_get_field(cfg, 'PRBSet', []);
if isempty(prbSet)
    prbSet = 0:(carrier.NSizeGrid-1);
end
prbSet = unique(prbSet(:).');   % 确保为一维行向量且无重复
end

function symSet = local_symbol_set(cfg)
% 根据 SymbolAllocation 获取 PDSCH 占用的符号索引（0‑based，连续）
% SymbolAllocation 格式为 [起始符号, 符号长度]
symAlloc = cfg.SymbolAllocation;
symSet = symAlloc(1):(symAlloc(1)+symAlloc(2)-1);
end

function comb = local_dmrs_comb(dmrsCfg)
% 根据 DMRS 配置类型返回频域梳齿子载波索引（1‑based，PRB 内）
% Type1: 每 PRB 6 个 DMRS 子载波（1,3,5,7,9,11）
% Type2: 每 PRB 4 个 DMRS 子载波（1,4,7,10）
if local_get_field(dmrsCfg, 'DMRSConfigurationType', 1) == 1
    comb = [1 3 5 7 9 11];
else
    comb = [1 4 7 10];
end
end

function enabled = local_ptrs_enabled(cfg, ptrsCfg)
% 判断 PTRS 是否使能
% 优先检查 cfg.EnablePTRS（逻辑值），否则检查 ptrsCfg.enable 字符串是否等于 'YES'
enabled = false;
if isfield(cfg, 'EnablePTRS') && ~isempty(cfg.EnablePTRS)
    enabled = logical(cfg.EnablePTRS);
elseif isfield(ptrsCfg, 'enable') && ischar(ptrsCfg.enable)
    enabled = strcmpi(ptrsCfg.enable, 'YES');
end
end

function dmrsSym = local_pdsch_dmrs_symbols(symAlloc, dmrs)
% 计算 PDSCH DMRS 占用的符号位置（0‑based 索引）
% 输入：symAlloc - [起始符号, 符号长度]，dmrs - DMRS 配置结构体
% 输出：dmrsSym - DMRS 符号索引数组
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);   % PDSCH 占用的所有符号

% 若 DMRS 被禁用，返回空
if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrsSym = [];
    return;
end

% TypeA DMRS 起始符号（若未配置，默认为 PDSCH 起始符号）
l0 = local_get_field(dmrs, 'DMRSTypeAPosition', startSym);
% 根据附加位置确定候选 DMRS 符号
switch local_get_field(dmrs, 'DMRSAdditionalPosition', 0)
    case 0
        cand = [l0];
    case 1
        cand = [l0 l0+4];
    case 2
        cand = [l0 l0+4 l0+7];
    otherwise
        cand = [l0 l0+3 l0+6 l0+9];
end
% 只保留落在 PDSCH 符号内的候选
dmrsSym = cand(ismember(cand, dataSymSet));
% 如果是双符号 DMRS，每个位置扩展为连续两个符号
if local_get_field(dmrs, 'DMRSLength', 1) == 2
    dmrsSym = unique([dmrsSym dmrsSym+1]);
    dmrsSym = dmrsSym(ismember(dmrsSym, dataSymSet));
end
end

function ptrsSym = local_ptrs_symbols(symAlloc, dmrsSym, ptrs)
% 计算 PTRS 占用的符号位置（0‑based 索引）
% 输入：symAlloc - [起始符号, 符号长度]，dmrsSym - DMRS 符号集，ptrs - PTRS 配置
% 输出：ptrsSym - PTRS 符号索引数组
if ~isfield(ptrs, 'enable') || strcmpi(ptrs.enable, 'NO')
    ptrsSym = [];   % PTRS 未使能
    return;
end
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);
% 时域密度（至少为 1）
timeDensity = max(1, local_get_field(ptrs, 'TimeDensity', 2));
% PTRS 从 startSym+1 开始，每隔 timeDensity 个符号放置一个
cand = startSym+1 : timeDensity : (startSym+nSym-1);
% 不能与 DMRS 符号重叠
cand = setdiff(cand, dmrsSym);
% 只保留落在 PDSCH 符号内的候选
ptrsSym = cand(ismember(cand, dataSymSet));
end

function re0 = local_ptrs_re_index(ptrsCfg)
% 获取 PTRS 在 PRB 内的子载波偏移（1‑based 索引）
% 根据 REOffset 配置决定，默认 '00' 对应索引 2
reOff = local_get_field(ptrsCfg, 'REOffset', '00');
switch reOff
    case '00'
        re0 = 2;
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

function Qm = local_mod_order(modName)
% 根据调制方式字符串返回调制阶数 Qm
% 输入：modName - 字符串，如 'QPSK', '16QAM' 等
% 输出：Qm - 每个符号承载的比特数
if isstring(modName)
    modName = char(modName);   % 将字符串标量转换为字符数组
end
switch upper(modName)
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
        Qm = 2;   % 默认 QPSK
end
end