function [dmrsIndices, dmrsSymbols, info] = nr_pdsch_dmrs_build(carrier, pdsch)
%NR_PDSCH_DMRS_BUILD Build NR PDSCH DMRS indices and symbols without Toolbox.
%   该函数在不依赖MATLAB 5G Toolbox的情况下，手动构建NR PDSCH的DMRS
%   （解调参考信号）的线性索引和复数符号。它根据载波配置（carrier）和
%   PDSCH配置（pdsch）生成所有DMRS资源单元（RE）的位置和对应的QPSK符号。
%
%   输入：
%       carrier - 载波配置结构体，至少应包含 NSizeGrid（RB数）、
%                 NTxAnts（可选，发射天线数）等字段。
%       pdsch   - PDSCH配置结构体，应包含 SymbolAllocation（符号分配）、
%                 DMRS（DMRS配置子结构体）、PRBSet（可选，PRB集合）等。
%   输出：
%       dmrsIndices  - DMRS占用的所有RE的线性索引（列向量），适用于
%                      维度为 [K, L, Nt] 的资源网格。
%       dmrsSymbols  - 对应每个索引的QPSK复数值符号（列向量）。
%       info         - 结构体，包含 DMRSSymbolSet（DMRS符号索引，0-based）、
%                      Comb（频域梳齿子载波索引，1-based）、Ports（端口列表）。

% ========================== 主函数体 ==========================
% 计算总子载波数（K = 12 * RB数）
K = 12 * carrier.NSizeGrid;
% 获取每个时隙的OFDM符号数（L），默认为14
L = local_symbols_per_slot(carrier);
% 安全获取DMRS配置，若不存在则使用空结构体
dmrsCfg = local_get_field(pdsch, 'DMRS', struct);
% 获取PDSCH分配的PRB集合（0-based索引）
prbSet = local_prb_set(pdsch, carrier);
% 计算DMRS占用的符号位置（0-based符号索引）
dmrsSymSet = local_pdsch_dmrs_symbols(pdsch.SymbolAllocation, dmrsCfg);
% 获取DMRS端口集合
ports = local_dmrs_ports(dmrsCfg);
% 确定资源网格的天线平面数（发射天线数或端口数中的较大者）
numPlanes = max(local_get_field(carrier, 'NTxAnts', numel(ports)), numel(ports));
% 根据DMRS配置类型获取频域梳齿子载波索引（1-based，PRB内）
comb = local_dmrs_comb(dmrsCfg);

% 预分配索引和符号数组（大小按最坏情况估算）
allIdx = zeros(max(1, numel(prbSet) * numel(dmrsSymSet) * numel(comb) * numel(ports)), 1);
allSym = complex(zeros(size(allIdx)));
ptr = 1;   % 当前填充位置的指针

% 三层循环：PRB → DMRS符号 → 端口
for ip = 1:numel(prbSet)
    prb = prbSet(ip);
    % 计算当前PRB内DMRS子载波的绝对索引（1-based）
    scAbs = prb * 12 + comb;
    for is = 1:numel(dmrsSymSet)
        sym0 = dmrsSymSet(is);          % 0-based符号索引
        sym1 = sym0 + 1;                % 1-based符号索引（用于sub2ind）
        for ipt = 1:numel(ports)
            % 天线平面索引：若发射天线数大于端口数，则每个端口映射到不同的天线平面；
            % 否则，多个端口可能映射到同一平面（简化处理，取 min）。
            plane = min(ipt, numPlanes);
            n = numel(scAbs);
            % 将子载波、符号、天线平面组合为线性索引（假设网格为 [K, L, numPlanes]）
            idx = sub2ind([K, L, numPlanes], scAbs(:), sym1 * ones(n,1), plane * ones(n,1));
            allIdx(ptr:ptr+n-1) = idx;
            % 为这些RE生成QPSK序列（基于端口、符号、PRB等计算的种子）
            allSym(ptr:ptr+n-1) = local_qpsk_sequence(n, local_dmrs_seed(carrier, ports(ipt), sym0, prb, 1000));
            ptr = ptr + n;
        end
    end
end

% 截取实际使用的部分
dmrsIndices = allIdx(1:ptr-1);
dmrsSymbols = allSym(1:ptr-1);
% 返回辅助信息
info = struct('DMRSSymbolSet', dmrsSymSet, 'Comb', comb, 'Ports', ports);

end   % 主函数结束

%% ======================= 局部辅助函数 =======================

function value = local_get_field(s, name, defaultValue)
% 安全地从结构体中获取字段值，若字段不存在或为空则返回默认值
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function L = local_symbols_per_slot(carrier)
% 获取每个时隙的OFDM符号数。优先使用 carrier.SymbolsPerSlot，
% 其次使用 carrier.NSymbols，否则默认为14（NR常规CP）。
if isfield(carrier, 'SymbolsPerSlot') && ~isempty(carrier.SymbolsPerSlot)
    L = carrier.SymbolsPerSlot;
elseif isfield(carrier, 'NSymbols') && ~isempty(carrier.NSymbols)
    L = carrier.NSymbols;
else
    L = 14;
end
end

function prbSet = local_prb_set(cfg, carrier)
% 获取PDSCH分配的PRB集合（0-based，行向量）。
% 若配置中未指定，则使用整个载波带宽的所有RB。
prbSet = local_get_field(cfg, 'PRBSet', []);
if isempty(prbSet)
    prbSet = 0:(carrier.NSizeGrid-1);
end
prbSet = unique(prbSet(:).');   % 确保是一维行向量且唯一
end

function comb = local_dmrs_comb(dmrsCfg)
% 根据DMRS配置类型返回频域梳齿子载波索引（1-based，PRB内）。
% Type1: 每个RB内DMRS占用6个子载波（索引1,3,5,7,9,11）；
% Type2: 每个RB内DMRS占用4个子载波（索引1,4,7,10）。
if local_get_field(dmrsCfg, 'DMRSConfigurationType', 1) == 1
    comb = [1 3 5 7 9 11];
else
    comb = [1 4 7 10];
end
end

function ports = local_dmrs_ports(dmrsCfg)
% 获取DMRS端口集合。若未指定，默认使用端口0。
ports = local_get_field(dmrsCfg, 'DMRSPortSet', 0);
ports = ports(:).';   % 确保为行向量
if isempty(ports)
    ports = 0;
end
end

function dmrsSym = local_pdsch_dmrs_symbols(symAlloc, dmrs)
% 计算PDSCH DMRS占用的符号位置（0-based符号索引）。
% 输入：
%   symAlloc : [起始符号, 持续符号数]，例如 [2,10]。
%   dmrs     : DMRS配置结构体。
% 输出：
%   dmrsSym  : DMRS符号索引数组（可能包含连续两个符号的DMRS）。
startSym = symAlloc(1);
nSym = symAlloc(2);
dataSymSet = startSym:(startSym+nSym-1);   % PDSCH占用的所有符号

% 若DMRS被禁用，返回空
if isfield(dmrs, 'enable') && strcmpi(dmrs.enable, 'NO')
    dmrsSym = [];
    return;
end

% TypeA DMRS起始符号（若未配置，默认为PDSCH起始符号）
l0 = local_get_field(dmrs, 'DMRSTypeAPosition', startSym);
% 根据附加位置确定候选符号
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
% 只保留落在PDSCH符号内的候选
dmrsSym = cand(ismember(cand, dataSymSet));
% 如果是双符号DMRS，每个位置扩展为连续两个符号
if local_get_field(dmrs, 'DMRSLength', 1) == 2
    dmrsSym = unique([dmrsSym dmrsSym+1]);
    dmrsSym = dmrsSym(ismember(dmrsSym, dataSymSet));
end
end

function seed = local_dmrs_seed(carrier, port, sym0, prb, offset)
% 为每个DMRS RE生成伪随机序列种子。
% 种子计算公式：offset + 97*NCellID + 29*port + 13*sym0 + prb
% 该公式用于保证不同小区、端口、符号、PRB的DMRS序列不同。
nCellId = local_get_field(carrier, 'NCellID', 0);
seed = offset + 97 * double(nCellId) + 29 * double(port) + 13 * double(sym0) + double(prb);
end

function seq = local_qpsk_sequence(N, seed)
% 生成N个QPSK调制符号（归一化功率，即每个符号幅值为1/√2）。
% 输入：
%   N    - 符号数量
%   seed - 随机种子（保证可重复性）
% 输出：
%   seq  - 复数值列向量，每个元素为 (±1 ± 1i)/√2。
% 实现：生成2N个随机比特，奇数为I路，偶数为Q路，映射为BPSK后组合。
s = RandStream('mt19937ar', 'Seed', seed);
b = randi(s, [0 1], 2 * N, 1);
b0 = 1 - 2 * b(1:2:end);   % I路：0->1, 1->-1
b1 = 1 - 2 * b(2:2:end);   % Q路：0->1, 1->-1
seq = (b0 + 1i * b1) / sqrt(2);
end