%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 文件名: pusch_process_nr.m
% 函数功能描述:
%   针对每个 UE 的 NR PUSCH 处理流程：从传输块比特到 NR 资源网格映射。
%   在可能的情况下复用 LTE 遗留模块：
%   - source_bit_gen.m（可选的回退路径）
%   - BC_modulation_process.m
%   并使用 NR 适配器处理 NR 特有的资源逻辑：
%   - nr_phy_adapter('pusch_indices'/'pusch_dmrs'/'tbs')
%
% 输入参数:
%   n_cell      : cell_para 中的小区索引
%   n_user      : user_para 中的用户索引
%   n_frame     : 帧号
%   n_slot      : 时隙号
%   carrier     : NR 载波结构体（包含 NSizeGrid, NCellID, SymbolsPerSlot, NTxAnts 等）
%   txGridIn    : 输入资源网格，维度 [12*NSizeGrid, SymbolsPerSlot, NTxAnts]
%   puschPrbSet : 可选参数，冲突解决后的有效 PRB 集合（若提供则覆盖配置中的 PRBSet）
%
% 输出参数:
%   txGridOut   : 添加完当前 UE 的 PUSCH/DMRS 后的输出资源网格
%   ueInfo      : 运行时信息汇总，用于调试/集成
%
% 调用示例:
%   [txGrid, info] = pusch_process_nr(n_cell, n_user, n_frame, n_slot, carrier, txGrid, []);
%
% 详细功能说明:
%   1. 检查输入参数的有效性，判断当前 UE 是否激活了 PUSCH。
%   2. 根据用户参数和可选的 puschPrbSet 构建 NR PUSCH 配置。
%   3. 验证层数不超过发送天线数。
%   4. 调用 nr_phy_adapter('pusch_indices') 计算 PUSCH 资源索引和可用 RE 总数 G。
%   5. 基于调制方式、层数、PRB 数、每 PRB 的 NRE、目标码率和 XOverhead 计算 TBS。
%   6. 准备 HARQ 进程 ID 和冗余版本；生成传输块比特（来自传统 source_bit_gen 或随机种子）。
%   7. 对传输块进行速率匹配，得到长度为 G 的编码比特序列。
%   8. 使用 BC_modulation_process 对编码比特进行调制，得到复数 PUSCH 符号。
%   9. 通过 nr_phy_adapter('pusch_dmrs') 生成 DMRS 符号和对应的索引。
%   10. 将 PUSCH 和 DMRS 符号映射到输入资源网格 txGridIn 上。
%   11. 更新 user_para 中的运行时字段以及可选的 user_data 调试缓存。
%   12. 返回更新后的网格和信息结构体。
%
% 与 PDSCH 处理的主要区别:
%   - 使用 'pusch_indices' 和 'pusch_dmrs' 而非 'pdsch_*'
%   - 支持外部传入 puschPrbSet 用于冲突解决（如上行免调度冲突）
%   - 上行传输块生成优先使用用户参数中的 pusch 字段（而非 pdsch）
%   - 写入 user_data 的字段名带有 _ul 后缀以示区分
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [txGridOut, ueInfo] = pusch_process_nr(n_cell, n_user, n_frame, n_slot, carrier, txGridIn, puschPrbSet)
% 函数开始：输入小区索引、用户索引、帧号、时隙号、载波配置、输入网格、可选 PRB 集合
% 输出：更新后的网格和 UE 信息结构体

% 声明全局变量（通常包含 cell_para, user_para, user_data 等）
globals_declare;

% 若未提供 puschPrbSet 参数（输入参数少于 7 个），则初始化为空
if nargin < 7
    puschPrbSet = [];
end

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
                'puschIndicesCount', 0, ...
                'dmrsIndicesCount', 0);

% -------------------- 基本检查 --------------------
% 检查小区索引和用户索引是否越界，或者用户配置为空
if n_cell > size(user_para, 1) || n_user > size(user_para, 2) || isempty(user_para{n_cell, n_user})
    ueInfo.reason = 'user_not_found';   % 用户不存在
    return;
end
% 检查用户配置中是否包含 nr 结构和 pusch 字段
if ~isfield(user_para{n_cell, n_user}, 'nr') || ~isfield(user_para{n_cell, n_user}.nr, 'pusch')
    ueInfo.reason = 'nr_pusch_not_configured';   % 未配置 NR PUSCH
    return;
end

% 获取当前用户的完整配置和 PUSCH 配置
ueCfg = user_para{n_cell, n_user};
puschCfg = ueCfg.nr.pusch;

% 检查运行时激活标志：必须存在 runtime.active 且为 1 才处理
if ~isfield(puschCfg, 'runtime') || isempty(puschCfg.runtime) || ...
   ~isfield(puschCfg.runtime, 'active') || puschCfg.runtime.active == 0
    ueInfo.reason = 'pusch_not_active';
    return;
end

% -------------------- 构建 NR PUSCH 配置结构体 --------------------
puschNR = local_build_pusch_config(puschCfg, carrier, puschPrbSet);

% 验证层数不超过基站发送天线数（上行发送时 UE 天线数通常等于基站接收天线数，
% 但此处使用 carrier.NTxAnts 作为上限检查）
if puschNR.NumLayers > carrier.NTxAnts
    error('pusch_process_nr: NumLayers(%d) > NTxAnts(%d).', puschNR.NumLayers, carrier.NTxAnts);
end

% 调用 NR 适配器获取 PUSCH 资源索引以及相关信息（如 G、NREPerPRB 等）
[puschIndices, puschIndicesInfo] = nr_phy_adapter('pusch_indices', carrier, puschNR);
% 若未获取到有效索引，则记录实际使用的 PRB 集合并退出
if isempty(puschIndices)
    ueInfo.reason = 'empty_pusch_indices';
    % 将实际使用的 PRB 集合存回运行时，便于上层调试
    user_para{n_cell, n_user}.nr.pusch.runtime.EffectivePRBSet = puschNR.PRBSet;
    return;
end

% 获取目标码率（默认为 0.5）
targetCodeRate = local_get_field(puschCfg, 'TargetCodeRate', 0.5);
% 获取额外的开销（XOverhead），用于 TBS 计算
xOverhead = local_get_field(puschCfg, 'XOverhead', 0);
% 调用 NR 适配器计算传输块大小 TBS（单位：比特）
tbs = nr_phy_adapter('tbs', puschNR.Modulation, puschNR.NumLayers, ...
    numel(puschNR.PRBSet), puschIndicesInfo.NREPerPRB, targetCodeRate, xOverhead);
% 确保 TBS 为非负数
tbs = max(0, floor(double(tbs)));

% -------------------- 准备 HARQ 信息和传输块比特 --------------------
[harqInfo, transportBlock] = local_prepare_harq_and_tb(n_cell, n_user, puschCfg, tbs, n_frame, n_slot);
% 对传输块进行速率匹配，得到长度为 G 的编码比特序列
codedBits = local_rate_match_bits(transportBlock, puschIndicesInfo.G);
% 根据调制方式、编码比特和符号总数生成复数 PUSCH 符号
[puschSymbols, modulationSource] = local_generate_pusch_symbols(puschNR.Modulation, codedBits, numel(puschIndices));
% 调用 NR 适配器生成 DMRS 的索引和符号
[dmrsIndices, dmrsSymbols] = nr_phy_adapter('pusch_dmrs', carrier, puschNR);

% -------------------- 将 PUSCH 和 DMRS 映射到资源网格 --------------------
% 将 PUSCH 符号叠加到网格的对应位置（支持多天线端口）
txGridOut(puschIndices) = txGridOut(puschIndices) + puschSymbols;
% 若 DMRS 索引非空，则将 DMRS 符号也叠加到网格中
if ~isempty(dmrsIndices)
    txGridOut(dmrsIndices) = txGridOut(dmrsIndices) + dmrsSymbols;
end

% -------------------- 写回运行时信息至全局 user_para --------------------
% 记录实际生效的 PRB 集合（可能经过冲突解决）
user_para{n_cell, n_user}.nr.pusch.runtime.EffectivePRBSet = puschNR.PRBSet;
user_para{n_cell, n_user}.nr.pusch.runtime.transportBlock = transportBlock;
user_para{n_cell, n_user}.nr.pusch.runtime.transportBlockSize = tbs;
user_para{n_cell, n_user}.nr.pusch.runtime.HARQProcessID = harqInfo.HARQProcessID;
user_para{n_cell, n_user}.nr.pusch.runtime.RedundancyVersion = harqInfo.RedundancyVersion;
user_para{n_cell, n_user}.nr.pusch.runtime.puschIndicesInfo = puschIndicesInfo;
user_para{n_cell, n_user}.nr.pusch.runtime.G = puschIndicesInfo.G;
user_para{n_cell, n_user}.nr.pusch.runtime.modulationSource = modulationSource;

% 可选的调试缓存：若 user_data 存在且维度匹配，则保存中间比特和符号（上行专用字段）
if exist('user_data', 'var') && ~isempty(user_data) && ...
        n_cell <= size(user_data, 1) && n_user <= size(user_data, 2)
    user_data{n_cell, n_user}.trans_source_bits_nr_ul = transportBlock(:).';
    user_data{n_cell, n_user}.trans_raw_bits_nr_ul = codedBits(:).';
    user_data{n_cell, n_user}.modulated_symbols_nr_ul = puschSymbols(:).';
end

% 填充输出信息结构体
ueInfo.active = true;
ueInfo.reason = 'ok';
ueInfo.transportBlockSize = tbs;
ueInfo.HARQProcessID = harqInfo.HARQProcessID;
ueInfo.RedundancyVersion = harqInfo.RedundancyVersion;
ueInfo.G = puschIndicesInfo.G;
ueInfo.modulationSource = modulationSource;
ueInfo.puschIndicesCount = numel(puschIndices);
ueInfo.dmrsIndicesCount = numel(dmrsIndices);
end

%% ======================= 局部辅助函数 =======================
% 功能：从用户配置、载波参数和可选的 PRB 集合中构建 NR PUSCH 配置结构体
function puschNR = local_build_pusch_config(cfg, carrier, puschPrbSet)
puschNR = struct;
% 调制方式（默认 QPSK）
puschNR.Modulation = local_get_field(cfg, 'Modulation', 'QPSK');
% 层数（默认 1）
puschNR.NumLayers = local_get_field(cfg, 'NumLayers', 1);
% 映射类型（默认 'A'，时隙内连续符号映射）
puschNR.MappingType = local_get_field(cfg, 'MappingType', 'A');
% 小区 ID（默认 0）
puschNR.NID = local_get_field(cfg, 'NID', 0);
% RNTI（默认 1）
puschNR.RNTI = local_get_field(cfg, 'RNTI', 1);

% 获取运行时配置（可能包含动态的 PRBSet 和 SymbolSet）
rt = local_get_field(cfg, 'runtime', struct);
% 优先级：外部传入的 puschPrbSet > 运行时 PRBSet > 配置中的 PRBSet > 全部 PRB
if ~isempty(puschPrbSet)
    puschNR.PRBSet = unique(puschPrbSet(:).');
elseif isfield(rt, 'PRBSet') && ~isempty(rt.PRBSet)
    puschNR.PRBSet = unique(rt.PRBSet(:).');
else
    puschNR.PRBSet = unique(local_get_field(cfg, 'PRBSet', 0:(carrier.NSizeGrid-1)));
end

% 符号分配：优先使用运行时指定的连续符号集合，否则使用配置中的 SymbolAllocation
if isfield(rt, 'SymbolSet') && ~isempty(rt.SymbolSet)
    symSet = rt.SymbolSet(:).';
    % 要求运行时 SymbolSet 必须是连续整数序列
    if ~isequal(symSet, symSet(1):symSet(end))
        error('pusch_process_nr: runtime.SymbolSet must be contiguous.');
    end
    puschNR.SymbolAllocation = [symSet(1), numel(symSet)];
else
    % 默认分配整个时隙的所有符号（[0, SymbolsPerSlot]）
    puschNR.SymbolAllocation = local_get_field(cfg, 'SymbolAllocation', [0 carrier.SymbolsPerSlot]);
end

% DMRS 配置
puschNR.DMRS = local_get_field(cfg, 'dmrs', struct);
end

% 功能：准备 HARQ 相关信息并生成传输块比特（上行）
function [harqInfo, transportBlock] = local_prepare_harq_and_tb(n_cell, n_user, puschCfg, tbs, n_frame, n_slot)
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
% 若 PUSCH 配置中直接指定了 RV 序列，则优先使用
if isfield(puschCfg, 'RVSequence') && ~isempty(puschCfg.RVSequence)
    rvSeq = double(puschCfg.RVSequence(:).');
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

% 功能：生成指定长度的传输块比特序列（上行专用，优先使用 legacy pusch 字段）
function bits = local_generate_bits(n_cell, n_user, tbs, n_frame, n_slot)
globals_declare
bits = zeros(max(0, tbs), 1);
if tbs <= 0
    return;
end

% 尝试使用传统的 LTE source_bit_gen（如果存在传统 pusch 字段）
if isfield(user_para{n_cell, n_user}, 'pusch') && ~isempty(user_para{n_cell, n_user}.pusch)
    legacyPusch = user_para{n_cell, n_user}.pusch;
    % 检查是否存在必要字段 'CM' 和 'TBS_control'
    ok = isfield(legacyPusch, 'CM') && isfield(legacyPusch, 'TBS_control');
    if ok
        try
            % 调用遗留的源比特生成函数，输入 TBS 作为码字源大小和原始比特大小
            [src, legacyPusch] = source_bit_gen(legacyPusch, 1, tbs, tbs);
            % 回写可能更新的配置
            user_para{n_cell, n_user}.pusch = legacyPusch;
            % 速率匹配到目标长度 tbs
            bits = local_rate_match_bits(src(:), tbs);
            return;
        catch
            % 失败则回退到确定性随机比特
        end
    end
end

% 确定性随机比特生成（基于种子，保证可重复），与 PDSCH 使用不同的种子偏移（40000 vs 30000）
seed = 40000 + 97 * n_cell + 193 * n_user + 31 * n_frame + n_slot;
s = RandStream('mt19937ar', 'Seed', seed);
bits = randi(s, [0 1], tbs, 1);
end

% 功能：将编码比特调制为复数符号，长度适配到 expectedLen（与 PDSCH 类似，但函数名不同）
function [symbols, sourceTag] = local_generate_pusch_symbols(modName, codedBits, expectedLen)
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