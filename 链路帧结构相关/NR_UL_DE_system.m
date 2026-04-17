function nr_rx_result = NR_UL_DE_system(targetCellID, rx_signal, rx_signal0, n_unit)
% NR_UL_DE_system - NR上行接收链路解调解码系统（最小化实现）
%
% 功能描述：
%   本函数是NR上行接收处理的主入口，完成以下任务：
%     1) 对接收到的时域信号进行OFDM解调，得到频域资源网格；
%     2) 遍历小区内所有用户，检测当前时隙是否有活跃的PUSCH或PUCCH；
%     3) 对于活跃的PUSCH用户，提取对应的资源单元，进行DMRS信道估计、均衡、
%        符号解映射，得到软比特和硬判决比特；
%     4) 对于活跃的PUCCH用户，仅提取接收符号并计算平均功率（占位实现）；
%     5) 将处理结果缓存到用户和小区运行时结构体中。
%
% 当前范围与限制：
%   - 仅支持简单的基于DMRS的标量信道估计（一个平均复数系数）；
%   - 未实现完整的DLSCH解码（传输块解码），仅输出软/硬比特；
%   - 支持BPSK/QPSK/16QAM软解调，其他调制方式返回空；
%   - 依赖MATLAB 5G Toolbox进行PUSCH配置、索引生成、DMRS生成。
%
% 输入参数：
%   targetCellID : 目标小区ID（用于索引小区配置）
%   rx_signal    : 接收到的时域复信号（加噪声后的），尺寸 [Nr, Nsamp]
%   rx_signal0   : 理想无噪接收信号（仅经过信道），尺寸同rx_signal
%   n_unit       : 当前时隙号（NR中单元为时隙）
%
% 输出参数：
%   nr_rx_result : 结构体，包含处理状态、用户结果列表、频域网格等。

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量：cell_para, user_para, sys_para, sim_para等

% ========================== 1. 参数有效性检查 ==========================
% 根据小区ID获取小区索引
n_cell = getCellIndexfromID(targetCellID);
if isempty(n_cell)
    error('NR_UL_DE_system: invalid targetCellID.');
end

% 检查小区是否配置了NR参数
if ~isfield(cell_para{1,n_cell}, 'nr') || isempty(cell_para{1,n_cell}.nr)
    error('NR_UL_DE_system: cell_para{1,%d}.nr not configured.', n_cell);
end

% 列出需要使用的5G工具箱函数，确保它们存在
cellCfg = cell_para{1, n_cell};   % 小区配置
nrCfg = cellCfg.nr;               % NR子配置
n_slot = n_unit;                  % 时隙号（与输入参数n_unit相同）

% 检查NR运行时信息是否存在
if ~isfield(nrCfg, 'runtime') || isempty(nrCfg.runtime)
    error('NR_UL_DE_system: missing NR runtime. Please call sim_config_compute_nr first.');
end

% 确保当前时隙的链路方向为上行
if isfield(nrCfg.runtime, 'current_effective_link_type') && ...
        ~strcmpi(nrCfg.runtime.current_effective_link_type, 'UPLINK')
    error('NR_UL_DE_system: current slot is not UPLINK.');
end

n_frame = nrCfg.runtime.current_frame;   % 获取当前帧号

% ========================== 2. OFDM解调 ==========================
% 调用NR OFDM解调函数，将时域信号转换为频域资源网格
% rxGrid  : 加噪信号的频域网格（尺寸 [K, L, Nr]，K子载波数，L符号数，Nr接收天线数）
% rxGrid0 : 无噪信号的频域网格
rxGrid = NR_ofdm_demodulation(rx_signal, targetCellID, n_frame, n_slot);
rxGrid0 = NR_ofdm_demodulation(rx_signal0, targetCellID, n_frame, n_slot);

% ========================== 3. 构造5G工具箱载波配置对象 ==========================
carrier = struct;
carrier.NCellID = nrCfg.NCellID;                 % 小区ID
carrier.SubcarrierSpacing = nrCfg.scs / 1e3;     % 子载波间隔（kHz）
carrier.CyclicPrefix = 'normal';                 % 常规循环前缀
carrier.NSizeGrid = nrCfg.carrier.NSizeGrid;     % 载波带宽（RB数）
carrier.NStartGrid = nrCfg.carrier.NStartGrid;   % 载波起始RB索引
carrier.NSlot = n_slot;                          % 当前时隙号
carrier.NFrame = n_frame;                        % 当前帧号
carrier.SymbolsPerSlot = nrCfg.symbols_per_slot;
if isfield(cellCfg, 'BS_phy_antenna_num') && ~isempty(cellCfg.BS_phy_antenna_num)
    carrier.NTxAnts = cellCfg.BS_phy_antenna_num;
else
    carrier.NTxAnts = size(rxGrid,3);
end

% ========================== 4. 初始化返回结果结构体 ==========================
nr_rx_result = struct;
nr_rx_result.targetCellID = targetCellID;   % 目标小区ID
nr_rx_result.n_frame = n_frame;             % 帧号
nr_rx_result.n_slot = n_slot;               % 时隙号
nr_rx_result.rxGrid = rxGrid;               % 频域网格（含噪声）
nr_rx_result.rxGrid0 = rxGrid0;             % 无噪频域网格
nr_rx_result.users = [];                    % 用户处理结果列表
nr_rx_result.status = 'no_active_ul_user';  % 初始状态：无活跃上行用户

% ========================== 5. 遍历小区内所有用户 ==========================
cellUserIDList = cellCfg.userID_list;       % 当前小区的用户ID列表
userResults = cell(1, length(cellUserIDList));  % 预分配用户结果cell数组
hasActiveUser = false;                       % 是否有活跃用户标志

for iu = 1:length(cellUserIDList)
    userID = cellUserIDList(iu);
    [u_cell, u_user] = getUserIndexfromID(userID);   % 获取用户索引
    if isempty(u_cell) || isempty(u_user) || isempty(user_para{u_cell, u_user})
        continue;   % 用户不存在或未配置，跳过
    end

    ueCfg = user_para{u_cell, u_user};        % 用户配置结构体
    if ~isfield(ueCfg, 'nr')
        continue;   % 用户未配置NR参数，跳过
    end

    userResult = struct;                      % 初始化该用户的结果结构体
    userResult.userID = userID;
    userResult.pusch = [];
    userResult.pucch = [];
    userResult.status = 'inactive';

    % 检查该用户在当前时隙是否有活跃的PUSCH
    hasPusch = isfield(ueCfg.nr, 'pusch') && isfield(ueCfg.nr.pusch, 'runtime') && ...
        isfield(ueCfg.nr.pusch.runtime, 'active') && ueCfg.nr.pusch.runtime.active;

    % 检查是否有活跃的PUCCH
    hasPucch = isfield(ueCfg.nr, 'pucch') && isfield(ueCfg.nr.pucch, 'runtime') && ...
        isfield(ueCfg.nr.pucch.runtime, 'active') && ueCfg.nr.pucch.runtime.active;

    % -------------------- 5.1 PUSCH处理 --------------------
    if hasPusch
        hasActiveUser = true;   % 标记存在活跃用户
        % 调用局部函数进行PUSCH检测和解调
        puschResult = local_detect_pusch(carrier, rxGrid, rxGrid0, cellCfg, ueCfg);
        userResult.pusch = puschResult;
        userResult.status = 'pusch_demod_only';

        % 将处理结果存入用户运行时结构体（供后续使用或调试）
        user_para{u_cell, u_user}.nr.runtime.rxGrid = rxGrid;
        user_para{u_cell, u_user}.nr.runtime.rxGrid0 = rxGrid0;
        user_para{u_cell, u_user}.nr.runtime.last_ul_result = userResult;
        user_para{u_cell, u_user}.nr.pusch.runtime.rxSymbols = puschResult.rxSymbols;
        user_para{u_cell, u_user}.nr.pusch.runtime.eqSymbols = puschResult.eqSymbols;
        user_para{u_cell, u_user}.nr.pusch.runtime.softBits = puschResult.softBits;
        user_para{u_cell, u_user}.nr.pusch.runtime.hardBits = puschResult.hardBits;
        user_para{u_cell, u_user}.nr.pusch.runtime.channelEstimate = puschResult.Havg;
        user_para{u_cell, u_user}.nr.pusch.runtime.noiseVar = puschResult.noiseVar;
        user_para{u_cell, u_user}.nr.pusch.runtime.EVMRMS = puschResult.EVMRMS;
    end

    % -------------------- 5.2 PUCCH处理（占位实现） --------------------
    if hasPucch
        hasActiveUser = true;
        userResult.pucch = local_detect_pucch_placeholder(rxGrid, rxGrid0, ueCfg);
        if strcmp(userResult.status, 'inactive')
            userResult.status = 'pucch_placeholder_only';
        end
        % 将PUCCH检测结果存入用户运行时
        user_para{u_cell, u_user}.nr.pucch.runtime.lastDetect = userResult.pucch;
    end

    userResults{iu} = userResult;   % 收集结果
end   % 结束用户遍历

% ========================== 6. 组装最终返回结果 ==========================
if hasActiveUser
    nr_rx_result.status = 'ul_demod_only';   % 仅完成了上行解调（未解码）
end

% 过滤掉空的用户结果（即未处理或无效的用户）
nr_rx_result.users = userResults(~cellfun('isempty', userResults));

% 将本次上行接收结果存入小区运行时结构体
cell_para{1, n_cell}.nr.runtime.last_ul_result = nr_rx_result;

end   % 主函数结束

%% ======================= 局部函数：PUSCH检测与解调 =======================
function puschResult = local_detect_pusch(carrier, rxGrid, rxGrid0, cellCfg, ueCfg)
% 局部函数：对单个用户的PUSCH进行完整的接收处理
% 输入：
%   carrier : nrCarrierConfig对象
%   rxGrid  : 接收频域网格（含噪声）
%   rxGrid0 : 接收频域网格（无噪声）
%   cellCfg : 小区配置
%   ueCfg   : 用户配置
% 输出：
%   puschResult : 结构体，包含均衡后符号、软硬比特、信道估计、噪声方差等

% 构建PUSCH配置对象（基于用户配置和运行时）
puschNR = local_build_pusch_config(ueCfg, carrier);

% 获取PUSCH占用的RE索引以及资源信息
[puschIndices, puschIndicesInfo] = nr_phy_adapter('pusch_indices', carrier, puschNR);

% 获取PUSCH DMRS占用的RE索引
[dmrsIndices, dmrsSymbols] = nr_phy_adapter('pusch_dmrs', carrier, puschNR);

% 从接收网格中提取PUSCH数据符号（含噪声和无噪）
rxPusch = rxGrid(puschIndices);
rxPusch0 = rxGrid0(puschIndices);

% 提取DMRS接收符号（含噪声和无噪）
rxDmrs = rxGrid(dmrsIndices);
rxDmrs0 = rxGrid0(dmrsIndices);

% 获取发射端参考信号（用于EVM计算和信道估计）
% 优先从用户运行时获取发射网格，否则从小区的发射网格获取
txGrid = [];
refPusch = [];
refDmrs = [];
if isfield(ueCfg.nr.runtime, 'txGrid') && ~isempty(ueCfg.nr.runtime.txGrid)
    txGrid = ueCfg.nr.runtime.txGrid;
    refPusch = txGrid(puschIndices);      % 参考PUSCH符号
    refDmrs = txGrid(dmrsIndices);        % 参考DMRS符号
elseif isfield(cellCfg.nr.runtime, 'txGrid') && ~isempty(cellCfg.nr.runtime.txGrid)
    txGrid = cellCfg.nr.runtime.txGrid;
    refPusch = txGrid(puschIndices);
    refDmrs = txGrid(dmrsIndices);
else
    % 如果没有发射网格，则使用生成的DMRS符号作为参考
    refDmrs = dmrsSymbols;
end

% ---------- 基于DMRS的信道估计（标量平均） ----------
Hdmrs = [];   % 每个DMRS RE的信道估计
if ~isempty(refDmrs)
    valid = abs(refDmrs) > 0;   % 排除参考符号为零的位置
    if any(valid)
        % 最小二乘信道估计：接收无噪DMRS / 参考DMRS
        Hdmrs = rxDmrs0(valid) ./ refDmrs(valid);
    end
end

if isempty(Hdmrs)
    Havg = 1;   % 若无法估计，默认信道增益为1
else
    Havg = mean(Hdmrs(:));   % 对所有DMRS RE的信道估计取平均（标量）
end

% 防止除零
if abs(Havg) < 1e-12
    Havg = 1;
end

% ---------- 信道均衡（单抽头除法） ----------
eqPusch = rxPusch ./ Havg;      % 均衡后的数据符号（含噪声）
eqPusch0 = rxPusch0 ./ Havg;    % 均衡后的数据符号（无噪声，理想）

% ---------- 噪声方差估计 ----------
% 利用加噪信号与无噪信号的差值估计噪声
noiseVec = rxPusch - rxPusch0;
noiseVar = mean(abs(noiseVec(:)).^2);
if isnan(noiseVar) || isempty(noiseVar)
    noiseVar = 0;
end

% ---------- EVM计算（若存在参考符号） ----------
evmRms = [];
if ~isempty(refPusch)
    denom = max(mean(abs(refPusch).^2), eps);   % 参考符号的平均功率
    evmRms = sqrt(mean(abs(eqPusch - refPusch).^2) / denom);
end

% ---------- 符号解映射（软比特和硬判决） ----------
[hardBits, softBits] = local_symbol_demapper(eqPusch, ueCfg.nr.pusch.Modulation);

% ---------- 组装结果结构体 ----------
puschResult = struct;
puschResult.active = 1;
puschResult.PRBSet = ueCfg.nr.pusch.runtime.PRBSet;
puschResult.SymbolSet = ueCfg.nr.pusch.runtime.SymbolSet;
puschResult.DMRSSymbolSet = ueCfg.nr.pusch.runtime.DMRSSymbolSet;
% 有效PRB集合（可能存在跳频等情况，优先使用EffectivePRBSet）
if isfield(ueCfg.nr.pusch.runtime, 'EffectivePRBSet')
    puschResult.EffectivePRBSet = ueCfg.nr.pusch.runtime.EffectivePRBSet;
else
    puschResult.EffectivePRBSet = ueCfg.nr.pusch.runtime.PRBSet;
end
puschResult.Havg = Havg;                  % 平均信道估计
puschResult.Hdmrs = Hdmrs;                % 每个DMRS RE的信道估计
puschResult.noiseVar = noiseVar;          % 噪声方差估计
puschResult.rxSymbols = rxPusch;          % 接收的PUSCH符号（均衡前）
puschResult.rxSymbolsNoiseless = rxPusch0;% 无噪接收PUSCH符号
puschResult.eqSymbols = eqPusch;          % 均衡后的符号（含噪声）
puschResult.eqSymbolsNoiseless = eqPusch0;% 均衡后的无噪符号
puschResult.refSymbols = refPusch;        % 参考PUSCH符号（用于EVM）
puschResult.hardBits = hardBits;          % 硬判决比特
puschResult.softBits = softBits;          % 软比特（LLR近似）
puschResult.EVMRMS = evmRms;              % 均方根EVM
puschResult.transportBlock = [];          % 原始传输块（若有）
puschResult.transportBlockEstimate = [];  % 解码后估计的传输块（未实现）
puschResult.decodeImplemented = false;    % 解码未实现
puschResult.puschIndicesInfo = puschIndicesInfo; % 资源信息

% 若用户运行时中存有传输块（发射端），则将其保存到结果中
if isfield(ueCfg.nr.pusch.runtime, 'transportBlock')
    puschResult.transportBlock = ueCfg.nr.pusch.runtime.transportBlock;
end

end   % local_detect_pusch

%% ======================= 局部函数：PUCCH占位检测 =======================
function pucchResult = local_detect_pucch_placeholder(rxGrid, rxGrid0, ueCfg)
% 局部函数：PUCCH的占位接收处理（仅提取符号，不进行实际解码）
% 输入：
%   rxGrid  : 接收频域网格（含噪声）
%   rxGrid0 : 无噪频域网格
%   ueCfg   : 用户配置
% 输出：
%   pucchResult : 结构体，包含资源信息、接收符号、平均功率等

rt = ueCfg.nr.pucch.runtime;   % PUCCH运行时配置
pucchResult = struct;
pucchResult.active = 1;
pucchResult.PRBSet = rt.PRBSet;
pucchResult.SymbolSet = rt.SymbolSet;
pucchResult.DMRSSymbolSet = rt.DMRSSymbolSet;
pucchResult.Format = rt.Format;           % PUCCH格式
pucchResult.PayloadType = rt.PayloadType; % 载荷类型（如ACK/NACK, SR, CQI）
pucchResult.PayloadBits = rt.PayloadBits; % 原始载荷比特（发射端）
pucchResult.rxSymbols = [];
pucchResult.rxSymbolsNoiseless = [];
pucchResult.avgPower = [];
pucchResult.decodeImplemented = false;

% 若未配置PRB或符号集，则直接返回
if isempty(rt.PRBSet) || isempty(rt.SymbolSet)
    return;
end

% 提取PUCCH占用的所有RE上的接收符号
allSym = [];
allSym0 = [];
for iPrb = 1:length(rt.PRBSet)
    scBase = rt.PRBSet(iPrb) * 12;                % PRB起始子载波（0-based）
    scIdx = (scBase + 1):(scBase + 12);           % 该PRB内的子载波索引（1-based）
    for iSym = 1:length(rt.SymbolSet)
        sym = rt.SymbolSet(iSym);                 % 符号索引（0-based）
        % 提取该符号上该PRB内的所有子载波（所有天线，这里简单拼接）
        allSym = [allSym; rxGrid(scIdx, sym + 1, :)];    % 注意：这可能导致高维，但通常Nr=1
        allSym0 = [allSym0; rxGrid0(scIdx, sym + 1, :)];
    end
end

pucchResult.rxSymbols = allSym(:);          % 拉直为列向量
pucchResult.rxSymbolsNoiseless = allSym0(:);
if ~isempty(pucchResult.rxSymbols)
    pucchResult.avgPower = mean(abs(pucchResult.rxSymbols).^2);
end

end   % local_detect_pucch_placeholder

%% ======================= 局部函数：构建PUSCH配置对象 =======================
function puschNR = local_build_pusch_config(ueCfg, carrier)
% 局部函数：根据用户配置和运行时信息构造nrPUSCHConfig对象
% 输入：
%   ueCfg   : 用户配置结构体
%   carrier : nrCarrierConfig对象
% 输出：
%   puschNR : 配置好的PUSCH对象

puschNR = struct;
cfg = ueCfg.nr.pusch;          % 静态配置
rt = ueCfg.nr.pusch.runtime;   % 运行时动态配置

% 基本参数
puschNR.Modulation = cfg.Modulation;   % 调制方式
puschNR.NumLayers = cfg.NumLayers;     % 传输层数
puschNR.MappingType = cfg.MappingType; % 映射类型（A/B）
puschNR.NID = cfg.NID;                 % 扰码ID
puschNR.RNTI = cfg.RNTI;               % RNTI

% PRB分配：优先使用EffectivePRBSet（跳频等），其次PRBSet
if isfield(rt, 'EffectivePRBSet') && ~isempty(rt.EffectivePRBSet)
    puschNR.PRBSet = rt.EffectivePRBSet;
elseif isfield(rt, 'PRBSet') && ~isempty(rt.PRBSet)
    puschNR.PRBSet = rt.PRBSet;
else
    puschNR.PRBSet = cfg.PRBSet;
end

% 符号分配：要求运行时SymbolSet为连续区间
if isfield(rt, 'SymbolSet') && ~isempty(rt.SymbolSet)
    symSet = rt.SymbolSet(:).';
    if isequal(symSet, symSet(1):symSet(end))
        puschNR.SymbolAllocation = [symSet(1), numel(symSet)]; % [起始符号, 长度]
    else
        error('NR_UL_DE_system: runtime.SymbolSet is non-contiguous.');
    end
else
    puschNR.SymbolAllocation = cfg.SymbolAllocation;
end

% 配置DMRS
dmrs = struct;
dmrs.DMRSConfigurationType = cfg.dmrs.DMRSConfigurationType;
dmrs.DMRSLength = cfg.dmrs.DMRSLength;
dmrs.DMRSAdditionalPosition = cfg.dmrs.DMRSAdditionalPosition;
dmrs.DMRSTypeAPosition = cfg.dmrs.DMRSTypeAPosition;
dmrs.NumCDMGroupsWithoutData = cfg.dmrs.NumCDMGroupsWithoutData;
dmrs.DMRSPortSet = cfg.dmrs.DMRSPortSet;
dmrs.NIDNSCID = cfg.dmrs.NIDNSCID;
dmrs.NSCID = cfg.dmrs.NSCID;
puschNR.DMRS = dmrs;

% 若PRBSet为空，则默认使用整个载波带宽
if isempty(puschNR.PRBSet)
    puschNR.PRBSet = 0:(carrier.NSizeGrid-1);
end

end   % local_build_pusch_config

%% ======================= 局部函数：符号解映射（软/硬） =======================
function [hardBits, softBits] = local_symbol_demapper(sym, modulation)
% 局部函数：将复数调制符号解映射为软比特和硬判决比特
% 输入：
%   sym        : 均衡后的复数符号向量
%   modulation : 调制方式字符串，如 'QPSK', '16QAM', 'BPSK'
% 输出：
%   hardBits   : 硬判决比特（逻辑向量，0/1）
%   softBits   : 软比特（LLR近似值，实数值）
%
% 注意：软比特计算采用简化方法（未考虑噪声方差归一化），
%       对于QPSK和16QAM使用近似对数似然比。

switch upper(modulation)
    case 'BPSK'
        % BPSK: I分量决定比特，0->+1, 1->-1
        softBits = -real(sym);          % 软比特：负的I分量
        hardBits = softBits < 0;        % 硬判决：软比特<0则为1

    case 'QPSK'
        % QPSK: 两个比特，分别由I和Q分量的符号决定
        softBits = zeros(2 * numel(sym), 1);
        softBits(1:2:end) = -real(sym);   % 第1个比特的软信息
        softBits(2:2:end) = -imag(sym);   % 第2个比特的软信息
        hardBits = softBits < 0;

    case '16QAM'
        % 16QAM: 4个比特，映射顺序符合3GPP标准（格雷映射）
        % 星座点归一化因子 sqrt(10) 用于将平均功率归一化为1
        x = real(sym);
        y = imag(sym);
        softBits = zeros(4 * numel(sym), 1);
        % 比特0（I符号位）
        softBits(1:4:end) = -x;
        % 比特1（I幅度位）
        softBits(2:4:end) = 2/sqrt(10) - abs(x);
        % 比特2（Q符号位）
        softBits(3:4:end) = -y;
        % 比特3（Q幅度位）
        softBits(4:4:end) = 2/sqrt(10) - abs(y);
        hardBits = softBits < 0;

    otherwise
        % 不支持的调制方式，返回空
        softBits = zeros(0, 1);
        hardBits = zeros(0, 1);
end

end   % local_symbol_demapper
