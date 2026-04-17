function nr_rx_result = NR_DL_DE_system(rx_signal, rx_signal0, userID, n_unit)
% NR_DL_DE_system - NR下行接收解调解码系统（不依赖5G Toolbox）
%
% 功能描述：
%   本函数是NR用户设备（UE）下行接收处理的主入口，负责完成一个时隙（slot）内的
%   物理层接收处理。主要步骤包括：
%     1) 对接收时域信号进行OFDM解调，得到频域资源网格；
%     2) 检查当前用户在当前时隙是否有激活的PDSCH，若无则返回；
%     3) 提取PDSCH和DMRS资源单元（RE）的接收符号；
%     4) 基于DMRS进行最小二乘（LS）信道估计（标量平均）；
%     5) 单抽头均衡；
%     6) 计算噪声方差和EVM（若存在参考符号）；
%     7) 符号解映射得到软比特和硬判决比特；
%     8) 将结果缓存到用户运行时结构体中。
%
% 当前限制：
%   - 仅支持简单的标量信道估计（整个带宽使用一个平均复数系数）；
%   - 未实现完整的DLSCH解码（仅输出软/硬比特）；
%   - 支持BPSK/QPSK/16QAM/64QAM软解调；
%   - 完全依赖手工实现的NR物理层辅助函数（通过nr_phy_adapter调用），
%     不依赖MATLAB 5G Toolbox。
%
% 输入参数：
%   rx_signal  : 接收到的时域复信号（加噪声后的），尺寸 [Nr, Nsamp]
%   rx_signal0 : 理想无噪接收信号（仅经过信道），尺寸同rx_signal
%   userID     : 目标用户ID（用于索引用户配置）
%   n_unit     : 当前时隙号（NR中单元为时隙）
%
% 输出参数：
%   nr_rx_result : 结构体，包含处理状态、PDSCH结果、频域网格等。

% ========================== 全局变量声明 ==========================
globals_declare;   % 加载全局变量：cell_para, user_para, sim_para等

% ========================== 1. 用户索引获取与有效性检查 ==========================
% 根据用户ID获取其在全局cell_para和user_para中的索引
[n_cell, n_user] = getUserIndexfromID(userID);
if isempty(n_cell) || isempty(n_user)
    error('NR_DL_DE_system: invalid userID.');   % 用户不存在则报错
end

% 提取小区配置、用户配置和NR配置
cellCfg = cell_para{1, n_cell};
ueCfg = user_para{n_cell, n_user};
nrCfg = cellCfg.nr;
n_slot = n_unit;   % 时隙号

% 检查NR运行时信息是否存在（需预先调用sim_config_compute_nr）
if ~isfield(nrCfg, 'runtime') || isempty(nrCfg.runtime)
    error('NR_DL_DE_system: missing NR runtime. Please call sim_config_compute_nr first.');
end
% 确保当前时隙的链路方向为下行
if isfield(nrCfg.runtime, 'current_effective_link_type') && ...
        ~strcmpi(nrCfg.runtime.current_effective_link_type, 'DOWNLINK')
    error('NR_DL_DE_system: current slot is not DOWNLINK.');
end
n_frame = nrCfg.runtime.current_frame;   % 获取当前帧号

% ========================== 2. OFDM解调 ==========================
N_ID_CELL = cellCfg.cellID;   % 小区ID（用于OFDM解调函数）
% 调用NR OFDM解调函数，将时域信号转换为频域资源网格
% rxGrid  : 加噪信号的频域网格（尺寸 [K, L, Nr]，K子载波数，L符号数，Nr接收天线数）
% rxGrid0 : 无噪信号的频域网格
rxGrid = NR_ofdm_demodulation(rx_signal, N_ID_CELL, n_frame, n_slot);
rxGrid0 = NR_ofdm_demodulation(rx_signal0, N_ID_CELL, n_frame, n_slot);

% ========================== 3. 构造载波配置结构体（与手工辅助函数兼容） ==========================
carrier = struct;
carrier.NCellID = nrCfg.NCellID;                 % 小区ID
carrier.SubcarrierSpacing = nrCfg.scs / 1e3;     % 子载波间隔 (kHz)
carrier.CyclicPrefix = 'normal';                 % 常规循环前缀
carrier.NSizeGrid = nrCfg.carrier.NSizeGrid;     % 载波带宽（RB数）
carrier.NStartGrid = nrCfg.carrier.NStartGrid;   % 载波起始RB索引
carrier.NSlot = n_slot;                          % 当前时隙号
carrier.NFrame = n_frame;                        % 当前帧号
carrier.SymbolsPerSlot = nrCfg.symbols_per_slot; % 每时隙符号数
% 获取发射天线数：优先从小区配置读取，否则从接收网格第三维推断
if isfield(cellCfg, 'BS_phy_antenna_num') && ~isempty(cellCfg.BS_phy_antenna_num)
    carrier.NTxAnts = cellCfg.BS_phy_antenna_num;
else
    carrier.NTxAnts = size(rxGrid, 3);   % 接收网格的天线维数
end

% ========================== 4. 初始化返回结果结构体 ==========================
nr_rx_result = struct;
nr_rx_result.userID = userID;          % 用户ID
nr_rx_result.n_frame = n_frame;        % 帧号
nr_rx_result.n_slot = n_slot;          % 时隙号
nr_rx_result.rxGrid = rxGrid;          % 频域网格（含噪声）
nr_rx_result.rxGrid0 = rxGrid0;        % 无噪频域网格
nr_rx_result.pdsch = [];               % PDSCH处理结果（稍后填充）

% ========================== 5. 检查PDSCH是否活跃 ==========================
% 若用户未配置NR、未配置PDSCH、或无运行时激活标志，则直接返回
if ~isfield(ueCfg, 'nr') || ~isfield(ueCfg.nr, 'pdsch') || ~isfield(ueCfg.nr.pdsch, 'runtime') || ...
        ~isfield(ueCfg.nr.pdsch.runtime, 'active') || ueCfg.nr.pdsch.runtime.active == 0
    nr_rx_result.status = 'inactive_pdsch';   % 状态：PDSCH未激活
    % 保存网格到用户运行时，便于调试
    user_para{n_cell, n_user}.nr.runtime.rxGrid = rxGrid;
    user_para{n_cell, n_user}.nr.runtime.rxGrid0 = rxGrid0;
    user_para{n_cell, n_user}.nr.runtime.last_dl_result = nr_rx_result;
    return;   % 提前退出
end

% ========================== 6. PDSCH活跃用户的接收处理 ==========================
% 构建PDSCH配置结构体（基于用户配置和运行时）
pdschNR = local_build_pdsch_config(ueCfg, carrier);
% 通过适配器获取PDSCH占用的RE索引和DMRS索引/符号
[pdschIndices, pdschIndicesInfo] = nr_phy_adapter('pdsch_indices', carrier, pdschNR);
[dmrsIndices, dmrsSymbols] = nr_phy_adapter('pdsch_dmrs', carrier, pdschNR);

% 若无PDSCH或DMRS资源，则返回
if isempty(pdschIndices) || isempty(dmrsIndices)
    nr_rx_result.status = 'inactive_pdsch_resources';
    user_para{n_cell, n_user}.nr.runtime.rxGrid = rxGrid;
    user_para{n_cell, n_user}.nr.runtime.rxGrid0 = rxGrid0;
    user_para{n_cell, n_user}.nr.runtime.last_dl_result = nr_rx_result;
    return;
end

% 从接收网格中提取PDSCH数据符号（含噪声和无噪）
rxPdsch = rxGrid(pdschIndices);
rxPdsch0 = rxGrid0(pdschIndices);
% 提取DMRS接收符号（含噪声和无噪）
rxDmrs = rxGrid(dmrsIndices);
rxDmrs0 = rxGrid0(dmrsIndices);

% 获取发射端参考信号（用于信道估计和EVM计算）
txGrid = [];
refPdsch = [];
refDmrs = [];
if isfield(cellCfg.nr.runtime, 'txGrid') && ~isempty(cellCfg.nr.runtime.txGrid)
    txGrid = cellCfg.nr.runtime.txGrid;
    refPdsch = txGrid(pdschIndices);   % 参考PDSCH符号
    refDmrs = txGrid(dmrsIndices);     % 参考DMRS符号
else
    % 若无发射网格，则使用生成的DMRS符号作为参考（仅用于信道估计）
    refDmrs = dmrsSymbols;
end

% ---------- 基于DMRS的信道估计（标量平均） ----------
Hdmrs = [];   % 每个DMRS RE的信道估计值
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
eqPdsch = rxPdsch ./ Havg;      % 均衡后的数据符号（含噪声）
eqPdsch0 = rxPdsch0 ./ Havg;    % 均衡后的数据符号（无噪声，理想）

% ---------- 噪声方差估计 ----------
% 利用加噪信号与无噪信号的差值估计噪声
noiseVec = rxPdsch - rxPdsch0;
noiseVar = mean(abs(noiseVec(:)).^2);
if isnan(noiseVar) || isempty(noiseVar)
    noiseVar = 0;
end

% ---------- EVM计算（若存在参考符号） ----------
evmRms = [];
if ~isempty(refPdsch)
    denom = max(mean(abs(refPdsch).^2), eps);   % 参考符号的平均功率
    evmRms = sqrt(mean(abs(eqPdsch - refPdsch).^2) / denom);   % 均方根误差向量幅度
end

% ---------- 符号解映射（软比特和硬判决） ----------
[hardBits, softBits] = local_symbol_demapper(eqPdsch, ueCfg.nr.pdsch.Modulation);

% ---------- 组装PDSCH结果结构体 ----------
pdschResult = struct;
pdschResult.active = 1;
pdschResult.PRBSet = ueCfg.nr.pdsch.runtime.PRBSet;
pdschResult.SymbolSet = ueCfg.nr.pdsch.runtime.SymbolSet;
pdschResult.DMRSSymbolSet = ueCfg.nr.pdsch.runtime.DMRSSymbolSet;
pdschResult.Havg = Havg;                  % 平均信道估计
pdschResult.Hdmrs = Hdmrs;                % 每个DMRS RE的信道估计
pdschResult.noiseVar = noiseVar;          % 噪声方差估计
pdschResult.rxSymbols = rxPdsch;          % 接收的PDSCH符号（均衡前）
pdschResult.rxSymbolsNoiseless = rxPdsch0;% 无噪接收PDSCH符号
pdschResult.eqSymbols = eqPdsch;          % 均衡后的符号（含噪声）
pdschResult.eqSymbolsNoiseless = eqPdsch0;% 均衡后的无噪符号
pdschResult.refSymbols = refPdsch;        % 参考PDSCH符号（用于EVM）
pdschResult.hardBits = hardBits;          % 硬判决比特
pdschResult.softBits = softBits;          % 软比特（LLR近似）
pdschResult.EVMRMS = evmRms;              % 均方根EVM
pdschResult.transportBlock = [];          % 原始传输块（若有）
pdschResult.transportBlockEstimate = [];  % 解码后估计的传输块（未实现）
pdschResult.decodeImplemented = false;    % 解码未实现
pdschResult.pdschIndicesInfo = pdschIndicesInfo; % 资源信息

% 记录调制来源（来自发射端的记录，用于调试）
if isfield(ueCfg.nr.pdsch.runtime, 'modulationSource')
    pdschResult.modulationSource = ueCfg.nr.pdsch.runtime.modulationSource;
else
    pdschResult.modulationSource = 'UNKNOWN';
end
% 若用户运行时中存有传输块（发射端），则将其保存到结果中
if isfield(ueCfg.nr.pdsch.runtime, 'transportBlock')
    pdschResult.transportBlock = ueCfg.nr.pdsch.runtime.transportBlock;
end

% ---------- 组装最终返回结果 ----------
nr_rx_result.status = 'pdsch_demod_only';   % 状态：仅完成了PDSCH解调（未解码）
nr_rx_result.pdsch = pdschResult;

% ---------- 将处理结果缓存到用户运行时结构体 ----------
user_para{n_cell, n_user}.nr.runtime.rxGrid = rxGrid;
user_para{n_cell, n_user}.nr.runtime.rxGrid0 = rxGrid0;
user_para{n_cell, n_user}.nr.runtime.last_dl_result = nr_rx_result;
user_para{n_cell, n_user}.nr.pdsch.runtime.rxSymbols = rxPdsch;
user_para{n_cell, n_user}.nr.pdsch.runtime.eqSymbols = eqPdsch;
user_para{n_cell, n_user}.nr.pdsch.runtime.softBits = softBits;
user_para{n_cell, n_user}.nr.pdsch.runtime.hardBits = hardBits;
user_para{n_cell, n_user}.nr.pdsch.runtime.channelEstimate = Havg;
user_para{n_cell, n_user}.nr.pdsch.runtime.noiseVar = noiseVar;
user_para{n_cell, n_user}.nr.pdsch.runtime.EVMRMS = evmRms;

end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function pdschNR = local_build_pdsch_config(ueCfg, carrier)
% 局部函数：根据用户配置和运行时信息构造PDSCH配置结构体（普通结构体，非工具箱对象）
% 输入：ueCfg - 用户配置，carrier - 载波配置
% 输出：pdschNR - 包含PDSCH参数的普通结构体

pdschNR = struct;
cfg = ueCfg.nr.pdsch;      % 静态配置
rt  = ueCfg.nr.pdsch.runtime; % 运行时配置

% 基本参数
pdschNR.Modulation = cfg.Modulation;
pdschNR.NumLayers = cfg.NumLayers;
pdschNR.MappingType = cfg.MappingType;
pdschNR.NID = cfg.NID;
pdschNR.RNTI = cfg.RNTI;

% PRB集合：优先使用运行时指定的PRB集合
if isfield(rt, 'PRBSet') && ~isempty(rt.PRBSet)
    pdschNR.PRBSet = rt.PRBSet;
else
    pdschNR.PRBSet = cfg.PRBSet;
end

% 符号分配：运行时要求连续符号区间
if isfield(rt, 'SymbolSet') && ~isempty(rt.SymbolSet)
    symSet = rt.SymbolSet(:).';
    if isequal(symSet, symSet(1):symSet(end))
        pdschNR.SymbolAllocation = [symSet(1), numel(symSet)];
    else
        error('NR_DL_DE_system: runtime.SymbolSet is non-contiguous.');
    end
else
    pdschNR.SymbolAllocation = cfg.SymbolAllocation;
end

% DMRS配置
dmrs = struct;
dmrs.DMRSConfigurationType = cfg.dmrs.DMRSConfigurationType;
dmrs.DMRSLength = cfg.dmrs.DMRSLength;
dmrs.DMRSAdditionalPosition = cfg.dmrs.DMRSAdditionalPosition;
dmrs.DMRSTypeAPosition = cfg.dmrs.DMRSTypeAPosition;
dmrs.NumCDMGroupsWithoutData = cfg.dmrs.NumCDMGroupsWithoutData;
dmrs.DMRSPortSet = cfg.dmrs.DMRSPortSet;
dmrs.NIDNSCID = cfg.dmrs.NIDNSCID;
dmrs.NSCID = cfg.dmrs.NSCID;
pdschNR.DMRS = dmrs;

% PTRS配置（如果存在）
if isfield(cfg, 'ptrs')
    pdschNR.PTRS = cfg.ptrs;
end

% 若PRBSet为空，则默认使用整个载波带宽
if isempty(pdschNR.PRBSet)
    pdschNR.PRBSet = 0:(carrier.NSizeGrid-1);
end
end

function [hardBits, softBits] = local_symbol_demapper(sym, modulation)
% 局部函数：将复数调制符号解映射为软比特和硬判决比特
% 输入：
%   sym        : 均衡后的复数符号向量
%   modulation : 调制方式字符串，如 'BPSK', 'QPSK', '16QAM', '64QAM'
% 输出：
%   hardBits   : 硬判决比特（逻辑向量，0/1）
%   softBits   : 软比特（LLR近似值，实数值）
%
% 软比特计算采用简化方法（未考虑噪声方差归一化），
% 对于QPSK/16QAM/64QAM使用近似对数似然比。

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
        % 星座点归一化因子 sqrt(10)
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

    case '64QAM'
        % 64QAM: 6个比特，归一化因子 sqrt(42)
        x = real(sym);
        y = imag(sym);
        softBits = zeros(6 * numel(sym), 1);
        % 比特0（I符号位）
        softBits(1:6:end) = -x;
        % 比特1（I幅度位，第一级）
        softBits(2:6:end) = 4/sqrt(42) - abs(x);
        % 比特2（I幅度位，第二级）
        softBits(3:6:end) = 2/sqrt(42) - abs(abs(x) - 4/sqrt(42));
        % 比特3（Q符号位）
        softBits(4:6:end) = -y;
        % 比特4（Q幅度位，第一级）
        softBits(5:6:end) = 4/sqrt(42) - abs(y);
        % 比特5（Q幅度位，第二级）
        softBits(6:6:end) = 2/sqrt(42) - abs(abs(y) - 4/sqrt(42));
        hardBits = softBits < 0;

    otherwise
        % 不支持的调制方式，返回空
        softBits = zeros(0, 1);
        hardBits = zeros(0, 1);
end
end