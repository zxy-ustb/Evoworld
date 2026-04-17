%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 文件名: pdsch_process_nr.m
% 函数功能描述:
%   针对每个 UE 的 NR PDSCH 处理流程：从传输块比特到 NR 资源网格映射。
%   本函数在可能的情况下复用 LTE 遗留模块：
%   - source_bit_gen.m（可选，当存在传统 pdsch 字段时使用）
%   - BC_modulation_process.m
%   并使用 NR 适配器替换 LTE 特有的资源逻辑：
%   - nr_phy_adapter('pdsch_indices'/'pdsch_dmrs'/'tbs')
%
% 输入参数:
%   n_cell      : cell_para 中的小区索引
%   n_user      : user_para 中的用户索引
%   n_frame     : 帧号
%   n_slot      : 帧内的时隙号
%   carrier     : NR 载波结构体（包含 NSizeGrid, NCellID, SymbolsPerSlot, NTxAnts 等字段）
%   txGridIn    : 输入资源网格，维度 [12*NSizeGrid, SymbolsPerSlot, NTxAnts]
%
% 输出参数:
%   txGridOut   : 添加完当前 UE 的 PDSCH/DMRS 后的输出资源网格
%   ueInfo      : 运行时信息汇总，用于调试/集成
%
% 调用示例:
%   [txGrid, info] = pdsch_process_nr(n_cell,n_user,n_frame,n_slot,carrier,txGrid);
%
% 详细功能说明:
%   1. 检查输入参数的有效性，判断当前 UE 是否激活了 PDSCH。
%   2. 根据用户参数构建 NR PDSCH 配置（调制方式、层数、PRB 集合、符号分配、DMRS 等）。
%   3. 调用 nr_phy_adapter('pdsch_indices') 计算 PDSCH 资源索引和可用 RE 总数 G。
%   4. 基于调制方式、层数、PRB 数、每 PRB 的 NRE、目标码率和 XOverhead 计算传输块大小 TBS。
%   5. 准备 HARQ 进程 ID 和冗余版本；生成传输块比特（可来自外部源、传统 source_bit_gen 或随机种子）。
%   6. 对传输块进行速率匹配，使其正好填充分配的 G 个比特。
%   7. 使用 BC_modulation_process（LTE 遗留模块）对编码比特进行调制，得到复数 PDSCH 符号。
%   8. 通过 nr_phy_adapter('pdsch_dmrs') 生成 DMRS 符号和对应的索引。
%   9. 若配置了 data_power_db，则对 PDSCH 符号进行功率缩放。
%   10. 将 PDSCH 和 DMRS 符号映射到输入资源网格 txGridIn 上。
%   11. 更新 user_para 中的运行时字段以及可选的 user_data 调试缓存。
%   12. 返回更新后的网格和信息结构体。
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [txGridOut, ueInfo] = pdsch_process_nr(n_cell, n_user, n_frame, n_slot, carrier, txGridIn)
% 声明全局变量（通常包含 cell_para, user_para, user_data 等）
globals_declare;

% 初始化输出网格为输入网格（后续将叠加当前 UE 的信号）
txGridOut = txGridIn;
% 初始化 UE 信息结构体，包含活跃标志、原因、传输块大小等字段
ueInfo = struct('active', false, ...
                'reason', '', ...
                'transportBlockSize', 0, ...
                'HARQProcessID', [], ...
                'RedundancyVersion', [], ...
                'G', 0, ...
                'modulationSource', '', ...
                'pdschIndicesCount', 0, ...
                'dmrsIndicesCount', 0);

% -------------------- 基本检查 --------------------
% 检查小区索引和用户索引是否越界，或者用户配置为空
if n_cell > size(user_para, 1) || n_user > size(user_para, 2) || isempty(user_para{n_cell, n_user})
    ueInfo.reason = 'user_not_found';   % 用户不存在
    return;
end
% 检查用户配置中是否包含 nr 结构和 pdsch 字段
if ~isfield(user_para{n_cell, n_user}, 'nr') || ~isfield(user_para{n_cell, n_user}.nr, 'pdsch')
    ueInfo.reason = 'nr_pdsch_not_configured';   % 未配置 NR PDSCH
    return;
end

% 获取当前用户的配置和 PDSCH 配置
ueCfg = user_para{n_cell, n_user};
pdschCfg = ueCfg.nr.pdsch;

% 检查运行时激活标志：必须存在 runtime.active 且为 1 才处理
if ~isfield(pdschCfg, 'runtime') || isempty(pdschCfg.runtime) || ...
   ~isfield(pdschCfg.runtime, 'active') || pdschCfg.runtime.active == 0
    ueInfo.reason = 'pdsch_not_active';
    return;
end

% -------------------- 构建 NR PDSCH 配置结构体 --------------------
pdschNR = local_build_pdsch_config(pdschCfg, carrier);

% 调用 NR 适配器获取 PDSCH 资源索引以及相关信息（如 G、NREPerPRB 等）
[pdschIndices, pdschIndicesInfo] = nr_phy_adapter('pdsch_indices', carrier, pdschNR);
% 若未获取到有效索引，则退出
if isempty(pdschIndices)
    ueInfo.reason = 'empty_pdsch_indices';
    return;
end

% 获取目标码率（默认为 0.5）
targetCodeRate = local_get_field(pdschCfg, 'TargetCodeRate', 0.5);
% 获取额外的开销（XOverhead），用于 TBS 计算
xOverhead = local_get_field(pdschCfg, 'XOverhead', 0);
% 调用 NR 适配器计算传输块大小 TBS（单位：比特）
tbs = nr_phy_adapter('tbs', pdschNR.Modulation, pdschNR.NumLayers, ...
    numel(pdschNR.PRBSet), pdschIndicesInfo.NREPerPRB, targetCodeRate, xOverhead);
% 确保 TBS 为非负数
tbs = max(0, floor(double(tbs)));

% -------------------- 准备 HARQ 信息和传输块比特 --------------------
[harqInfo, transportBlock] = local_prepare_harq_and_tb(n_cell, n_user, pdschCfg, tbs, n_frame, n_slot);
% 对传输块进行速率匹配，得到长度为 G 的编码比特序列
codedBits = local_rate_match_bits(transportBlock, pdschIndicesInfo.G);

% -------------------- 生成 PDSCH 调制符号和 DMRS --------------------
% 根据调制方式、编码比特和符号总数生成复数 PDSCH 符号
[pdschSymbols, modulationSource] = local_generate_pdsch_symbols(pdschNR.Modulation, codedBits, numel(pdschIndices));
% 调用 NR 适配器生成 DMRS 的索引和符号
[dmrsIndices, dmrsSymbols] = nr_phy_adapter('pdsch_dmrs', carrier, pdschNR);

% -------------------- 可选功率偏移 --------------------
dataScale = 1.0;   % 默认缩放因子为 1
% 若配置了 data_power_db（单位 dB），则转换为线性幅度缩放因子
if isfield(pdschCfg, 'data_power_db') && ~isempty(pdschCfg.data_power_db)
    dataScale = 10^(double(pdschCfg.data_power_db) / 20);
end
% 对 PDSCH 符号应用功率缩放
pdschSymbols = pdschSymbols * dataScale;

% -------------------- 将 PDSCH 和 DMRS 映射到资源网格 --------------------
% 将 PDSCH 符号叠加到网格的对应位置（支持多天线端口）
txGridOut(pdschIndices) = txGridOut(pdschIndices) + pdschSymbols;
% 若 DMRS 索引非空，则将 DMRS 符号也叠加到网格中
if ~isempty(dmrsIndices)
    txGridOut(dmrsIndices) = txGridOut(dmrsIndices) + dmrsSymbols;
end

% -------------------- 写回运行时信息至全局 user_para --------------------
user_para{n_cell, n_user}.nr.pdsch.runtime.transportBlock = transportBlock;
user_para{n_cell, n_user}.nr.pdsch.runtime.transportBlockSize = tbs;
user_para{n_cell, n_user}.nr.pdsch.runtime.HARQProcessID = harqInfo.HARQProcessID;
user_para{n_cell, n_user}.nr.pdsch.runtime.RedundancyVersion = harqInfo.RedundancyVersion;
user_para{n_cell, n_user}.nr.pdsch.runtime.pdschIndicesInfo = pdschIndicesInfo;
user_para{n_cell, n_user}.nr.pdsch.runtime.modulationSource = modulationSource;

% 可选的遗留调试缓存：若 user_data 存在且维度匹配，则保存中间比特和符号
if exist('user_data', 'var') && ~isempty(user_data) && ...
        n_cell <= size(user_data, 1) && n_user <= size(user_data, 2)
    user_data{n_cell, n_user}.trans_source_bits_nr = transportBlock(:).';
    user_data{n_cell, n_user}.trans_raw_bits_nr = codedBits(:).';
    user_data{n_cell, n_user}.modulated_symbols_nr = pdschSymbols(:).';
end

% 填充输出信息结构体
ueInfo.active = true;
ueInfo.reason = 'ok';
ueInfo.transportBlockSize = tbs;
ueInfo.HARQProcessID = harqInfo.HARQProcessID;
ueInfo.RedundancyVersion = harqInfo.RedundancyVersion;
ueInfo.G = pdschIndicesInfo.G;
ueInfo.modulationSource = modulationSource;
ueInfo.pdschIndicesCount = numel(pdschIndices);
ueInfo.dmrsIndicesCount = numel(dmrsIndices);
end

%% ======================= 局部辅助函数 =======================
% 功能：从用户配置和载波参数中构建 NR PDSCH 配置结构体
function pdschNR = local_build_pdsch_config(cfg, carrier)
pdschNR = struct;
% 调制方式（默认 QPSK）
pdschNR.Modulation = local_get_field(cfg, 'Modulation', 'QPSK');
% 层数（默认 1）
pdschNR.NumLayers = local_get_field(cfg, 'NumLayers', 1);
% 映射类型（默认 'A'，时隙内连续符号映射）
pdschNR.MappingType = local_get_field(cfg, 'MappingType', 'A');
% 小区 ID（默认 0）
pdschNR.NID = local_get_field(cfg, 'NID', 0);
% RNTI（默认 1）
pdschNR.RNTI = local_get_field(cfg, 'RNTI', 1);

rt = local_get_field(cfg, 'runtime', struct);
% 优先使用运行时指定的 PRB 集合，否则使用配置中的 PRBSet 或全部 PRB
if isfield(rt, 'PRBSet') && ~isempty(rt.PRBSet)
    pdschNR.PRBSet = rt.PRBSet(:).';
else
    pdschNR.PRBSet = local_get_field(cfg, 'PRBSet', 0:(carrier.NSizeGrid-1));
end
pdschNR.PRBSet = unique(pdschNR.PRBSet);   % 去重并保持行向量

% 符号分配：优先使用运行时指定的连续符号集合，否则使用配置中的 SymbolAllocation
if isfield(rt, 'SymbolSet') && ~isempty(rt.SymbolSet)
    symSet = rt.SymbolSet(:).';
    % 要求运行时 SymbolSet 必须是连续整数序列
    if ~isequal(symSet, symSet(1):symSet(end))
        error('pdsch_process_nr: runtime.SymbolSet must be contiguous.');
    end
    pdschNR.SymbolAllocation = [symSet(1), numel(symSet)];
else
    pdschNR.SymbolAllocation = local_get_field(cfg, 'SymbolAllocation', [2 10]);
end

% DMRS 配置
pdschNR.DMRS = local_get_field(cfg, 'dmrs', struct);
% PTRS 配置（如果存在）
if isfield(cfg, 'ptrs')
    pdschNR.PTRS = cfg.ptrs;
end
end

% 功能：准备 HARQ 相关信息并生成传输块比特
function [harqInfo, transportBlock] = local_prepare_harq_and_tb(n_cell, n_user, pdschCfg, tbs, n_frame, n_slot)
globals_declare
harqInfo = struct;
numHarqProc = 16;               % 默认 HARQ 进程数
rvSeq = [0 2 3 1];              % 默认冗余版本序列

% 若用户配置了 NR HARQ 参数，则覆盖默认值
if isfield(user_para{n_cell, n_user}.nr, 'harq')
    harqCfg = user_para{n_cell, n_user}.nr.harq;
    if isfield(harqCfg, 'num_process') && ~isempty(harqCfg.num_process)
        numHarqProc = max(1, double(harqCfg.num_process));
    end
    if isfield(harqCfg, 'rv_sequence') && ~isempty(harqCfg.rv_sequence)
        rvSeq = double(harqCfg.rv_sequence(:).');
    end
end
% 若 PDSCH 配置中直接指定了 RV 序列，则优先使用
if isfield(pdschCfg, 'RVSequence') && ~isempty(pdschCfg.RVSequence)
    rvSeq = double(pdschCfg.RVSequence(:).');
end
if isempty(rvSeq)
    rvSeq = [0 2 3 1];
end

% HARQ 进程 ID 由时隙号对进程数取模得到
harqInfo.HARQProcessID = mod(n_slot, numHarqProc);
% 冗余版本根据时隙号的变化循环选择
harqInfo.RedundancyVersion = rvSeq(mod(floor(n_slot / numHarqProc), numel(rvSeq)) + 1);
harqInfo.NewData = true;   % 本实现假设总是新数据（未实现重传合并）

% 生成传输块比特
transportBlock = local_generate_bits(n_cell, n_user, tbs, n_frame, n_slot);
end

% 功能：生成指定长度的传输块比特序列
function bits = local_generate_bits(n_cell, n_user, tbs, n_frame, n_slot)
globals_declare
bits = zeros(max(0, tbs), 1);
if tbs <= 0
    return;
end

% 1) 优先使用外部源（遗留兼容模式）：检查 cell_para 中的外部源标志和 user_data 中的比特
if n_cell <= size(cell_para, 2) && ~isempty(cell_para{1, n_cell}) && ...
        isfield(cell_para{1, n_cell}, 'pdsch') && ...
        isfield(cell_para{1, n_cell}.pdsch, 'isExternalSource') && ...
        cell_para{1, n_cell}.pdsch.isExternalSource && ...
        n_cell <= size(user_data, 1) && n_user <= size(user_data, 2) && ...
        ~isempty(user_data{n_cell, n_user}) && ...
        isfield(user_data{n_cell, n_user}, 'trans_source_bits')
    ext = user_data{n_cell, n_user}.trans_source_bits;
    if iscell(ext) && ~isempty(ext)
        % 速率匹配到目标长度 tbs
        bits = local_rate_match_bits(ext{1}(:), tbs);
        return;
    end
end

% 2) 尝试使用传统的 LTE source_bit_gen（如果存在传统 pdsch 字段）
if isfield(user_para{n_cell, n_user}, 'pdsch') && ~isempty(user_para{n_cell, n_user}.pdsch)
    legacyPdsch = user_para{n_cell, n_user}.pdsch;
    % 检查是否存在必要字段 'CM' 和 'TBS_control'
    req = {'CM','TBS_control'};
    ok = true;
    for i = 1:numel(req)
        ok = ok && isfield(legacyPdsch, req{i});
    end
    if ok
        try
            cw_source_size = tbs;
            cw_rawbits_size = tbs;
            [src, legacyPdsch] = source_bit_gen(legacyPdsch, 1, cw_source_size, cw_rawbits_size);
            user_para{n_cell, n_user}.pdsch = legacyPdsch;   % 回写可能更新的配置
            bits = local_rate_match_bits(src(:), tbs);
            return;
        catch
            % 失败则回退到确定性随机比特
        end
    end
end

% 3) 确定性随机比特生成（基于种子，保证可重复）
seed = 30000 + 97 * n_cell + 193 * n_user + 31 * n_frame + n_slot;
s = RandStream('mt19937ar', 'Seed', seed);
bits = randi(s, [0 1], tbs, 1);
end

% 功能：将编码比特调制为复数符号，长度适配到 expectedLen
function [symbols, sourceTag] = local_generate_pdsch_symbols(modName, codedBits, expectedLen)
sourceTag = 'LTE_BC';           % 标记调制来源为 LTE BC 模块
modName = upper(char(modName));
% 若调制方式为 256QAM，回退到 64QAM（因为 BC_modulation_process 不支持 256QAM）
if strcmp(modName, '256QAM')
    modName = '64QAM';
    sourceTag = 'LTE_BC_FALLBACK_64QAM';
end
% 仅支持 BPSK/QPSK/16QAM/64QAM，否则回退到 QPSK
if ~any(strcmp(modName, {'BPSK','QPSK','16QAM','64QAM'}))
    modName = 'QPSK';
    sourceTag = 'LTE_BC_FALLBACK_QPSK';
end

% 将比特序列转换为行向量放入 cell 中，适配 BC_modulation_process 接口
bitsCell = {reshape(double(codedBits), 1, [])};
modeCell = {modName};
% 调用 LTE 遗留的调制模块
symCell = BC_modulation_process(bitsCell, modeCell);
symbols = symCell{1}(:);        % 取出复数符号并转为列向量
% 将符号序列长度调整为期望的 expectedLen（通过截断或重复）
symbols = local_resize_symbols(symbols, expectedLen);
end

% 功能：对输入比特序列进行速率匹配，输出固定长度 targetLen 的比特序列
function bitsOut = local_rate_match_bits(bitsIn, targetLen)
bitsIn = bitsIn(:);              % 转为列向量
if targetLen <= 0
    bitsOut = zeros(0, 1);
    return;
end
if isempty(bitsIn)
    bitsOut = zeros(targetLen, 1);
    return;
end
if numel(bitsIn) >= targetLen
    % 直接截取前 targetLen 个比特
    bitsOut = bitsIn(1:targetLen);
else
    % 重复整个序列直到达到或超过目标长度，然后截断
    rep = ceil(targetLen / numel(bitsIn));
    bitsOut = repmat(bitsIn, rep, 1);
    bitsOut = bitsOut(1:targetLen);
end
% 确保输出为 0/1 双精度值
bitsOut = double(bitsOut ~= 0);
end

% 功能：调整符号序列长度到 targetLen（截断或重复）
function symsOut = local_resize_symbols(symsIn, targetLen)
symsIn = symsIn(:);
if targetLen <= 0
    symsOut = complex(zeros(0, 1));
    return;
end
if isempty(symsIn)
    symsOut = complex(zeros(targetLen, 1));
    return;
end
if numel(symsIn) >= targetLen
    symsOut = symsIn(1:targetLen);
else
    rep = ceil(targetLen / numel(symsIn));
    symsOut = repmat(symsIn, rep, 1);
    symsOut = symsOut(1:targetLen);
end
end

% 功能：从结构体中安全获取字段值，若不存在或为空则返回默认值
function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end